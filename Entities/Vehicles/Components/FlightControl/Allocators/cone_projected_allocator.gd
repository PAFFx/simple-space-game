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

## Step from the true Lipschitz constant (the largest eigenvalue of the weighted
## thrust-to-wrench map, by a power iteration warm-started from last tick, plus 5%)
## instead of the per-thruster bound, which is ~2.3x larger on the RX-93: each iteration
## goes about twice as far, so about half the iterations reach the same answer.
@export var tight_step: bool = false

## Iterations of the actuator trim (throttles only, nozzle directions as they really are).
@export_range(0, 200) var trim_iterations: int = 24
## In the trim, force error across the demand counts this much more than a shortfall
## along it: when the thrusters can't keep up, the suit pushes less, not sideways.
@export var trim_sideways_weight: float = 30.0
## Weight each axis's torque error by its inertia (heaviest / axis, up to the limit).
@export var inertia_weighting: bool = true
@export var max_inertia_weight: float = 1.5

var _u := PackedVector3Array()
var _wt2 := Vector3.ZERO   ## Last allocate()'s weights, reused by trim()
## The tight step's eigenvector (force and torque halves), carried over between ticks.
var _eig_f := Vector3.ONE
var _eig_t := Vector3.ONE
const _POWER_ITERATIONS := 12
const _TIGHT_MARGIN := 1.05
var _wf2 := 0.0


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
	if tight_step:
		lipschitz = _tight_lipschitz(r, t, n, wf2, wt2, lam, t_max)
	else:
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
	var native := FlightNative.kernels()
	for p in passes:
		if native != null:
			u = native.allocator_solve(u, r, t, state.thruster_axes, state.thruster_cone, state.thruster_planes,
					Thruster.PLANES, target_f, target_t, per_pass, step, wf2, wt2, lam, price)
		else:
			_solve(state, u, target_f, target_t, per_pass, step, wf2, wt2, lam, price)
		if p < passes - 1:
			var achieved: Variant = native.allocator_wrench_of(u, r, t) if native != null else _wrench_of(state, u)
			target_f += wrench.force - achieved[0]
			target_t += wrench.torque - achieved[1]
	_u = u
	_wt2 = wt2
	_wf2 = wf2
	return _u


## Bounded least squares on the throttles alone (FISTA), started from the first stage.
func trim(state: FlightState, wrench: Wrench, dirs: PackedVector3Array,
		lo: PackedFloat32Array, hi: PackedFloat32Array, start: PackedFloat32Array) -> PackedFloat32Array:
	var n := dirs.size()
	var x := start.duplicate()
	for i in n:
		x[i] = clampf(x[i], lo[i], hi[i])
	if trim_iterations <= 0 or _wf2 <= 0.0:
		return x
	var t := state.thruster_max
	var fcol := PackedVector3Array()   # Force and torque per unit throttle
	var tcol := PackedVector3Array()
	fcol.resize(n)
	tcol.resize(n)
	var demand := wrench.force.length()
	var f_dir := wrench.force / demand if demand > 1.0 else Vector3.ZERO
	var side := maxf(trim_sideways_weight, 1.0) if demand > 1.0 else 1.0
	var wt2_max := maxf(_wt2.x, maxf(_wt2.y, _wt2.z))
	var lipschitz := 0.0
	for i in n:
		fcol[i] = dirs[i] * t[i]
		tcol[i] = state.thruster_positions[i].cross(fcol[i])
		lipschitz += 2.0 * (_wf2 * side * fcol[i].length_squared() + wt2_max * tcol[i].length_squared())
	if lipschitz <= 0.0:
		return x
	var step := 1.0 / lipschitz
	var native := FlightNative.kernels()
	if native != null:
		return native.allocator_trim(x, lo, hi, fcol, tcol, f_dir, side, _wf2, _wt2, wrench.force, wrench.torque,
				step, trim_iterations)
	var y := x.duplicate()
	var momentum := 1.0
	for _k in trim_iterations:
		var force := Vector3.ZERO
		var torque := Vector3.ZERO
		for i in n:
			force += fcol[i] * y[i]
			torque += tcol[i] * y[i]
		var e := force - wrench.force
		var along := f_dir * e.dot(f_dir)
		var g_force := (along + (e - along) * side) * (2.0 * _wf2)
		var g_torque := (torque - wrench.torque) * _wt2 * 2.0
		var next_momentum := (1.0 + sqrt(1.0 + 4.0 * momentum * momentum)) * 0.5
		var beta := (momentum - 1.0) / next_momentum
		for i in n:
			var x_new := clampf(y[i] - step * (g_force.dot(fcol[i]) + g_torque.dot(tcol[i])), lo[i], hi[i])
			y[i] = x_new + (x_new - x[i]) * beta
			x[i] = x_new
		momentum = next_momentum
	return x


