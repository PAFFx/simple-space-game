extends SceneTree

## Can the ν dodge? A turret drone shoots at the suit; a scripted pilot reacts to the
## turret's charge glow (its spool) after a human reaction time and boosts across the line
## of sight, then brakes. Counts hits on the suit per shot, by range.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Weapons/dodge_probe.gd -- \
##       [speed=1500] [shots=10] [ranges=500,1000,2000] [policies=none,up,side]
##       [aim=track,truth] [reaction=0.25] [hold=0.8] [spool=0.5]
##
## policies: none (sits still), up (the mains' axis, ~9 G), side (left or right at random,
## ~3.6 G), any (up / down / left / right at random). aim: the turret leads from its own
## sensor track of the suit (TargetDrone.use_track) or from the suit's true state.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		return cmd

var _suit: RigidBody3D
var _fcs: FireControl
var _input := ScriptedInput.new()
var _speed := 1500.0
var _shots := 10
var _ranges := PackedFloat64Array([500.0, 1000.0, 2000.0])
var _policies := PackedStringArray(["none", "up", "side"])
var _aims := PackedStringArray(["track"])
var _reaction := 0.25
var _hold := 0.8
var _spool := 0.5
var _hits := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"speed": _speed = float(value)
			"shots": _shots = int(value)
			"ranges": _ranges = _floats(value)
			"policies": _policies = value.split(",")
			"aim": _aims = value.split(",")
			"reaction": _reaction = float(value)
			"hold": _hold = float(value)
			"spool": _spool = float(value)
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
	_suit.connect(&"hit_taken", func(_d: float, _p: Vector3, _dir: Vector3) -> void: _hits += 1)
	await _ticks(60)
	print("turret beam %.0f m/s, spool %.2f s, %d shots per case; pilot reacts %.2f s after the glow, boosts %.2f s" % [
			_speed, _spool, _shots, _reaction, _hold])
	for aim in _aims:
		for policy in _policies:
			var line := "aim %-5s dodge %-4s |" % [aim, policy]
			for r in _ranges:
				var result: Array = await _case(aim == "track", policy, r)
				line += " %4.0f m %2d/%d |" % [r, result[0], result[1]]
			print(line)
	quit()


## [hits, shots resolved]
func _case(track: bool, policy: String, r: float) -> Array:
	var start := _suit.global_transform
	var spec: ProjectileSpec = (load("res://Entities/Projectiles/Specs/drone_shot.tres") as ProjectileSpec).duplicate()
	spec.speed = _speed
	spec.spool_time = _spool
	spec.lifetime = maxf(spec.lifetime, r * 1.5 / _speed)
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.TURRET
	drone.quarry = _suit
	drone.shot = spec
	drone.jink_accel_g = 0.0
	drone.hit_points = 1e12
	drone.aim_error_deg = 0.03
	drone.fire_range = r * 2.0
	drone.fire_interval = Vector2(1.0, 1.4)
	drone.use_track = track
	drone.velocity = _suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = _suit.global_position + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(Vector2(5, 3)) * r
	_hits = 0
	var hits := 0
	var resolved := 0
	# A turret that stops shooting (lost track, out of reach) must not hang the probe.
	var time_left := 8.0 + _shots * (3.0 + r / _speed)
	var spooling := false
	var dodge_in := -1.0
	var dodge_left := 0.0
	var dodge_dir := Vector3.ZERO
	var settle := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	while resolved < _shots and time_left > 0.0:
		await physics_frame
		time_left -= 1.0 / Engine.physics_ticks_per_second
		var cue := drone.is_spooling()
		if cue and not spooling and policy != "none":
			dodge_in = _reaction
		if spooling and not cue:
			# Fired: judge it once it has had time to arrive, then put the suit back.
			settle = r / _speed + 0.4
		spooling = cue
		if dodge_in >= 0.0:
			dodge_in -= dt
			if dodge_in < 0.0:
				dodge_left = _hold
				dodge_dir = _dodge_direction(policy, drone)
		_input.cmd = PilotCommand.new()
		if dodge_left > 0.0:
			dodge_left -= dt
			_input.cmd.translation = dodge_dir
			_input.cmd.boost = true
			_input.cmd.boost_full = true
		else:
			_input.cmd.brake = true
		if settle > 0.0:
			settle -= dt
			if settle <= 0.0:
				resolved += 1
				# One shot hits once, however many parts it touched.
				hits += mini(_hits, 1)
				_hits = 0
				_suit.global_transform = start
				_suit.linear_velocity = Vector3.ZERO
				_suit.angular_velocity = Vector3.ZERO
	if resolved < _shots:
		push_warning("dodge_probe: only %d of %d shots resolved (%s, %.0f m)" % [resolved, _shots, policy, r])
	drone.queue_free()
	await _ticks(30)
	return [hits, resolved]


## Across the line of sight, in the pilot's frame (the suit flies level, so the body's).
func _dodge_direction(policy: String, drone: TargetDrone) -> Vector3:
	var los := (_suit.global_basis.orthonormalized().inverse() * (drone.global_position - _suit.global_position)).normalized()
	var want := Vector3.UP
	match policy:
		"side":
			want = Vector3.RIGHT if randf() < 0.5 else Vector3.LEFT
		"any":
			want = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT][randi() % 4]
	return (want - los * want.dot(los)).normalized()


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


static func _floats(csv: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for part in csv.split(","):
		out.append(float(part))
	return out
