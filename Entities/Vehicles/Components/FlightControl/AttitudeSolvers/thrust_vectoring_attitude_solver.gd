class_name ThrustVectoringAttitudeSolver
extends AttitudeOffsetSolver

## Minimises, over pitch/yaw offsets r (rotation vector in the pilot frame):
##
##   J(r) = (|F| / capability(R⁻¹ F))²  +  angle_weight · (|r| / max_offset)²
##                                       +  smooth_weight · |r − r_prev|²
##
## capability() is the body's directional force authority (FlightState), so the
## first term is "how saturated the thrusters would be". Small demands cost
## nothing, so the suit only turns when a demand is hard to meet as it is.
## Pattern search, started from the best of {current, zero, best body axis
## aimed at F}; a dozen cost evaluations per tick.

## Weight of offset angle relative to thruster saturation.
@export var angle_weight: float = 0.6
## Penalises jumping between solutions, per rad².
@export var smooth_weight: float = 0.4
@export var initial_step_deg: float = 12.0
@export var iterations: int = 6


func solve(state: FlightState, force_pilot: Vector3, current: Quaternion) -> Quaternion:
	var max_angle := deg_to_rad(max_offset_deg)
	var demand := force_pilot.length()
	if demand < 1.0 or max_angle <= 0.0:
		return Quaternion.IDENTITY
	var r_prev := _to_pitch_yaw(current)

	var best := r_prev
	var best_cost := _cost(state, force_pilot, best, r_prev, max_angle)
	var candidates: Array[Vector2] = [Vector2.ZERO]
	var f_dir := force_pilot / demand
	for axis: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN,
			Vector3.LEFT, Vector3.RIGHT]:
		candidates.append(_aim(axis, f_dir, max_angle))
	for c in candidates:
		var cost := _cost(state, force_pilot, c, r_prev, max_angle)
		if cost < best_cost:
			best_cost = cost
			best = c

	var step := deg_to_rad(initial_step_deg)
	for _i in iterations:
		var improved := false
		for d: Vector2 in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
			var c := _limit(best + d, max_angle)
			var cost := _cost(state, force_pilot, c, r_prev, max_angle)
			if cost < best_cost:
				best_cost = cost
				best = c
				improved = true
		if not improved:
			step *= 0.5
	return _to_quat(best)


func _cost(state: FlightState, f_pilot: Vector3, r: Vector2, r_prev: Vector2,
		max_angle: float) -> float:
	var f_body := _to_quat(r).inverse() * f_pilot
	var cap := maxf(state.force_capability(f_body.normalized()), 1.0)
	var sat := f_pilot.length() / cap
	var a := r.length() / max_angle
	return sat * sat + angle_weight * a * a + smooth_weight * (r - r_prev).length_squared()


## Offset that turns body direction `body_axis` toward `target` (pilot frame), clamped.
static func _aim(body_axis: Vector3, target: Vector3, max_angle: float) -> Vector2:
	var axis := body_axis.cross(target)
	var angle := body_axis.angle_to(target)
	if axis.length_squared() < 1e-8:
		if angle < 0.1:
			return Vector2.ZERO
		axis = Vector3.RIGHT  # opposite: flip about pitch, the UC way
	axis = axis.normalized()
	var rv := axis * minf(angle, max_angle)
	return _limit(Vector2(rv.x, rv.y), max_angle)


static func _limit(r: Vector2, max_angle: float) -> Vector2:
	return r.limit_length(max_angle)


static func _to_quat(r: Vector2) -> Quaternion:
	var rv := Vector3(r.x, r.y, 0.0)
	var angle := rv.length()
	return Quaternion(rv / angle, angle) if angle > 1e-6 else Quaternion.IDENTITY


static func _to_pitch_yaw(q: Quaternion) -> Vector2:
	var angle := q.get_angle()
	if angle < 1e-6:
		return Vector2.ZERO
	var rv := q.get_axis() * angle
	return Vector2(rv.x, rv.y)
