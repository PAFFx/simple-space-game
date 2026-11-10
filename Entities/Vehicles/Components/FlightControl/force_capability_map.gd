class_name ForceCapabilityMap
extends RefCounted

## How much *clean* force (N) the suit can make along each body direction:
## force in that direction with less than `tolerance` leaking sideways or into
## torque. Built by asking the allocator itself (bisection on the demand), so
## it accounts for gimbals, lever arms and thrusters that can only help with
## side effects (e.g. downward mains gimballed sideways also push up).
##
## Built once from a FlightState snapshot; lookup() blends the nearest samples.

const SHARPNESS := 8.0
const PROBE_ITERATIONS := 80

var dirs := PackedVector3Array()
var values := PackedFloat32Array()


static func build(state: FlightState, allocator: ThrustAllocator, count: int = 48,
		tolerance: float = 0.06, steps: int = 7) -> ForceCapabilityMap:
	var map := ForceCapabilityMap.new()
	var upper := 0.0
	for t in state.thruster_max:
		upper += t
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - 2.0 * (i + 0.5) / count
		var radius := sqrt(1.0 - y * y)
		var dir := Vector3(cos(golden * i) * radius, y, sin(golden * i) * radius)
		var lo := 0.0
		var hi := upper
		# One probe per direction, warm-started across the bisection steps (their
		# solutions differ mostly in scale), so few iterations per step suffice.
		var probe: ThrustAllocator = allocator.duplicate()
		if probe is ConeProjectedAllocator:
			(probe as ConeProjectedAllocator).iterations = PROBE_ITERATIONS
			(probe as ConeProjectedAllocator).warm_start_decay = 1.0
		for _s in steps:
			var mid := (lo + hi) * 0.5
			if _is_clean(state, probe, dir, mid, tolerance):
				lo = mid
			else:
				hi = mid
		map.dirs.append(dir)
		map.values.append(lo)
	return map


## Interpolated clean authority along a unit body direction, N.
func lookup(dir: Vector3) -> float:
	var sum := 0.0
	var weight := 0.0
	for i in dirs.size():
		var d := dirs[i].dot(dir)
		if d <= 0.0:
			continue
		var w := pow(d, SHARPNESS)
		sum += values[i] * w
		weight += w
	return sum / weight if weight > 0.0 else 0.0


static func _is_clean(state: FlightState, probe: ThrustAllocator, dir: Vector3,
		magnitude: float, tolerance: float) -> bool:
	var u := probe.allocate(state, Wrench.new(dir * magnitude, Vector3.ZERO))
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	for i in u.size():
		var f := u[i] * state.thruster_max[i]
		force += f
		torque += state.thruster_positions[i].cross(f)
	var along := force.dot(dir)
	var side := (force - dir * along).length()
	return along >= magnitude * (1.0 - tolerance) and side <= magnitude * tolerance \
			and torque.length() <= magnitude * tolerance * 4.0