## FISTA on u (in place) toward a target force/torque, with a propellant price per
## newton of thrust. The hot loop: the gimbal projection (project_to_gimbal) is inlined
## with each thruster's cone trig worked out once per solve, same arithmetic in the same
## order, so the result is identical; it runs ~670 times a tick (28 thrusters × 24).
func _solve(state: FlightState, u: PackedVector3Array, force_target: Vector3, torque_target: Vector3,
		count: int, step: float, wf2: float, wt2: Vector3, lam: float, price: float) -> void:
	var n := u.size()
	var r := state.thruster_positions
	var t := state.thruster_max
	var axes := state.thruster_axes
	var planes := state.thruster_planes
	var np := Thruster.PLANES
	var tan_c := PackedFloat64Array()
	var cos_c := PackedFloat64Array()
	var sin_c := PackedFloat64Array()
	var damping := PackedFloat64Array()   # 2λT², the squared-thrust penalty's gradient factor
	var shrink := PackedFloat64Array()
	tan_c.resize(n)
	cos_c.resize(n)
	sin_c.resize(n)
	damping.resize(n)
	shrink.resize(n)
	for i in n:
		var cone: float = state.thruster_cone[i]
		tan_c[i] = tan(cone)
		cos_c[i] = cos(cone)
		sin_c[i] = sin(cone)
		damping[i] = 2.0 * lam * t[i] * t[i]
		shrink[i] = step * price * t[i]
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
			var ti: float = t[i]
			if ti <= 0.0:
				u[i] = Vector3.ZERO
				y[i] = Vector3.ZERO
				continue
			var yi := y[i]
			var grad := (g_force + g_torque.cross(r[i])) * ti + yi * damping[i]
			var w := yi - grad * step
			# Onto the gimbal cone (project_to_cone)...
			var axis := axes[i]
			var a := w.dot(axis)
			var perp := w - axis * a
			var s := perp.length()
			var v: Vector3
			if s <= a * tan_c[i]:
				v = w
			elif s * tan_c[i] <= -a:
				v = Vector3.ZERO
			elif s < 1e-9:
				v = axis * maxf(a, 0.0)
			else:
				var edge := axis * cos_c[i] + perp / s * sin_c[i]
				v = edge * (a * cos_c[i] + s * sin_c[i])
			var v_len := v.length()
			if v_len > 1.0:
				v = v / v_len
			# ...then inside its swing-limit planes.
			if planes.size() >= np * (i + 1):
				for k in np:
					var m := planes[np * i + k]
					var over := m.dot(v)
					if over > 0.0:
						v -= m * over
			var sh := shrink[i]
			if sh > 0.0:
				var length := v.length()
				v = v * (maxf(length - sh, 0.0) / length) if length > 1e-12 else Vector3.ZERO
			y[i] = v + (v - u[i]) * beta
			u[i] = v
		momentum = next_momentum


## 2 λmax(W½ (Σ Tᵢ² Bᵢ Bᵢᵀ) W½) + 2 λ Tmax², Bᵢ = [I; [rᵢ]×] (force and torque of a unit
## push from thruster i, weighted as the cost weighs them): the steepest the cost can curve,
## so 1/L is the largest step FISTA can safely take. Power iteration on the 6×6 matrix,
## kept as its three sums (Σ T², Σ T² r, Σ T² (|r|² I − r rᵀ)).
func _tight_lipschitz(r: PackedVector3Array, t: PackedFloat32Array, n: int, wf2: float, wt2: Vector3,
		lam: float, t_max: float) -> float:
	var s0 := 0.0
	var sr := Vector3.ZERO
	var srr := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for i in n:
		var ti: float = t[i]
		var t2 := ti * ti
		var ri := r[i]
		var l2 := ri.length_squared()
		s0 += t2
		sr += ri * t2
		srr.x += (Vector3(l2, 0.0, 0.0) - ri * ri.x) * t2
		srr.y += (Vector3(0.0, l2, 0.0) - ri * ri.y) * t2
		srr.z += (Vector3(0.0, 0.0, l2) - ri * ri.z) * t2
	var sf := sqrt(wf2)
	var wt := Vector3(sqrt(wt2.x), sqrt(wt2.y), sqrt(wt2.z))
	var vf := _eig_f
	var vt := _eig_t
	var eig := 0.0
	for _k in _POWER_ITERATIONS:
		var a := vt * wt
		var mf := vf * (wf2 * s0) + a.cross(sr) * sf
		var mt := (sr.cross(vf) * sf + srr * a) * wt
		eig = sqrt(mf.length_squared() + mt.length_squared())
		if eig <= 0.0:
			break
		vf = mf / eig
		vt = mt / eig
	_eig_f = vf
	_eig_t = vt
	return 2.0 * eig * _TIGHT_MARGIN + 2.0 * lam * t_max * t_max


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
