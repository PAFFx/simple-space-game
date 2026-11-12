class_name ThrustVectoringAttitudeSolver
extends AttitudeOffsetSolver

## Minimises, over offsets r (rotation vector in the pilot frame, each axis
## limited by axis_limit_deg, total by max_offset_deg):
##
##   J(r) = shortfall_weight · max(0, 1 − target_load · capability(R⁻¹ F) / |F|)²
##        + angle_weight · (|r| / max_offset)²  +  smooth_weight · |r − r_prev|²
##        + commit_weight · max(0, −r · ĉ)
##
## The last term commits to a side: once the offset passes commit_angle_deg one way (ĉ),
## turning back through to the other side (e.g. nose up vs nose down for a descent,
## often nearly as good) costs a lot, until the demanded force swings more than
## commit_release_deg away from the one the side was chosen for. So the suit doesn't
## flip between near-equal solutions as the demand shifts a little.
##
## capability() is the body's clean directional force authority (FlightState). The first
## term is the share of the demand left unmet (0..1), so a full-boost demand far beyond
## any attitude's capability can't swamp the other terms over tiny capability differences.
## Demands the current attitude can meet cost nothing but the angle, so the
## suit only turns when it must, and only as far as needed.
## Pattern search, started from the best of {current, zero, each body axis aimed
## at F}; a couple of dozen cost evaluations per tick. Locked axes keep their
## current component and are left out of the search.

## Thruster load (demand / capability) the solver aims to stay under.
@export var target_load: float = 0.9
## Weight of exceeding target_load (the reason to rotate at all).
@export var shortfall_weight: float = 120.0
## Weight of offset angle (the cost of rotating).
@export var angle_weight: float = 0.6
## Penalises jumping between solutions, per rad².
@export var smooth_weight: float = 0.4
## Cost of turning back through to the opposite side, per rad of reversal.
@export var commit_weight: float = 40.0
## Offsets smaller than this don't commit to a side, deg.
@export var commit_angle_deg: float = 5.0
## The side is released when the demanded force turns this far from where it was chosen, deg.
@export var commit_release_deg: float = 45.0
## For pushes within upright_cone_deg of straight up, only turn away from the pilot frame
## if that raises the force capability along the demand by at least this factor;
## otherwise stay upright (a climb keeps the head up instead of leaning back for a bit
## more thrust). Other pushes tilt whenever it helps.
@export var min_tilt_gain: float = 1.6
@export var upright_cone_deg: float = 45.0
@export var initial_step_deg: float = 12.0
@export var iterations: int = 6

var _cap := 0.0  ## Offset limit of the current solve, rad
var _commit := Vector3.ZERO           ## Committed side (unit rotation vector), zero = none
var _commit_force := Vector3.ZERO     ## Demand direction the side was chosen for

func solve(state: FlightState, force_pilot: Vector3, current: Quaternion,
		locked: Vector3, max_angle_deg: float) -> Quaternion:
	var r_pin := to_rotation_vector(current)
	_cap = deg_to_rad(clampf(max_angle_deg, 0.0, max_offset_deg))
	var demand := force_pilot.length()
	if demand < 1.0 or _cap <= 0.0:
		_commit = Vector3.ZERO
		return from_rotation_vector(_limit(Vector3.ZERO, r_pin, locked))
	var r_prev := _limit(r_pin, r_pin, locked)
	var f_dir := force_pilot / demand
	if _commit != Vector3.ZERO and f_dir.angle_to(_commit_force) > deg_to_rad(commit_release_deg):
		_commit = Vector3.ZERO

	var best := r_prev
	var best_cost := _cost(state, force_pilot, best, r_prev)
	var candidates: Array[Vector3] = [Vector3.ZERO]
	for axis: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN,
			Vector3.LEFT, Vector3.RIGHT]:
		candidates.append(_aim(axis, f_dir))
	for i in candidates.size():
		candidates[i] = _limit(candidates[i], r_pin, locked)
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
			if limits[k] <= 1e-4 or locked[k] > 0.0:
				continue
			for sign in [1.0, -1.0]:
				var c := best
				c[k] += step * sign
				c = _limit(c, r_pin, locked)
				var cost := _cost(state, force_pilot, c, r_prev)
				if cost < best_cost:
					best_cost = cost
					best = c
					improved = true
		if not improved:
			step *= 0.5
	if best != Vector3.ZERO and f_dir.dot(Vector3.UP) >= cos(deg_to_rad(upright_cone_deg)) \
			and _capability(state, force_pilot, Vector3.ZERO) * min_tilt_gain \
			>= _capability(state, force_pilot, best):
		best = _limit(Vector3.ZERO, r_pin, locked)
	# Commit to the side of this solution (not of the current attitude, which after a
	# release still points the old way).
	if _commit == Vector3.ZERO and best.length() > deg_to_rad(commit_angle_deg):
		_commit = best.normalized()
		_commit_force = f_dir
	return from_rotation_vector(best)


func _capability(state: FlightState, f_pilot: Vector3, r: Vector3) -> float:
	var f_body := from_rotation_vector(r).inverse() * f_pilot
	return state.force_capability(f_body.normalized())


func _cost(state: FlightState, f_pilot: Vector3, r: Vector3, r_prev: Vector3) -> float:
	var f_body := from_rotation_vector(r).inverse() * f_pilot
	var cap := maxf(state.force_capability(f_body.normalized()), 1.0)
	var shortfall := maxf(0.0, 1.0 - target_load * cap / maxf(f_pilot.length(), 1.0))
	var a := r.length() / deg_to_rad(max_offset_deg)
	var commit := commit_weight * maxf(0.0, -r.dot(_commit))
	return shortfall_weight * shortfall * shortfall + angle_weight * a * a \
			+ smooth_weight * (r - r_prev).length_squared() + commit


## Rotation vector that turns body direction `body_axis` toward `target` (pilot frame).
static func _aim(body_axis: Vector3, target: Vector3) -> Vector3:
	var axis := body_axis.cross(target)
	var angle := body_axis.angle_to(target)
	if axis.length_squared() < 1e-8:
		if angle < 0.1:
			return Vector3.ZERO
		axis = Vector3.RIGHT  # opposite: flip about pitch, the UC way
	return axis.normalized() * angle


## Clamps each free axis to axis_limit_deg and the total to the solve's cap
## (shrinking only the free part); locked axes take their value from r_pin as is.
func _limit(r: Vector3, r_pin: Vector3, locked: Vector3) -> Vector3:
	var limits := axis_limit_deg * (PI / 180.0)
	r = r.clamp(-limits, limits)
	var pinned := r_pin * locked
	var free := r * (Vector3.ONE - locked)
	return pinned + free.limit_length(sqrt(maxf(_cap * _cap - pinned.length_squared(), 0.0)))
