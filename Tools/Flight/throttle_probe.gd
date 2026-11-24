extends SceneTree

## The analog throttle curve as flown: for each stick travel (forward, from rest), the
## acceleration the suit actually reaches (average over 0.6–1.4 s) and the boost level the
## control law reports (0 cruise, 1 boost, 2 full).
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Flight/throttle_probe.gd -- \
##       [travel=10,20,30,40,50,60,70,80,90,95,100] [deadzone=0.08] [expo=<TwinStickPilotInput's>]
##
## travel is the physical stick travel in %; deadzone and expo the twin-stick input's
## translation shaping (the law sees the travel past the deadzone, through the expo).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := PilotCommand.new()
		out.translation = cmd.translation
		out.analog_thrust = cmd.analog_thrust
		out.brake = cmd.brake
		return out

var _suit: RigidBody3D
var _fc: FlightComputer
var _input := ScriptedInput.new()
var _travel := PackedFloat32Array([10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100])
var _deadzone := 0.08
var _expo := -1.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"travel": _travel = PackedFloat32Array(Array(value.split(",")).map(func(s): return float(s)))
			"deadzone": _deadzone = float(value)
			"expo": _expo = float(value)
	if _expo < 0.0:
		var stick := TwinStickPilotInput.new()
		_expo = stick.translation_expo
		stick.free()
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
	_fc = (_suit as Node as VehicleBase).find_component(FlightComputer) as FlightComputer
	_fc.add_child(_input)
	_fc.input_source = _input
	await _ticks(90)
	print("expo %.2f, deadzone %.2f" % [_expo, _deadzone])
	print("%6s | %6s | %7s | %s" % ["travel", "law", "accel G", "boost"])
	for p in _travel:
		await _case(p)
	quit()


func _case(percent: float) -> void:
	var start := _suit.global_transform
	_input.cmd = PilotCommand.new()
	_input.cmd.brake = true
	await _ticks(60)
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO
	await _ticks(30)
	var u := clampf((percent / 100.0 - _deadzone) / (1.0 - _deadzone), 0.0, 1.0)
	u = JoyDevices.shape(u, 0.0, _expo)
	var c := PilotCommand.new()
	c.translation = Vector3.FORWARD * u
	c.analog_thrust = true
	_input.cmd = c
	var hz := Engine.physics_ticks_per_second
	await _ticks(roundi(0.6 * hz))
	var v0 := _suit.linear_velocity
	var level := _fc.control_law.get_boost_level()
	await _ticks(roundi(0.8 * hz))
	var accel := (_suit.linear_velocity - v0).length() / 0.8 / FlightComputer.G0
	print("%5.0f%% | %6.3f | %7.2f | %d" % [percent, u, accel, level])
	_input.cmd = PilotCommand.new()
	_input.cmd.brake = true
	await _ticks(120)
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
