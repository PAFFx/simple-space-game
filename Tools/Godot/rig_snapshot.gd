extends SceneTree

## Renders the RX-93's rig at work to PNGs: the rifle held at the corners of its envelope
## (collarbone / wrist assist, shoulder armour following the arm), the shield missile pose,
## the shield guard, and the main nozzle cups swinging sideways in a boosted strafe.
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 -s Tools/Godot/rig_snapshot.gd -- <out_dir> [shots]
##
## shots: comma list of rest,rifle,wide,cockpit,missile,guard,nozzle (default all but wide).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const RIFLE_AIMS := [Vector2(0, 0), Vector2(-35, 0), Vector2(75, 0), Vector2(0, 55), Vector2(0, -50), Vector2(-35, 40)]
# "wide" shot: corners past the current envelope, to see what the rig can reach.
const WIDE_AIMS := [Vector2(-55, 0), Vector2(90, 0), Vector2(0, 65), Vector2(0, -60),
		Vector2(-55, 45), Vector2(85, 50), Vector2(-45, -45), Vector2(85, -45)]
# Eye / target in the suit's frame (front −Z, right +X).
const VIEWS := {
	front = [Vector3(-14, 22, -42), Vector3(0, 15, 0)],
	right = [Vector3(40, 20, -18), Vector3(0, 15, 0)],
	top = [Vector3(0, 52, -20), Vector3(0, 15, 0)],
	left = [Vector3(-40, 18, -14), Vector3(0, 15, 0)],
	back = [Vector3(10, 22, 34), Vector3(0, 16, 3)],
	dead_front = [Vector3(0, 15, -48), Vector3(0, 14, 0)],
	pods = [Vector3(0, 21, 15), Vector3(0, 16.4, 3.4)],
	# Down the cups' sideways swing axis, so the swing shows as a turn in the picture.
	pods_axis = [Vector3(0, 26.0, 12.5), Vector3(0, 16.3, 3.6)],
	shoulder_front = [Vector3(-6, 21, -22), Vector3(0, 16.5, 0)],
	# Close on the right shoulder and the held rifle.
	rshoulder_side = [Vector3(16, 17, -6), Vector3(4, 16, -2)],
	rshoulder_front = [Vector3(9, 19, -16), Vector3(4, 16, -1)],
	rshoulder_top = [Vector3(5, 27, -5), Vector3(4, 16.5, -1)],
	shoulder_right = [Vector3(20, 20, -8), Vector3(3, 16.5, 0)],
	shoulder_top = [Vector3(2, 34, -10), Vector3(0, 17, 0)],
	shoulder_left = [Vector3(-20, 19, -6), Vector3(-3, 16, 0)],
}

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	var hold := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.translation = hold.translation
		cmd.boost = hold.boost
		cmd.boost_full = hold.boost_full
		cmd.shield_block = hold.shield_block
		return out

var _out := "user://rig_snapshot"
var _vehicle: VehicleBase
var _fcs: FireControl
var _input := ScriptedInput.new()
var _ext: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var shots := PackedStringArray(["rest", "rifle", "cockpit", "missile", "guard", "nozzle"])
	if args.size() > 1:
		shots = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred(shots)


