class_name GreedyAllocator
extends ThrustAllocator

## Crude baseline: every thruster independently aims where it helps the demanded
## wrench most and sizes its throttle as if it had to deliver it alone, then all
## contributions are shared out evenly. No iteration, no coordination, so expect
## overshoot, wasted propellant and cross-coupling. Handy for comparing against
## ConeProjectedAllocator and as a starting point for experiments.

@export var reference_arm: float = 4.0


func allocate(state: FlightState, wrench: Wrench) -> PackedVector3Array:
	var n := state.thruster_axes.size()
	var out := PackedVector3Array()
	out.resize(n)
	var wt2 := 1.0 / (reference_arm * reference_arm)

	var active := 0
	for i in n:
		var t := state.thruster_max[i]
		var r := state.thruster_positions[i]
		if t <= 0.0:
			continue
		# Most useful direction for this thruster = negative cost gradient at zero thrust.
		var useful := wrench.force + wrench.torque.cross(r) * wt2
		var aimed := project_to_cone(useful.normalized(), state.thruster_axes[i], state.thruster_cone[i])
		if aimed.length_squared() < 1e-8:
			continue
		var dir := aimed.normalized()
		var lever := r.cross(dir)
		var throttle := dir.dot(useful) / (t * (1.0 + wt2 * lever.length_squared()))
		if throttle > 0.0:
			out[i] = dir * throttle
			active += 1

	if active > 1:
		for i in n:
			out[i] = (out[i] / float(active)).limit_length(1.0)
	else:
		for i in n:
			out[i] = out[i].limit_length(1.0)
	return out
