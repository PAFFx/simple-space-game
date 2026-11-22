extends SceneTree

## Renders the rifle draw (MsDrawMotion) frozen at chosen points to PNGs, from several
## sides, and tiles them: rows = views, columns = progress (0 stowed, 1 the grab, 2 held).
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 -s Tools/Godot/draw_snapshot.gd -- <out_dir> [p=0,0.5,1,1.3,1.6,1.85,2] [views=back,right,top,backleft] [raised] [nofunnels]
##
## `raised` adds a column with the rifle up on the boresight; `nofunnels` hides the backpack
## equipment (it covers the back views). Prints DRAW lines: progress, muzzle, wrist.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const VIEWS := {
	back = [Vector3(9, 15, 20), Vector3(1.5, 12.5, 2)],
	right = [Vector3(24, 13, -2), Vector3(3, 11, 0)],
	top = [Vector3(5, 36, 6), Vector3(2, 12, 0.5)],
	grip = [Vector3(12, 14, 13), Vector3(3.5, 12.5, 3)],
	hip = [Vector3(18, 12, 10), Vector3(4, 11.5, 1.5)],
	skirt = [Vector3(3, 12.5, 14), Vector3(1.2, 12.0, 2.0)],
	hatch = [Vector3(3.5, 17.5, 8.5), Vector3(1.4, 13.6, 1.9)],
	rshoulder = [Vector3(17, 19, 8), Vector3(4, 16.5, 1)],
	mocap = [Vector3(17, 6, -5), Vector3(3, 14, 1)],
	skirtside = [Vector3(12, 12.5, 9), Vector3(1.6, 12.0, 2.0)],
	hipfront = [Vector3(16, 12, -12), Vector3(4.5, 11.5, 0)],
	gripside = [Vector3(16, 11, 4), Vector3(3.5, 12.5, 2.5)],
	backleft = [Vector3(-16, 14, 18), Vector3(1, 11, 2)],
	front = [Vector3(8, 14, -26), Vector3(2, 11, 0)],
	backlow = [Vector3(6, 4, 22), Vector3(2, 9, 2)],
}

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		return out

var _out := "user://draw_snapshot"
var _input := ScriptedInput.new()
var _ext: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred(args.slice(1))


func _run(args: PackedStringArray) -> void:
	var progress := PackedFloat32Array([0.0, 0.5, 1.0, 1.3, 1.6, 1.85, 2.0])
	var views := PackedStringArray(["back", "right", "top", "backleft"])
	var raised := false
	var funnels := true
	var hide_rifle := false
	for a in args:
		if a.begins_with("p="):
			progress = PackedFloat32Array(Array(a.substr(2).split(",")).map(func(x: String) -> float: return x.to_float()))
		elif a.begins_with("views="):
			views = a.substr(6).split(",")
		elif a == "raised":
			raised = true
		elif a == "nofunnels":
			funnels = false
		elif a == "norifle":
			hide_rifle = true
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _frames(20)
	var vehicle: VehicleBase
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			vehicle = node
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	var fcs := vehicle.find_component(FireControl) as FireControl
	var loadout := vehicle.find_component(MsLoadout) as MsLoadout
	var rifle := fcs.get_weapon(&"beam_rifle")
	var eq := rifle.equipment
	if hide_rifle:
		for vi in eq.find_children("*", "VisualInstance3D", true, false):
			(vi as VisualInstance3D).visible = false
	if not funnels:
		for e in loadout.equipment:
			if "Funnel" in e.name or "Bazooka" in e.name:
				e.visible = false
	# Only the suit: the station and planet clutter the stills.
	for node in stage.find_children("*", "VisualInstance3D", true, false):
		if not vehicle.is_ancestor_of(node):
			(node as VisualInstance3D).visible = false
	_ext = Camera3D.new()
	_ext.cull_mask = Layers.MASK_THIRD_PERSION
	_ext.fov = 40.0
	_ext.far = 20000.0
	vehicle.add_child(_ext)
	_ext.make_current()

	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _frames(2)
	loadout.draw_frozen = true
	var cols: Array[String] = []
	for p in progress:
		loadout.set_draw_progress(eq, p)
		await _frames(45)
		var tag := "p%03d" % roundi(p * 100.0)
		var muzzle := rifle.get_muzzle().global_position
		var to_body := vehicle.global_transform.affine_inverse()
		print("DRAW %s muzzle %s rifle %s" % [tag, (to_body * muzzle).snapped(Vector3.ONE * 0.01),
				(to_body * eq.global_position).snapped(Vector3.ONE * 0.01)])
		var ambac := vehicle.find_component(AmbacController) as AmbacController
		var line := "DRAW %s ambac" % tag
		for i in ambac.joints.size():
			if ambac.joints[i].group == &"arm_r" or ambac.joints[i].group == &"torso":
				line += " %s %.0f" % [ambac.joints[i].bone_name, rad_to_deg(ambac.angles[i])]
		var anim := vehicle.find_component(MsPoseAnimator) as MsPoseAnimator
		print(line, " | low %.2f ready %.2f readiness %.2f aimw %.2f active %s pose %s" % [anim.get_layer_weight(&"rifle_low"),
				anim.get_layer_weight(&"rifle_ready"), rifle.readiness, rifle.aim_weight, eq.active, eq.active_pose])
		for v in views:
			await _shot("%s_%s" % [tag, v], v)
		cols.append(tag)
	if raised:
		loadout.set_draw_progress(eq, 2.0)
		rifle.aim_override = Vector2.ZERO
		_input.cmd.lock_nearest = true
		await _frames(90)
		for v in views:
			await _shot("up_%s" % v, v)
		cols.append("up")
	var files := PackedStringArray()
	for v in views:
		for c in cols:
			files.append("%s/%s_%s.png" % [_out, c, v])
	var sheet := FileAccess.open("%s/files.txt" % _out, FileAccess.WRITE)
	sheet.store_string("%d\n%s" % [cols.size(), "\n".join(files)])
	quit()


func _shot(file: String, view: String) -> void:
	var v: Array = VIEWS[view]
	_ext.transform = Transform3D(Basis.IDENTITY, v[0]).looking_at(v[1], Vector3.UP)
	await _frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, file])


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame
