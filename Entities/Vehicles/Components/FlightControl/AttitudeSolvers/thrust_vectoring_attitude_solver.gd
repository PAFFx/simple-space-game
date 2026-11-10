class_name ThrustVectoringAttitudeSolver
extends AttitudeOffsetSolver

## Minimises, over offsets r (rotation vector in the pilot frame, each axis
## limited by axis_limit_deg, total by max_offset_deg):
##
##   J(r) = (|F| / capability(R⁻¹ F))²  +  angle_weight · (|r| / max_offset)²
##                                       +  smooth_weight · |r − r_prev|²
##
## capability() is the body's directional force authority (FlightState), so the
## first term is "how saturated the thrusters would be". Small demands cost
## nothing, so the suit only turns when a demand is hard to meet as it is.
## Pattern search, started from the best of {current, zero, each body axis aimed
## at F}; a couple of dozen cost evaluations per tick.

## Weight of offset angle relative to thruster saturation.
@export var angle_weight: float = 0.6
## Penalises jumping between solutions, per rad².
@export var smooth_weight: float = 0.4
@export var initial_step_deg: float = 12.0
@export var iterations: int = 6

const _AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


func solve(state: FlightState, force_pilot: Vector3, current: Quaternion) -> Quaternion:
	var max_angle := deg_to_rad(max_offset_deg)
	var demand := force_pilot.length()
	if demand < 1.0 or max_angle <= 0.0:
		return Quaternion.IDENTITY
	var r_prev := _limit(_to_vector(current))

	var best := r_prev
	var best_cost := _cost(state, force_pilot, best, r_prev)
	var f_dir := force_pilot / demand
	var candidates: Array[Vector3] = [Vector3.ZERO]
	for axis: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN,
			Vector3.LEFT, Vector3.RIGHT]:
		candidates.append(_limit(_aim(axis, f_dir)))
	for c in candidates:
		var cost := _cost(state, force_pilot, c, r_prev)
		if cost < best_cost:
			best_cost = cost
			best = c

	var step := deg_to_rad(initial_step_deg)
	var limits := axis_limit_deg * (PI / 180.0)
	for _i in iterations:
		var improved := false
		for k in 3:
			if limits[k] <= 1e-4:
				continue
			for sign in [1.0, -1.0]:
				var c := best
				c[k] += step * sign
				c = _limit(c)
				var cost := _cost(state, force_pilot, c, r_prev)
				if cost < best_cost:
					best_cost = cost
					best = c
					improved = true
		if not improved:
			step *= 0.5
	return _to_quat(best)


func _cost(state: FlightState, f_pilot: Vector3, r: Vector3, r_prev: Vector3) -> float:
	var f_body := _to_quat(r).inverse() * f_pilot
	var cap := maxf(state.force_capability(f_body.normalized()), 1.0)
	var sat := f_pilot.length() / cap
	var a := r.length() / deg_to_rad(max_offset_deg)
	return sat * sat + angle_weight * a * a + smooth_weight * (r - r_prev).length_squared()


## Rotation vector that turns body direction `body_axis` toward `target` (pilot frame).
static func _aim(body_axis: Vector3, target: Vector3) -> Vector3:
	var axis := body_axis.cross(target)
	var angle := body_axis.angle_to(target)
	if axis.length_squared() < 1e-8:
		if angle < 0.1:
			return Vector3.ZERO
		axis = Vector3.RIGHT  # opposite: flip about pitch, the UC way
	return axis.normalized() * angle


## Clamps each axis to axis_limit_deg, then the total to max_offset_deg.
func _limit(r: Vector3) -> Vector3:
	var limits := axis_limit_deg * (PI / 180.0)
	return r.clamp(-limits, limits).limit_length(deg_to_rad(max_offset_deg))


static func _to_quat(r: Vector3) -> Quaternion:
	var angle := r.length()
	return Quaternion(r / angle, angle) if angle > 1e-6 else Quaternion.IDENTITY


static func _to_vector(q: Quaternion) -> Vector3:
	var angle := q.get_angle()
	return q.get_axis() * angle if angle > 1e-6 else Vector3.ZERO
