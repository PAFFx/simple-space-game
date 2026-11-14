class_name ConeProjectedAllocator
extends ThrustAllocator

## Gimbal-aware least-squares allocation solved with accelerated projected
## gradient descent (FISTA).
##
## Each thruster i contributes a free 3D vector u_i (throttle-normalised) limited
## to its gimbal cone. We minimise
##     |Wf (ΣTᵢuᵢ − F)|² + |Wt (Σ rᵢ×Tᵢuᵢ − τ)|² + λ Σ|Tᵢuᵢ|² + μ Σ|Tᵢuᵢ|
## so when the demand exceeds authority the result degrades gracefully. The solution
## is warm-started from the previous tick, so a few iterations per frame are enough.
##
## Propellant: μ Σ|Tᵢuᵢ| is what fuel really costs (proportional to thrust). Without
## it, least squares fires every thruster that helps even a little and lets pairs
## fight each other (e.g. down-firing verniers while climbing); with it, the fewest,
## best-aimed thrusters do the job. The price would leave the demand short, so the
## solve runs in passes, adding each pass's shortfall back onto the target (Bregman
## iteration), which converges on the cheapest allocation that meets the demand.
## μ scales with the force demand and fades out as it nears the suit's capability in
## that direction: a full-power push needs every thruster, so it's never held back,
## and pure rotations (no force demand) are left alone.

@export_range(1, 200) var iterations: int = 24
## Lever arm used to make torque errors comparable to force errors, m.
@export var reference_arm: float = 4.0
## >1 favours rotation accuracy over translation when saturated.
@export var torque_priority: float = 2.0
## Small squared-thrust penalty λ (keeps the problem well conditioned).
@export var fuel_weight: float = 0.01
## Propellant price, relative to the force demand. Higher = fewer thrusters fire.
## 0 = off.
@export_range(0.0, 1.0) var fuel_cost: float = 0.1
## Passes that add the shortfall back onto the target (iterations are split over them).
@export_range(1, 8) var fuel_passes: int = 3
## The price fades out between this fraction of the capability and full capability.
@export_range(0.0, 1.0) var fuel_fade_start: float = 0.75

## Fraction of last tick's solution kept as the starting guess. <1 bleeds off
## thruster pairs that cancel each other out, which pure residual minimisation
## never removes.
@export_range(0.0, 1.0) var warm_start_decay: float = 0.85

## Weight each axis's torque error by its inertia (heaviest / axis, up to the limit).
@export var inertia_weighting: bool = true
@export var max_inertia_weight: float = 1.5

var _u := PackedVector3Array()


func allocate(state: FlightState, wrench: Wrench) -> PackedVector3Array:
	var n := state.thruster_axes.size()
	if _u.size() != n:
		_u = PackedVector3Array()
		_u.resize(n)

	var r := state.thruster_positions
	var t := state.thruster_max
	var total := 0.0
	var t_max := 0.0
	for i in n:
		total += t[i]
		t_max = maxf(t_max, t[i])
	if total <= 0.0:
		_u.fill(Vector3.ZERO)
		return _u

	var wf2 := 1.0 / (total * total)
	var tp := wrench.torque_priority if wrench.torque_priority >= 0.0 else torque_priority
	# Torque errors count by the turning they cause: an axis with little inertia (yaw on
	# a tall suit) spins up from an error the heavy axes wouldn't notice.
	var wt2 := Vector3.ONE * (wf2 * tp * tp / (reference_arm * reference_arm))
	var inertia := Vector3(state.inertia_local.x.x, state.inertia_local.y.y, state.inertia_local.z.z)
	var heaviest := maxf(inertia.x, maxf(inertia.y, inertia.z))
	if inertia_weighting and heaviest > 0.0:
		for k in 3:
			wt2[k] *= minf(heaviest / maxf(inertia[k], 1e-6), max_inertia_weight) ** 2
	var wt2_max := maxf(wt2.x, maxf(wt2.y, wt2.z))
	var lam := fuel_weight * wf2
	var lipschitz := 2.0 * lam * t_max * t_max
	for i in n:
		lipschitz += 2.0 * t[i] * t[i] * (wf2 + wt2_max * r[i].length_squared())
	var step := 1.0 / lipschitz

	var u := _u
	for i in n:
		u[i] *= warm_start_decay
	var price := _price(state, wrench, wf2)
	var passes := fuel_passes if price > 0.0 else 1
	var per_pass := ceili(float(iterations) / passes)
	var target_f := wrench.force
	var target_t := wrench.torque
	for p in passes:
		_solve(state, u, target_f, target_t, per_pass, step, wf2, wt2, lam, price)
		if p < passes - 1:
			var achieved := _wrench_of(state, u)
			target_f += wrench.force - achieved[0]
			target_t += wrench.torque - achieved[1]
	_u = u
	return _u


## FISTA on u (in place) toward a target force/torque, with a propellant price per
## newton of thrust.
func _solve(state: FlightState, u: PackedVector3Array, force_target: Vector3, torque_target: Vector3,
		count: int, step: float, wf2: float, wt2: Vector3, lam: float, price: float) -> void:
	var n := u.size()
	var r := state.thruster_positions
	var t := state.thruster_max
	var y := u.duplicate()
	var momentum := 1.0
	for _k in count:
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		for i in n:
			var f := y[i] * t[i]
			force += f
			torque += r[i].cross(f)
		var g_force := (force - force_target) * (2.0 * wf2)
		var g_torque := (torque - torque_target) * wt2 * 2.0

		var next_momentum := (1.0 + sqrt(1.0 + 4.0 * momentum * momentum)) * 0.5
		var beta := (momentum - 1.0) / next_momentum
		for i in n:
			if t[i] <= 0.0:
				u[i] = Vector3.ZERO
				y[i] = Vector3.ZERO
				continue
			var grad := (g_force + g_torque.cross(r[i])) * t[i] + y[i] * (2.0 * lam * t[i] * t[i])
			var u_new := project_to_gimbal(y[i] - grad * step, state, i)
			var shrink := step * price * t[i]
			if shrink > 0.0:
				var length := u_new.length()
				u_new = u_new * (maxf(length - shrink, 0.0) / length) if length > 1e-12 else Vector3.ZERO
			y[i] = u_new + (u_new - u[i]) * beta
			u[i] = u_new
		momentum = next_momentum


## Price per newton: fuel_cost × the force-residual gradient at u = 0 (so it scales
## with the demand), faded out as the demand nears the capability in its direction.
func _price(state: FlightState, wrench: Wrench, wf2: float) -> float:
	var demand := wrench.force.length()
	if fuel_cost <= 0.0 or demand < 1.0:
		return 0.0
	var capability := state.force_capability(wrench.force / demand)
	var ratio := demand / maxf(capability, 1.0)
	var headroom := 1.0 if fuel_fade_start >= 1.0 else \
			clampf((1.0 - ratio) / maxf(1.0 - fuel_fade_start, 0.01), 0.0, 1.0)
	return fuel_cost * 2.0 * wf2 * demand * headroom


static func _wrench_of(state: FlightState, u: PackedVector3Array) -> Array[Vector3]:
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	for i in u.size():
		var f := u[i] * state.thruster_max[i]
		force += f
		torque += state.thruster_positions[i].cross(f)
	return [force, torque]
