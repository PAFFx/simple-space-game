extends SceneTree

## Renders the cockpit and its pilot from a few fixed views, with scripted control input,
## and saves PNGs: a visual check for cockpit model / pilot pose changes.
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off
##   godot --path . --resolution 1280x720 -s Tools/Godot/cockpit_snapshot.gd -- <out_dir> [shots] [cockpit.tscn]
##
## shots: comma list of rest,input,lean,hatch (default all); also look, outline, external,
## markers, handles (the hatch lock / override handles and their interlock), rail (the rail
## grips through each of their motions). cockpit.tscn replaces the suit's cockpit.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

var _out := "user://cockpit_snapshot"
var _cockpit_scene := ""
var _cockpit: CockpitBase
var _pilot: SeatedPilot
var _animator: CockpitControlsAnimator
var _input := PilotInputSource.new()
var _debug_cam: Camera3D
var _fp_cam: PilotCamera


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var shots := PackedStringArray(["rest", "input", "lean", "hatch"])
	if args.size() > 1:
		shots = args[1].split(",")
	if args.size() > 2:
		_cockpit_scene = args[2]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred(shots)


func _run(shots: PackedStringArray) -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for look in stage.find_children("*", "", true, false):
		if "capture_on_ready" in look:
			look.set("capture_on_ready", false)
	if _cockpit_scene != "":
		_swap_cockpit(stage)
	# The suit's own input reads the real sticks: make it inert, so it holds still.
	for n in stage.find_children("*", "", true, false):
		if n is PilotInputSource:
			n.set_script(PilotInputSource)
	root.add_child(stage)
	await _frames(20)
	# The look controller pans with the real mini-stick: the views set the look themselves.
	for look in stage.find_children("*", "MouseLookController", true, false):
		look.set_process(false)
		look.set_process_input(false)
	var vehicle: VehicleBase
	for n in stage.find_children("*", "", true, false):
		if n is VehicleBase:
			vehicle = n
			break
	_cockpit = vehicle.get_cockpit()
	_fp_cam = _cockpit.get_player_camera() as PilotCamera
	_pilot = _cockpit.find_child("Pilot", true, false) as SeatedPilot
	_animator = _cockpit.find_child("ControlsAnimator", true, false) as CockpitControlsAnimator
	_animator.input_source = _input
	_debug_cam = Camera3D.new()
	_debug_cam.cull_mask = Layers.COCKPIT | Layers.PILOT | Layers.DEBUG
	_debug_cam.near = 0.02
	_debug_cam.fov = 60.0
	_cockpit.add_child(_debug_cam)
	if _pilot != null:
		for mesh: MeshInstance3D in _pilot.find_children("*", "MeshInstance3D", true, false):
			if mesh.layers == 0 and SeatedPilot._matches(mesh, _pilot.head_meshes):
				mesh.layers = Layers.DEBUG   # the debug camera sees the head, the pilot's eye doesn't
				mesh.visible = true

	if "markers" in shots:
		_show_markers()
	if "rest" in shots:
		await _views("rest")
	if "outline" in shots:
		await _frames(10)
		var loadout := vehicle.find_component(MsLoadout) as MsLoadout
		var fcs := vehicle.find_component(FireControl)
		if fcs != null:
			fcs.set_physics_process(false)   # it would lower the shield again
		for eq in loadout.equipment:
			if eq is MsShield:
				eq.set_active(true)   # shield to guard
		await _views("outline_rest")
		await _frames(240)
		await _views("outline")
		# The same views with the shield itself drawn in the sensor image, to compare.
		vehicle.get_sensor_head().set_group_visible(Layers.VEHICLE_EXT, true)
		await _views("outline_real")
		vehicle.get_sensor_head().set_group_visible(Layers.VEHICLE_EXT, false)
	if "input" in shots:
		var cmd := PilotCommand.new()
		cmd.translation = Vector3(0, 1, -1)   # forward + up: both sticks forward, right pedal
		_input.last_command = cmd
		await _frames(30)
		await _views("fwd_up")
		cmd = PilotCommand.new()
		cmd.rotation = Vector3(1, 1, 0)        # yaw left + pitch up: sticks opposed and twisted
		cmd.translation = Vector3(0, -1, 0)
		_input.last_command = cmd
		await _frames(30)
		await _views("yaw_pitch_down")
		_input.last_command = PilotCommand.new()
	if "rail" in shots:
		for pose in [["slide_fwd", Vector3(0, 0, -1), Vector3.ZERO], ["slide_back", Vector3(0, 0, 1), Vector3.ZERO],
				["yaw_left", Vector3.ZERO, Vector3(0, 1, 0)], ["pitch_up", Vector3.ZERO, Vector3(1, 0, 0)],
				["pitch_down", Vector3.ZERO, Vector3(-1, 0, 0)], ["roll_right", Vector3.ZERO, Vector3(0, 0, -1)],
				["strafe_right", Vector3(1, 0, 0), Vector3.ZERO], ["up", Vector3(0, 1, 0), Vector3.ZERO],
				["down", Vector3(0, -1, 0), Vector3.ZERO], ["brake", Vector3.ZERO, Vector3.ZERO, 1],
				["brake_full", Vector3.ZERO, Vector3.ZERO, 2]]:
			var cmd := PilotCommand.new()
			cmd.translation = pose[1]
			cmd.rotation = pose[2]
			cmd.brake = pose.size() > 3
			cmd.brake_full = pose.size() > 3 and pose[3] == 2
			_input.last_command = cmd
			await _frames(40)
			await _rail_views(pose[0])
		_input.last_command = PilotCommand.new()
		await _frames(40)
		await _rail_views("rest")
	if "lean" in shots and _pilot != null:
		_pilot.set_physics_process(false)
		_pilot.lean = Vector2(_pilot.max_lean_deg, _pilot.max_lean_deg)
		await _frames(5)
		await _views("lean")
		_pilot.lean = Vector2.ZERO
		_pilot.set_physics_process(true)
	if "external" in shots:
		# The suit from outside, on a camera of its own in the suit's frame.
		var cam := Camera3D.new()
		cam.cull_mask = Layers.MASK_THIRD_PERSION
		cam.fov = 40.0
		vehicle.add_child(cam)
		cam.make_current()
		for view in [["front", Vector3(14, 16, -34), Vector3(0, 12, 0)], ["back", Vector3(-16, 20, 34), Vector3(0, 12, 0)],
				["chest", Vector3(5, 18, -12), Vector3(0, 16.5, 0)], ["leg", Vector3(7, 7, -11), Vector3(1.5, 6, 0)],
				["shoulder", Vector3(-9, 21, -9), Vector3(-3.5, 18, 0)], ["pack", Vector3(-8, 22, 12), Vector3(0, 18, 2)]]:
			cam.transform = Transform3D(Basis.IDENTITY, view[1]).looking_at(view[2], Vector3.UP)
			await _shot("external_" + view[0])
		cam.queue_free()
	if "look" in shots:
		# The pilot's eye and body for looks to the side, behind and down.
		for look in [[0, 0], [90, -10], [150, -10], [-150, -20], [0, -75], [60, -60]]:
			_fp_cam.make_current()
			_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(look[0])) * Basis(Vector3.RIGHT, deg_to_rad(look[1])))
			await _shot("look_%d_%d_fp" % [look[0], -look[1]])
			_debug_cam.make_current()
			_debug_cam.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 0.45, -1.15)).looking_at(Vector3(0, -0.2, -0.05), Vector3.UP)
			await _shot("look_%d_%d_front" % [look[0], -look[1]])
		_fp_cam.set_look_rotation(Basis.IDENTITY)
		_fp_cam.make_current()
	if "handles" in shots:
		# The hatch lock and override handles beside the cushion, and their interlock.
		var hatch := vehicle.find_component(CockpitHatch) as CockpitHatch
		var parts := vehicle.find_children("*", "HatchCockpitParts", true, false)[0] as HatchCockpitParts
		await _handle_views("handles_locked")
		parts._on_override(-1)
		await _frames(30)
		print("HANDLES override pulled with the lock down: override_up %s, hatch open %s" % [parts.override_up, hatch.is_open()])
		parts._on_lock(-1)
		await _frames(40)
		await _handle_views("handles_unlocked")
		parts._on_override(-1)
		await _frames(30)
		print("HANDLES both pulled: hatch open %s" % hatch.is_open())
		await _handle_views("handles_open")
		parts._on_lock(1)
		await _frames(10)
		print("HANDLES lock pushed with the override up: lock_up %s" % parts.lock_up)
		parts._on_override(1)
		await _frames(int(hatch.duration * 60.0) + 40)
		print("HANDLES override pushed: hatch open %s, unsealed %s" % [hatch.is_open(), hatch.is_unsealed()])
	if "hatch" in shots:
		var hatch := vehicle.find_component(CockpitHatch) as CockpitHatch
		if hatch != null:
			hatch.open()
			await _frames(int(hatch.duration * 60.0) + 40)
			await _views("hatch")
	quit()


