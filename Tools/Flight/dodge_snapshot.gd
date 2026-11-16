extends SceneTree

## Renders a sideways dodge from a world-fixed camera behind the suit: the old full-boost
## strafe (no break) and the break (tap of full boost), frame by frame from the same start.
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 -s Tools/Flight/dodge_snapshot.gd -- <out_dir> [direction=right|diag]

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const TIMES := [0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0]

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		return cmd

var _out := "user://dodge_snapshot"
var _direction := "right"
var _suit: RigidBody3D
var _law: RateCommandControlLaw
var _input := ScriptedInput.new()
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	for arg in args:
		if arg.begins_with("direction="):
			_direction = arg.get_slice("=", 1)
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
	await _ticks(10)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
	var fc := (_suit as Node as VehicleBase).find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_law = fc.control_law as RateCommandControlLaw
	await _ticks(90)
	var start := _suit.global_transform
	_cam = Camera3D.new()
	_cam.cull_mask = Layers.MASK_THIRD_PERSION
	_cam.fov = 50.0
	_cam.far = 20000.0
	current_scene.add_child(_cam)
	var basis := start.basis.orthonormalized()
	var target := start.origin + basis * Vector3(7, 13, 0)
	_cam.global_position = start.origin + basis * Vector3(6, 20, -44)
	_cam.look_at(target, basis.y)
	_cam.make_current()
	for mode in ["strafe", "break"]:
		_suit.global_transform = start
		_suit.linear_velocity = Vector3.ZERO
		_suit.angular_velocity = Vector3.ZERO
		_input.cmd = PilotCommand.new()
		await _ticks(150)
		_law.break_on_full_boost = mode == "break"
		var dir := Vector3.RIGHT if _direction == "right" else Vector3(1, 1, 0).normalized()
		var t := 0.0
		var k := 0
		while k < TIMES.size():
			var cmd := PilotCommand.new()
			cmd.translation = dir
			# The strafe holds full boost; the break is a tap of it, the stick held.
			cmd.boost_full = mode == "strafe" or t < 0.1
			cmd.boost = cmd.boost_full
			_input.cmd = cmd
			if t >= TIMES[k] - 1e-4:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%02d.png" % [_out, mode, k])
				k += 1
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
		_input.cmd = PilotCommand.new()
	_law.break_on_full_boost = true
	quit()


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
