extends SceneTree

## How far does the ν get out of the way? From rest, a kick (dodge press with a direction:
## pintle burst) against slamming the stick to full boost, per direction. Reports the
## distance along the direction at a few times, the stray across it, peak and mean
## acceleration over the kick, the attitude change, and the propellant the kick took.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Flight/kick_probe.gd -- \
##       [dirs=right,up,left,down,fwd,back,diag] [modes=kick,slam] [factor=4] [accel=0]
##       [time=0.3] [reserve=300] [refill=40] [after=1.5]
##
## factor / accel / time / reserve / refill override burst_thrust_factor, dodge_accel_g,
## dodge_time, burst_reserve_capacity and burst_refill_flow. after: seconds to watch the
## kick tank refill afterwards (0 = don't).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const TIMES := [0.1, 0.2, 0.3, 0.4, 0.5]
const DIRS := {
	"right": Vector3.RIGHT, "left": Vector3.LEFT, "up": Vector3.UP, "down": Vector3.DOWN,
	"fwd": Vector3.FORWARD, "back": Vector3.BACK, "diag": Vector3(1, 1, 0),
}

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		return cmd

var _suit: RigidBody3D
var _fc: FlightComputer
var _law: RateCommandControlLaw
var _input := ScriptedInput.new()
var _dirs := PackedStringArray(["right", "up", "left", "down", "fwd", "back", "diag"])
var _modes := PackedStringArray(["kick", "slam"])
var _overrides := {}
var _after := 1.5


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"dirs": _dirs = value.split(",")
			"modes": _modes = value.split(",")
			"factor": _overrides["burst_thrust_factor"] = float(value)
			"reserve": _overrides["burst_reserve_capacity"] = float(value)
			"refill": _overrides["burst_refill_flow"] = float(value)
			"accel": _overrides["dodge_accel_g"] = float(value)
			"time": _overrides["dodge_time"] = float(value)
			"after": _after = float(value)
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
	var vehicle := _suit as Node as VehicleBase
	_fc = vehicle.find_component(FlightComputer) as FlightComputer
	_fc.add_child(_input)
	_fc.input_source = _input
	_law = _fc.control_law as RateCommandControlLaw
	for key: String in _overrides:
		if key in _fc:
			_fc.set(key, _overrides[key])
		else:
			_law.set(key, _overrides[key])
	_fc.burst_reserve = _fc.burst_reserve_capacity
	await _ticks(60)
	print("ν %.1f t, pintles ×%.1f (Isp %d → %d s), kick %.2f s, cap %s, tank %.0f kg (min %.0f), refill %.0f kg/s" % [
			_suit.mass / 1000.0, _fc.burst_thrust_factor, roundi(_fc.specific_impulse),
			roundi(_fc.specific_impulse / maxf(_fc.burst_thrust_factor, 1.0)), _law.dodge_time,
			"%.0f G" % _law.dodge_accel_g if _law.dodge_accel_g > 0.0 else "none",
			_fc.burst_reserve_capacity, _fc.burst_min_reserve, _fc.burst_refill_flow])
	var head := "%-5s %-4s |" % ["dir", "mode"]
	for t: float in TIMES:
		head += " %4.1fs" % t
	print(head + " | stray  peak G  mean G | turn° | Δv m/s | kg (tank)")
	for mode in _modes:
		for name in _dirs:
			await _case(mode, name)
	quit()


func _case(mode: String, name: String) -> void:
	var start := _suit.global_transform
	_input.cmd = PilotCommand.new()
	_input.cmd.brake = true
	await _ticks(30)
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO
	_fc.burst_reserve = _fc.burst_reserve_capacity
	await _ticks(30)
	var basis0 := _suit.global_basis.orthonormalized()
	var dir: Vector3 = basis0 * (DIRS[name] as Vector3).normalized()
	var p0 := _com()
	var v_prev := _suit.linear_velocity
	var fuel0 := _fc.propellant
	var tank0 := _fc.burst_reserve
	var dt := 1.0 / Engine.physics_ticks_per_second
	var line := "%-5s %-4s |" % [name, mode]
	var peak := 0.0
	var accel_sum := 0.0
	var accel_n := 0
	var stray := 0.0
	var turn := 0.0
	var next := 0
	var t := 0.0
	var kick_time := _law.dodge_time
	while next < TIMES.size():
		_input.cmd = PilotCommand.new()
		if mode == "kick":
			# The press with the stick half out, then hands off: only the kick pushes.
			if t < dt * 0.5:
				_input.cmd.translation = DIRS[name] as Vector3 * 0.5
				_input.cmd.dodge = true
		else:
			_input.cmd.translation = (DIRS[name] as Vector3).normalized()
			_input.cmd.analog_thrust = true
		await physics_frame
		t += dt
		var v := _suit.linear_velocity
		var a := (v - v_prev).length() / dt / FlightComputer.G0
		v_prev = v
		peak = maxf(peak, a)
		if t <= kick_time + 1e-6:
			accel_sum += a
			accel_n += 1
		var d := _com() - p0
		stray = maxf(stray, (d - dir * d.dot(dir)).length())
		turn = maxf(turn, rad_to_deg(basis0.get_rotation_quaternion().angle_to(_suit.global_basis.get_rotation_quaternion())))
		if t >= TIMES[next] - 1e-6:
			line += " %5.1f" % d.dot(dir)
			next += 1
	var used := fuel0 - _fc.propellant
	line += " | %5.2f  %6.1f  %6.1f | %5.1f | %6.1f | %5.0f (%3.0f)" % [stray, peak, accel_sum / maxi(accel_n, 1),
			turn, _suit.linear_velocity.dot(dir), used, tank0 - _fc.burst_reserve]
	print(line)
	if mode == "kick" and _after > 0.0:
		var low := _fc.burst_reserve
		_input.cmd = PilotCommand.new()
		await _ticks(roundi(_after / dt))
		print("      tank %.0f → %.0f kg in %.1f s coasting" % [low, _fc.burst_reserve, _after])
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO


func _com() -> Vector3:
	return _suit.to_global(_suit.center_of_mass)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
