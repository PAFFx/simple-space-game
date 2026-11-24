extends SceneTree

## Checks for the fair-fight pass: the turret's gun arm (can you circle out of its arc?),
## its E-cap and recoil. (The suit's damage has its own probes: Tools/Damage.)
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Weapons/fair_fight_probe.gd -- \
##       [parts=arc,ecap] [ranges=150,300,600] [time=12] [speed=120]
##
## arc: a turret (perfect aim from the truth, 0.5 s spool) shoots for `time` s at a suit
## that holds still or circles it at `speed` m/s on the mains' axis; the same with the old
## turret (turns at once, arm reaches all round) as the control. Prints shots and hits.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		return cmd

var _suit: RigidBody3D
var _fcs: FireControl
var _damage: DamageModel
var _input := ScriptedInput.new()
var _parts := PackedStringArray(["arc", "ecap"])
var _ranges := PackedFloat64Array([150.0, 300.0, 600.0])
var _time := 12.0
var _speed := 120.0
## Turret body turn rate and acceleration override (deg/s, deg/s², 0 = its default).
var _turn := 0.0
var _turn_accel := 0.0
var _hits := 0
var _failed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"parts": _parts = value.split(",")
			"ranges":
				_ranges = PackedFloat64Array()
				for v in value.split(","):
					_ranges.append(float(v))
			"time": _time = float(value)
			"speed": _speed = float(value)
			"turn": _turn = float(value)
			"turn_accel": _turn_accel = float(value)
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
	_fcs.sensors.enabled = false
	_damage = vehicle.find_component(DamageModel) as DamageModel
	_check("suit has a damage model", _damage != null)
	# Hits are counted, the suit isn't damaged (a reactor hit would end the run).
	_damage.enabled = false
	_suit.connect(&"hit_taken", func(_d: float, _p: Vector3, _dir: Vector3) -> void: _hits += 1)
	await _ticks(60)
	if "arc" in _parts:
		await _arc()
	if "ecap" in _parts:
		await _ecap()
	print("RESULT: %s" % ("PASS" if _failed == 0 else "%d FAILED" % _failed))
	quit()


# --- Gun arm ---

func _arc() -> void:
	print("turret arc: %.0f s per case, circling at %.0f m/s" % [_time, _speed])
	var still_old := 0
	var circle_new := 0
	var circle_old := 0
	for r in _ranges:
		var line := "  %4.0f m |" % r
		for case in [["still", false], ["circle", false], ["circle", true]]:
			var result: Array = await _arc_case(r, case[0] == "circle", case[1])
			line += " %s %s %2d/%-2d %3.0f°/s |" % [case[0], "old" if case[1] else "new", result[0], result[1], result[2]]
			if r == _ranges[0]:
				if case[0] == "circle" and not case[1]:
					circle_new = result[0]
				elif case[0] == "circle":
					circle_old = result[0]
		print(line)
	_check("circling close in beats the gun arm (fewer hits than the old turret)", circle_new < circle_old)


## [hits, shots, mean line-of-sight rate seen from the turret, deg/s]
func _arc_case(r: float, circle: bool, old: bool) -> Array:
	_damage.repair()
	var start := _suit.global_transform
	var drone := _turret(r)
	if old:
		drone.turn_rate_deg = 0.0
		drone.arm_cone_deg = 180.0
		drone.arm_slew_deg = 100000.0
		drone.arm_accel_deg = 1e7
		drone.slew_error = 0.0
	drone.magazine = 0
	await _ticks(2)
	_hits = 0
	var t := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var last_los := (_suit.global_position - drone.global_position).normalized()
	var swept := 0.0
	while t < _time:
		await physics_frame
		t += dt
		var los := (_suit.global_position - drone.global_position).normalized()
		swept += rad_to_deg(los.angle_to(last_los))
		last_los = los
		_input.cmd = PilotCommand.new()
		if circle:
			_input.cmd.translation = _circle_command(drone, r)
			_input.cmd.rotation = _nose_on(drone)
			_input.cmd.boost = true
		else:
			_input.cmd.brake = true
	var result := [_hits, drone.shots_fired, swept / _time]
	drone.queue_free()
	_input.cmd = PilotCommand.new()
	_suit.global_transform = start
	_suit.linear_velocity = Vector3.ZERO
	_suit.angular_velocity = Vector3.ZERO
	await _ticks(30)
	return result


