extends SceneTree

## Renders a kick (dodge, pintles open) against a full-boost strafe the same way, plus the
## engine page during and after the kick, to PNGs.
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 --fixed-fps 60 -s Tools/Flight/kick_fx_snapshot.gd -- <out_dir> [views]
##
## views: comma list of the VIEWS below (default right,back). Each kick shot is a fresh kick
## left from rest, captured after the given number of ticks.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
## Eye / target in the suit's frame (front −Z, right +X). A kick left fires the right side.
const VIEWS := {
	right = [Vector3(46, 17, -6), Vector3(0, 15, 0)],
	back = [Vector3(22, 22, 40), Vector3(0, 15, 2)],
	front = [Vector3(28, 18, -40), Vector3(0, 15, 0)],
}
const KICK_TICKS := [2, 4, 8, 14]

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	var hold := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.translation = hold.translation
		cmd.boost = hold.boost
		cmd.boost_full = hold.boost_full
		cmd.brake = hold.brake
		return out

var _out := "user://kick_fx"
var _views := PackedStringArray(["right", "back"])
var _vehicle: VehicleBase
var _suit: RigidBody3D
var _fc: FlightComputer
var _input := ScriptedInput.new()
var _ext: Camera3D
var _start: Transform3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_views = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
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
	_suit = _vehicle as Node as RigidBody3D
	_fc = _vehicle.find_component(FlightComputer) as FlightComputer
	_fc.add_child(_input)
	_fc.input_source = _input
	for eq in _vehicle.find_children("*", "MsEquipment", true, false):
		if "Funnel" in eq.name or "Bazooka" in eq.name:
			(eq as Node3D).visible = false
	_ext = Camera3D.new()
	_ext.cull_mask = Layers.MASK_THIRD_PERSION
	_ext.fov = 40.0
	_ext.far = 20000.0
	_vehicle.add_child(_ext)
	_ext.make_current()
	await _frames(60)
	_start = _suit.global_transform

	for view in _views:
		_place(view)
		# Full-boost strafe left, settled, for comparison.
		await _reset()
		_input.hold.translation = Vector3.LEFT
		_input.hold.boost = true
		_input.hold.boost_full = true
		await _ticks(30)
		await _capture("%s_boost" % view)
		_input.hold = PilotCommand.new()
		for n: int in KICK_TICKS:
			await _reset()
			_input.cmd.translation = Vector3.LEFT * 0.6
			_input.cmd.dodge = true
			await _ticks(n)
			await _capture("%s_kick_%02d" % [view, n])
	# Engine page: mid-kick, right after, and refilling.
	await _reset()
	_input.cmd.translation = Vector3.LEFT * 0.6
	_input.cmd.dodge = true
	for step in [[10, "kick"], [20, "after"], [120, "refill"], [300, "full"]]:
		await _ticks(step[0] as int)
		await _engine_page("engine_%s" % step[1])
	quit()


func _place(view: String) -> void:
	var v: Array = VIEWS[view]
	_ext.transform = Transform3D(Basis.IDENTITY, v[0]).looking_at(v[1], Vector3.UP)


func _reset() -> void:
	_input.hold = PilotCommand.new()
	_input.hold.brake = true
	await _ticks(40)
	_suit.global_transform = _start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO
	_fc.burst_reserve = _fc.burst_reserve_capacity
	_input.hold = PilotCommand.new()
	await _ticks(20)


func _capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, file])


func _engine_page(file: String) -> void:
	var displays := _vehicle.find_children("*", "CockpitDisplays", true, false)
	if displays.is_empty():
		push_warning("kick_fx_snapshot: no CockpitDisplays")
		return
	var cd := displays[0] as CockpitDisplays
	var page: MfdPage = cd.pages.get("ScreenLeft")
	var vp := page.get_parent() as SubViewport
	page.queue_redraw()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s.png" % [_out, file])
	print("%s: kick tank %.0f kg, Isp %.0f s, flow %.0f kg/s" % [file, _fc.burst_reserve, _fc.get_effective_isp(), _fc.mass_flow])


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame
