class_name ConeProjectedAllocator
extends ThrustAllocator

## Gimbal-aware least-squares allocation solved with accelerated projected
## gradient descent (FISTA).
##
## Each thruster i contributes a free 3D vector u_i (throttle-normalised) limited
## to its gimbal cone. We minimise
##     |Wf (ΣTᵢuᵢ − F)|² + |Wt (Σ rᵢ×Tᵢuᵢ − τ)|² + λ Σ|Tᵢuᵢ|²
## so when the demand exceeds authority the result degrades gracefully and the
## λ term avoids thrusters fighting each other. The solution is warm-started from
## the previous tick, so a few iterations per frame are enough.

@export_range(1, 200) var iterations: int = 24
## Lever arm used to make torque errors comparable to force errors, m.
@export var reference_arm: float = 4.0
## >1 favours rotation accuracy over translation when saturated.
@export var torque_priority: float = 2.0
## Small propellant-use penalty λ.
@export var fuel_weight: float = 0.01

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
	var wt2 := wf2 * torque_priority * torque_priority / (reference_arm * reference_arm)
	var lam := fuel_weight * wf2
	var lipschitz := 2.0 * lam * t_max * t_max
	for i in n:
		lipschitz += 2.0 * t[i] * t[i] * (wf2 + wt2 * r[i].length_squared())
	var step := 1.0 / lipschitz

	var u := _u
	var y := _u.duplicate()
	var momentum := 1.0
	for _k in iterations:
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		for i in n:
			var f := y[i] * t[i]
			force += f
			torque += r[i].cross(f)
		var g_force := (force - wrench.force) * (2.0 * wf2)
		var g_torque := (torque - wrench.torque) * (2.0 * wt2)

		var next_momentum := (1.0 + sqrt(1.0 + 4.0 * momentum * momentum)) * 0.5
		var beta := (momentum - 1.0) / next_momentum
		for i in n:
			if t[i] <= 0.0:
				u[i] = Vector3.ZERO
				y[i] = Vector3.ZERO
				continue
			var grad := (g_force + g_torque.cross(r[i])) * t[i] + y[i] * (2.0 * lam * t[i] * t[i])
			var u_new := project_to_cone(y[i] - grad * step, state.thruster_axes[i], state.thruster_cone[i])
			y[i] = u_new + (u_new - u[i]) * beta
			u[i] = u_new
		momentum = next_momentum

	_u = u
	return _u