## Puts `_cockpit_scene` in place of the suit's cockpit, under the same name.
func _swap_cockpit(stage: Node) -> void:
	for n in stage.find_children("*", "", true, false):
		if n is CockpitBase:
			var replacement := (load(_cockpit_scene) as PackedScene).instantiate()
			var parent := n.get_parent()
			replacement.name = n.name
			replacement.transform = (n as Node3D).transform
			parent.remove_child(n)
			n.free()
			parent.add_child(replacement)
			replacement.owner = stage
			return


## The right grip and hand close by, and both from the pilot's eye looking down.
func _rail_views(tag: String) -> void:
	_fp_cam.make_current()
	_fp_cam.set_look_rotation(Basis(Vector3.RIGHT, deg_to_rad(-55)))
	await _shot("rail_%s_fp" % tag)
	_fp_cam.set_look_rotation(Basis.IDENTITY)
	await _frames(20)
	_debug_cam.make_current()
	var seat := _pilot.transform if _pilot != null else Transform3D.IDENTITY
	var at := Vector3(0.3, -0.34, -0.22)
	for view in [["side", Vector3(0.75, -0.3, -0.24)], ["front", Vector3(0.42, -0.2, -0.65)], ["top", Vector3(0.3, 0.1, -0.2)],
			["feet", Vector3(0.55, -0.7, -0.45)]]:
		var look_at := at if view[0] != "feet" else Vector3(0, -0.8, -0.5)
		_debug_cam.transform = seat * Transform3D(Basis.IDENTITY, view[1]).looking_at(look_at, Vector3.UP if view[0] != "top" else Vector3.FORWARD)
		await _shot("rail_%s_%s" % [tag, view[0]])
	_fp_cam.make_current()


