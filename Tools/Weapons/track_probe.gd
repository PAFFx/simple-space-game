extends SceneTree

## Hit rate of the beam rifle (PULSE) against a jinking drone, with the sensor track and
## with a perfect one, across range: how much the sensors' delay and noise give the
## defender (Docs/PhysicsAndSensors/sensors.md, "The dodge budget"). The suit holds still;
## each shot is held through its spool, then judged by the drone's hit points.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Weapons/track_probe.gd -- \
##       [speed=1500] [shots=10] [jink=3,6] [ranges=300,500,700,1000,1500,2000] [modes=sensor,truth]

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.fire_main = out.fire_main
		return out

var _suit: RigidBody3D
var _fcs: FireControl
var _input := ScriptedInput.new()
var _speed := 1500.0
var _shots := 10
var _jinks := PackedFloat64Array([3.0, 6.0])
var _ranges := PackedFloat64Array([300.0, 500.0, 700.0, 1000.0, 1500.0, 2000.0])
var _modes := PackedStringArray(["sensor", "truth"])


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"speed": _speed = float(value)
			"shots": _shots = int(value)
			"jink": _jinks = _floats(value)
			"ranges": _ranges = _floats(value)
			"modes": _modes = value.split(",")
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
	var rifle := _fcs.get_weapon(&"beam_rifle")
	var spec: ProjectileSpec = rifle.projectile.duplicate()
	spec.speed = _speed
	spec.lifetime = maxf(spec.lifetime, 3000.0 / _speed)
	rifle.projectile = spec
	print("beam %.0f m/s, %d shots per case, drone radius 7 m" % [_speed, _shots])
	for mode in _modes:
		_fcs.sensors.enabled = mode == "sensor"
		for g in _jinks:
			var line := "%-6s jink %.0f G |" % [mode, g]
			for r in _ranges:
				var result := await _case(rifle, g, r)
				line += " %4.0f m %2d/%d%s |" % [r, result[0], _shots, " (%d br)" % result[1] if mode == "sensor" else ""]
			print(line)
	quit()


## [hits, track breaks] for `_shots` shots at a drone jinking at `g`, `r` m away.
func _case(rifle: MsWeapon, g: float, r: float) -> Array:
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.JINK
	drone.jink_accel_g = g
	drone.hit_points = 1e12
	drone.velocity = _suit.linear_velocity
	drone.leash = maxf(r * 0.4, 100.0)
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(Vector2(8, 4)) * r
	await _ticks(2)
	_fcs.lock(drone)
	await _ticks(90)
	var hits := 0
	for i in _shots:
		rifle.rearm()
		# Wait for the cooldown and SHOOT (firm solution, barrel on the lead), as a pilot would.
		for k in 600:
			if rifle.can_fire() and rifle.on_target:
				break
			await physics_frame
		var hp := drone.hit_points
		var ammo := rifle.ammo
		_input.cmd.fire_main = true
		for k in 120:
			await physics_frame
			if rifle.ammo < ammo:
				break
		_input.cmd.fire_main = false
		await _ticks(ceili((r / _speed + 0.3) * Engine.physics_ticks_per_second))
		if drone.hit_points < hp:
			hits += 1
	var breaks := _fcs.sensors.track.breaks if _fcs.sensors.track != null else 0
	_fcs.lock(null)
	drone.queue_free()
	await _ticks(3)
	return [hits, breaks]


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


static func _floats(csv: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for part in csv.split(","):
		out.append(float(part))
	return out
