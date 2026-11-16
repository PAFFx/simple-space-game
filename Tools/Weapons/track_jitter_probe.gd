extends SceneTree

## How much the sensor track wanders on a still target with the suit still: the error of
## the estimate (position, velocity, acceleration) and how fast the aim direction it gives
## jitters. That jitter is what the arms, the head vulcans, the shield and the attitude
## hold follow.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Weapons/track_jitter_probe.gd -- \
##       [ranges=30,60,100,300,1000] [seconds=4]

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		return out

var _suit: RigidBody3D
var _fcs: FireControl
var _input := ScriptedInput.new()
var _ranges := PackedFloat64Array([30.0, 60.0, 100.0, 300.0, 1000.0])
var _seconds := 4.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"ranges": _ranges = _floats(value)
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
	var vehicle := _suit as Node as VehicleBase
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = vehicle.find_component(FireControl) as FireControl
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	_input.cmd.master_arm = 1
	await _ticks(60)
	print("still drone (7 m), still suit; RMS of the estimate's error and of the aim direction's rate")
	print("  range | pos err m | dir err mrad | dir rate mrad/s | vel err m/s | acc err m/s² | manoeuvre | torque kN·m | limb kN·m | body °/s | source")
	for r in _ranges:
		await _case(r)
	quit()


func _case(r: float) -> void:
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.STATIC
	drone.hit_points = 1e12
	drone.velocity = _suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(Vector2(8, 4)) * r
	await _ticks(2)
	_fcs.lock(drone)
	await _ticks(120)
	var n := 0
	var pos2 := 0.0
	var dir2 := 0.0
	var rate2 := 0.0
	var vel2 := 0.0
	var acc2 := 0.0
	var last_dir := Vector3.ZERO
	var sources := {}
	var level := 0.0
	var torque2 := 0.0
	var limb2 := 0.0
	var spin2 := 0.0
	var fc := (_suit as Node as VehicleBase).find_component(FlightComputer) as FlightComputer
	var dt := 1.0 / Engine.physics_ticks_per_second
	for k in int(_seconds * Engine.physics_ticks_per_second):
		await physics_frame
		var s := _fcs.sensors
		var est := s.track.get_estimate(s.get_time())
		var eye := _fcs.get_view_origin()
		var truth := drone.global_position
		var dir := (est[0] - eye).normalized() as Vector3
		pos2 += (est[0] - truth).length_squared()
		dir2 += pow(dir.angle_to(truth - eye) * 1000.0, 2.0)
		if last_dir != Vector3.ZERO:
			rate2 += pow(dir.angle_to(last_dir) / dt * 1000.0, 2.0)
		last_dir = dir
		vel2 += (est[1] - _suit.linear_velocity).length_squared()
		acc2 += (est[2] as Vector3).length_squared()
		sources[s.source] = sources.get(s.source, 0) + 1
		level += s.track.get("maneuver") if s.track.get("maneuver") != null else 1.0
		torque2 += fc.last_wrench.torque.length_squared()
		limb2 += fc.limb_torque.length_squared()
		spin2 += pow(rad_to_deg(_suit.angular_velocity.length()), 2.0)
		n += 1
	var names := ["none", "narrow", "wide", "body"]
	var src := ""
	for key in sources:
		src += "%s %d%% " % [names[key], 100 * sources[key] / n]
	print("  %5.0f | %9.3f | %12.3f | %15.2f | %11.3f | %12.3f | %9.2f | %11.1f | %9.1f | %8.3f | %s" % [r, sqrt(pos2 / n),
			sqrt(dir2 / n), sqrt(rate2 / n), sqrt(vel2 / n), sqrt(acc2 / n), level / n,
			sqrt(torque2 / n) / 1000.0, sqrt(limb2 / n) / 1000.0, sqrt(spin2 / n), src])
	_fcs.lock(null)
	drone.queue_free()
	await _ticks(3)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


static func _floats(csv: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for part in csv.split(","):
		out.append(float(part))
	return out