func _run(shots: PackedStringArray) -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _frames(20)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_vehicle = node
	var fc := _vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = _vehicle.find_component(FireControl) as FireControl
	_ext = Camera3D.new()
	_ext.cull_mask = Layers.MASK_THIRD_PERSION
	_ext.fov = 40.0
	_ext.far = 20000.0
	_vehicle.add_child(_ext)
	_ext.make_current()

	if "rest" in shots:
		for v in ["front", "right", "back"]:
			await _shot("rest_" + v, v)

	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _frames(60)
	if "rifle" in shots:
		var rifle := _fcs.get_weapon(&"beam_rifle")
		for aim: Vector2 in RIFLE_AIMS:
			rifle.aim_override = aim
			await _frames(120)
			var tag := "rifle_%d_%d" % [aim.x, aim.y]
			print("RIG %s aim %s" % [tag, rifle.aim])
			for v in ["shoulder_front", "shoulder_right", "shoulder_top", "rshoulder_side", "rshoulder_front", "rshoulder_top"]:
				await _shot("%s_%s" % [tag, v], v)
		rifle.aim_override = null

	if "wide" in shots:
		var rifle := _fcs.get_weapon(&"beam_rifle")
		var limits := [rifle.az_limits, rifle.el_limits]
		rifle.az_limits = Vector2(-90, 120)
		rifle.el_limits = Vector2(-90, 90)
		for aim: Vector2 in WIDE_AIMS:
			rifle.aim_override = aim
			await _frames(150)
			var tag := "wide_%d_%d" % [aim.x, aim.y]
			print("RIG %s aim %s" % [tag, rifle.aim])
			for v in ["shoulder_front", "shoulder_right", "shoulder_top"]:
				await _shot("%s_%s" % [tag, v], v)
		rifle.aim_override = null
		rifle.az_limits = limits[0]
		rifle.el_limits = limits[1]

	if "guardaim" in shots:
		# Shield up while the rifle aims: where it starts to cross the shield.
		_input.hold.shield_block = true
		var rifle := _fcs.get_weapon(&"beam_rifle")
		var limits := [rifle.guard_az_limits, rifle.guard_el_limits]
		rifle.guard_az_limits = Vector2.ZERO
		rifle.guard_el_limits = Vector2.ZERO
		for aim: Vector2 in [Vector2(-30, 0), Vector2(-15, 0), Vector2(0, 0), Vector2(15, 0), Vector2(0, 40), Vector2(0, -40), Vector2(-15, 30)]:
			rifle.aim_override = aim
			await _frames(150)
			print("RIG guardaim %s aim %s masked %s" % [aim, rifle.aim, rifle.masked])
			for v in ["dead_front", "top"]:
				await _shot("guardaim_%d_%d_%s" % [aim.x, aim.y, v], v)
		rifle.aim_override = null
		rifle.guard_az_limits = limits[0]
		rifle.guard_el_limits = limits[1]
		_input.hold.shield_block = false
		await _frames(60)

	if "cockpit" in shots:
		# The pilot's view with the rifle up at the boresight: how much it covers.
		await _frames(120)
		var fp := _vehicle.get_cockpit().get_player_camera()
		fp.make_current()
		await _frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/cockpit_rifle.png" % _out)
		_ext.make_current()

	if "missile" in shots:
		_input.cmd.weapon_select = FireControl.Hat.LEFT
		await _frames(10)
		var missiles := _fcs.get_weapon(&"shield_missile")
		for aim: Vector2 in [Vector2(0, 0), Vector2(-60, 0), Vector2(25, 30)]:
			missiles.aim_override = aim
			await _frames(140)
			for v in ["shoulder_front", "shoulder_left", "shoulder_top"]:
				await _shot("missile_%d_%d_%s" % [aim.x, aim.y, v], v)
		missiles.aim_override = null

	if "guard" in shots:
		_input.hold.shield_block = true
		await _frames(90)
		var face := _fcs.get_weapon(&"shield_guard").get_muzzle()
		var dir := _vehicle.global_basis.orthonormalized().inverse() * -face.global_basis.z
		print("RIG guard face %s (az/el %s)" % [dir, SpatialMath.direction_to_angles(dir)])
		for v in ["dead_front", "front", "shoulder_front", "left", "right", "top"]:
			await _shot("guard_" + v, v)
		_input.hold.shield_block = false
		await _frames(30)

	if "nozzle" in shots:
		_input.cmd.master_mode = FireControl.MasterMode.NAV
		var guards := _vehicle.find_component(ThrusterGuards) as ThrusterGuards
		for eq in _vehicle.find_children("*", "MsEquipment", true, false):
			if "Funnel" in eq.name or "Bazooka" in eq.name:
				(eq as Node3D).visible = false
		await _frames(60)
		await _shot("nozzle_idle_pods", "pods_axis")
		for dir in [["right", Vector3.RIGHT], ["left", Vector3.LEFT]]:
			_input.hold.translation = dir[1]
			_input.hold.boost = true
			_input.hold.boost_full = true
			await _frames(40)
			var line := "RIG nozzle %s:" % dir[0]
			for i in guards.guards.size():
				var g := guards.guards[i]
				if g.follow_yaw:
					line += " %s %.1f°" % [g.bone_name, rad_to_deg(guards.angles[i])]
			print(line)
			for v in ["pods_axis", "pods"]:
				await _shot("nozzle_%s_%s" % [dir[0], v], v)
			_input.hold.translation = Vector3.ZERO
			_input.hold.boost = false
			_input.hold.boost_full = false
			await _frames(90)
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