## Debug: a green ball on every Hand*/Foot* marker and a red one on the bone that should
## be there (wrist / ankle), drawn through everything.
func _show_markers() -> void:
	var sk := _pilot.find_child("Skeleton3D", true, false) as Skeleton3D
	var pose := sk.find_child("SeatedPilotPose", true, false) as SeatedPilotPose
	for pair in [["HandL", pose.arm_bones[2]], ["HandR", pose.arm_bones[5]],
			["FootL", pose.leg_bones[2]], ["FootR", pose.leg_bones[5]]]:
		var marker := _cockpit.find_child(pair[0], true, false) as Node3D
		marker.add_child(_ball(Color.GREEN, 0.012))
		var attach := BoneAttachment3D.new()
		attach.bone_name = pair[1]
		sk.add_child(attach)
		attach.add_child(_ball(Color.RED, 0.016 / sk.global_basis.get_scale().x))


func _ball(color: Color, radius: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 10
	mesh.material_override = mat
	mesh.layers = Layers.DEBUG
	return mesh


## The hatch handles from the pilot's eye and from close by, in the seat's frame.
func _handle_views(tag: String) -> void:
	_fp_cam.make_current()
	_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(-58)) * Basis(Vector3.RIGHT, deg_to_rad(-60)))
	await _shot(tag + "_fp")
	_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(-75)) * Basis(Vector3.RIGHT, deg_to_rad(-70)))
	await _shot(tag + "_fp_lean")
	_fp_cam.set_look_rotation(Basis.IDENTITY)
	_debug_cam.make_current()
	var seat := _pilot.transform if _pilot != null else Transform3D.IDENTITY
	var at := Vector3(0.27, -0.625, -0.18)
	for view in [["close", Vector3(0.62, -0.5, -0.32)], ["out", Vector3(0.55, -0.62, -0.05)], ["above", Vector3(0.12, -0.33, -0.12)]]:
		_debug_cam.transform = seat * Transform3D(Basis.IDENTITY, view[1]).looking_at(at, Vector3.UP)
		await _shot(tag + "_" + view[0])
	_fp_cam.make_current()


