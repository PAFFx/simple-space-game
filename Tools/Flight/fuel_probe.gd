extends SceneTree

## Where does the propellant go? Flies a few manoeuvres from rest (no dodges) and reports, for
## each, the propellant used, the average flow, and how much of the burnt impulse moved the
## suit (|m·Δv| plus what turning cost is not counted: efficiency = m·|Δv| / (propellant ·
## Isp · g0)). Also the flow sitting still.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Flight/fuel_probe.gd -- \
##       [scale=1.0] [cases=idle,cruise_fwd,boost_fwd,full_fwd,boost_right,full_right,yaw,pitch,brake]
##       [seconds=4]
##
## scale multiplies every thruster's rating at runtime (the capability map is rebuilt).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := PilotCommand.new()
		out.translation = cmd.translation
		out.rotation = cmd.rotation
		out.boost = cmd.boost
		out.boost_full = cmd.boost_full
		out.analog_thrust = cmd.analog_thrust
		out.brake = cmd.brake
		return out

var _suit: RigidBody3D
var _fc: FlightComputer
var _input := ScriptedInput.new()
var _scale := 1.0
var _seconds := 4.0
var _cases := PackedStringArray(["idle", "cruise_fwd", "boost_fwd", "full_fwd", "boost_right",
		"full_right", "yaw", "pitch", "brake"])


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"scale": _scale = float(value)
			"cases": _cases = value.split(",")
			"seconds": _seconds = float(value)
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
	if _scale != 1.0:
		for t in _fc.thrusters:
			t.max_thrust *= _scale
		_fc.invalidate_capability_map()
	await _ticks(90)
	var total := 0.0
	for t in _fc.thrusters:
		total += t.max_thrust
	print("ν %.1f t, thrust ×%.2f (%.2f MN in all), Isp %d s, propellant %.0f kg; %.1f s per case" % [
			_suit.mass / 1000.0, _scale, total / 1e6, roundi(_fc.specific_impulse), _fc.propellant, _seconds])
	print("%-11s | %8s %8s | %6s %6s | %s" % ["case", "kg", "kg/s", "Δv", "eff", "to empty at this rate"])
	for c in _cases:
		await _case(c)
	quit()


func _case(name: String) -> void:
	var start := _suit.global_transform
	_input.cmd = PilotCommand.new()
	_input.cmd.brake = true
	await _ticks(60)
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO
	_input.cmd = PilotCommand.new()
	await _ticks(30)
	var c := PilotCommand.new()
	match name:
		"cruise_fwd":
			c.translation = Vector3.FORWARD * 0.5
			c.analog_thrust = true
		"boost_fwd":
			c.translation = Vector3.FORWARD
			c.boost = true
		"full_fwd":
			c.translation = Vector3.FORWARD
			c.boost = true
			c.boost_full = true
		"boost_right":
			c.translation = Vector3.RIGHT
			c.boost = true
		"full_right":
			c.translation = Vector3.RIGHT
			c.boost = true
			c.boost_full = true
		"yaw":
			c.rotation = Vector3(0, 1, 0)
		"pitch":
			c.rotation = Vector3(1, 0, 0)
	var brake_case := name == "brake"
	if brake_case:
		# Get going first (not counted), then the stop is measured.
		var go := PilotCommand.new()
		go.translation = Vector3.FORWARD
		go.boost = true
		_input.cmd = go
		await _ticks(90)
		c.brake = true
	_input.cmd = c
	var fuel0 := _fc.propellant
	var v0 := _suit.linear_velocity
	var steps := roundi(_seconds * Engine.physics_ticks_per_second)
	await _ticks(steps)
	var used := fuel0 - _fc.propellant
	var dv := (_suit.linear_velocity - v0).length()
	var impulse := used * _fc.specific_impulse * FlightComputer.G0
	var eff := _suit.mass * dv / impulse if impulse > 1.0 else 0.0
	var rate := used / _seconds
	var empty := "%d:%02d" % [int(_fc.propellant / rate) / 60, int(_fc.propellant / rate) % 60] if rate > 0.01 else "-"
	print("%-11s | %8.1f %8.2f | %6.1f %5.0f%% | %s" % [name, used, rate, dv, eff * 100.0, empty])
	_input.cmd = PilotCommand.new()
	_input.cmd.brake = true
	await _ticks(90)
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