## Orbit the drone at radius `r`: hold `_speed` across the line of sight, on the suit's up
## axis (its strongest), with the centripetal pull and a radius correction.
func _circle_command(drone: TargetDrone, r: float) -> Vector3:
	var basis := _suit.global_basis.orthonormalized()
	var rel := _suit.global_position - drone.global_position
	var dist := rel.length()
	var radial := rel / dist
	var up := basis.y
	var tangent := (up - radial * up.dot(radial)).normalized()
	var rel_vel := _suit.linear_velocity - drone.velocity
	var v_t := rel_vel.dot(tangent)
	var want := tangent * _speed + radial * (r - dist) * 0.8
	var accel := (want - rel_vel) * 2.0 - radial * (v_t * v_t / maxf(dist, 1.0))
	var local := basis.inverse() * accel
	var biggest := maxf(absf(local.x), maxf(absf(local.y), absf(local.z)))
	return local / maxf(biggest, 1.0) if biggest > 1.0 else local / 20.0


## Keep the nose on the drone, as a pilot orbiting it would: the pull toward it then falls
## on the forward thrust and the mains push along the orbit.
func _nose_on(drone: TargetDrone) -> Vector3:
	var d := _suit.global_basis.orthonormalized().inverse() * (drone.global_position - _suit.global_position).normalized()
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, -d.z)
	return Vector3(clampf(pitch * 3.0, -1.0, 1.0), clampf(yaw * 3.0, -1.0, 1.0), 0.0)


func _turret(r: float) -> TargetDrone:
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.TURRET
	drone.quarry = _suit
	drone.jink_accel_g = 0.0
	drone.hit_points = 1e12
	drone.aim_error_deg = 0.03
	drone.fire_range = 5000.0
	drone.fire_interval = Vector2(1.0, 1.4)
	drone.velocity = _suit.linear_velocity
	if _turn > 0.0:
		drone.turn_rate_deg = _turn
	if _turn_accel > 0.0:
		drone.turn_accel_deg = _turn_accel
	current_scene.add_child(drone)
	drone.global_position = _suit.global_position + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(Vector2(5, 3)) * r
	return drone


# --- E-cap and recoil ---

func _ecap() -> void:
	_damage.repair()
	var drone := _turret(800.0)
	drone.magazine = 3
	drone.reload_time = 3.0
	drone.fire_interval = Vector2(0.2, 0.2)
	var held := true
	var fired_in_reload := false
	var shots := 0
	var t := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	_input.cmd = PilotCommand.new()
	_input.cmd.brake = true
	while t < 14.0:
		await physics_frame
		t += dt
		if drone.shots_fired != shots:
			shots = drone.shots_fired
			if drone.is_reloading():
				fired_in_reload = true
			# Recoil: the barrel holds where the shot left for the pour and after.
			var dir := drone.get_barrel_direction()
			await _ticks(int((drone.shot.emit_time + drone.recover_time * 0.8) * Engine.physics_ticks_per_second))
			t += drone.shot.emit_time + drone.recover_time * 0.8
			held = held and drone.get_barrel_direction().angle_to(dir) < deg_to_rad(0.5)
	print("ecap: %d shots, %d reloads in 14 s (3 per pack, 3 s swap)" % [drone.shots_fired, drone.reloads])
	_check("it reloads after its pack", drone.reloads >= 2)
	_check("no shot while reloading", not fired_in_reload)
	_check("shots per 14 s limited by the pack", drone.shots_fired <= 9)
	_check("the barrel holds through the pour and recoil", held)
	drone.queue_free()
	await _ticks(10)


# --- Armour ---

func _hit_box(box_name: String, times: int) -> void:
	var box := _suit.get_node(box_name) as Node3D
	for i in times:
		(_suit as Node).call(&"apply_hit", 100.0, box.global_position, Vector3.FORWARD, null)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["ok   " if ok else "FAIL ", label])
	if not ok:
		_failed += 1


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