func _views(tag: String) -> void:
	_fp_cam.make_current()
	_fp_cam.set_look_rotation(Basis.IDENTITY)
	await _shot(tag + "_fp")
	_fp_cam.set_look_rotation(Basis(Vector3.RIGHT, deg_to_rad(-48)))
	await _shot(tag + "_fp_down")
	_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(-55)) * Basis(Vector3.RIGHT, deg_to_rad(-40)))
	await _shot(tag + "_fp_right")
	# Toward the shield (left) and back over the left shoulder at the fin funnels.
	_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(60)) * Basis(Vector3.RIGHT, deg_to_rad(-25)))
	await _shot(tag + "_fp_shield")
	_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(150)) * Basis(Vector3.RIGHT, deg_to_rad(15)))
	await _shot(tag + "_fp_funnels")
	_fp_cam.set_look_rotation(Basis.IDENTITY)
	if tag.begins_with("outline"):
		for look in [[75, -10], [75, -45], [40, -30], [30, 0], [60, 15], [100, -20]]:
			_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(look[0])) * Basis(Vector3.RIGHT, deg_to_rad(look[1])))
			await _shot("%s_fp_left%d_%d" % [tag, look[0], -look[1]])
		for yaw in [100, 180, 215]:
			_fp_cam.set_look_rotation(Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(20)))
			await _shot("%s_fp_back%d" % [tag, yaw])
		_fp_cam.set_look_rotation(Basis.IDENTITY)
		return
	_debug_cam.make_current()
	for view in [["front", Vector3(0.75, 0.15, -1.0)], ["side", Vector3(1.15, -0.2, -0.1)],
			["back", Vector3(-0.7, 0.35, 0.95)], ["top", Vector3(0.05, 1.1, -0.35)],
			["hand", Vector3(0.42, -0.12, -0.52)], ["hand_top", Vector3(0.2, 0.05, -0.2)],
			["hand_in", Vector3(0.02, -0.33, -0.4)], ["hand_out", Vector3(0.62, -0.33, -0.3)], ["feet", Vector3(0.5, -0.75, -0.85)],
			["feet_side", Vector3(0.75, -0.8, -0.42)]]:
		var eye: Vector3 = view[1]
		var target := Vector3(0, -0.4, -0.2)
		if (view[0] as String).begins_with("hand"):
			target = Vector3(0.3, -0.33, -0.27)
		elif (view[0] as String).begins_with("feet"):
			target = Vector3(0, -0.85, -0.45)
		# In the seat's frame, so the views follow the seat when it turns for the hatch.
		var seat := _pilot.transform if _pilot != null else Transform3D.IDENTITY
		_debug_cam.transform = seat * Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)
		await _shot(tag + "_" + view[0])
	# Orthographic side views (0.6 m tall), for measuring fit: feet and hand.
	_debug_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_debug_cam.size = 0.6
	for view in [["ortho_feet", Vector3(0, -0.8, -0.45)], ["ortho_hand", Vector3(0, -0.35, -0.2)]]:
		var at: Vector3 = view[1]
		var seat := _pilot.transform if _pilot != null else Transform3D.IDENTITY
		_debug_cam.transform = seat * Transform3D(Basis.IDENTITY, at + Vector3(0.75, 0, 0)).looking_at(at, Vector3.UP)
		await _shot(tag + "_" + view[0])
	_debug_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_fp_cam.make_current()


func _shot(file: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, file])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
