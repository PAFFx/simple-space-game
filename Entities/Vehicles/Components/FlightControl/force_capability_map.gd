class_name ForceCapabilityMap
extends RefCounted

## How much *clean* force (N) the suit can make along each body direction:
## force in that direction with less than `tolerance` leaking sideways or into
## torque. Built by asking the allocator itself (bisection on the demand), so
## it accounts for gimbals, lever arms and thrusters that can only help with
## side effects (e.g. downward mains gimballed sideways also push up).
## It's also capped at the thrust of the thrusters that can aim within
## acos(`min_alignment`) of the direction: beyond that, the extra force comes from
## thrusters mostly cancelling each other, which burns a lot of propellant for little
## push in weak directions (e.g. straight down).
##
## Built from a FlightState snapshot, all at once (build) or a few directions per tick
## (start / step, for rebuilding while flying); lookup() blends the nearest samples.

const SHARPNESS := 8.0
const PROBE_ITERATIONS := 80
const FLOOR := 0.02

var dirs := PackedVector3Array()
var values := PackedFloat32Array()
## lookup()'s floor (FLOOR of the strongest sample), kept until values change (−1 = stale):
## the attitude solver looks up ~44 directions a tick.
var _floor := -1.0
## Clean torque per body axis, N·m: what the thrusters can turn with before they start
## borrowing off-centre thrust, which shoves the suit sideways. Measured like the force.
var clean_torque := Vector3.ZERO


const COUNT := 48
const TOLERANCE := 0.06
const STEPS := 7

# Incremental build state.
var _state: FlightState
var _allocator: ThrustAllocator
var _min_alignment := 0.0
var _next := 0


static func build(state: FlightState, allocator: ThrustAllocator, min_alignment: float = 0.0) \
		-> ForceCapabilityMap:
	var map := start(state, allocator, min_alignment)
	map.step(COUNT)
	return map


## Begins an incremental build; call step() until it returns true.
static func start(state: FlightState, allocator: ThrustAllocator, min_alignment: float = 0.0) \
		-> ForceCapabilityMap:
	var map := ForceCapabilityMap.new()
	map._state = state
	map._allocator = allocator
	map._min_alignment = min_alignment
	return map


## Measures up to `count` more directions. True when the map is complete.
func step(count: int) -> bool:
	var upper := 0.0
	for t in _state.thruster_max:
		upper += t
	var golden := PI * (3.0 - sqrt(5.0))
	var end := mini(_next + count, COUNT)
	for i in range(_next, end):
		var y := 1.0 - 2.0 * (i + 0.5) / COUNT
		var radius := sqrt(1.0 - y * y)
		var dir := Vector3(cos(golden * i) * radius, y, sin(golden * i) * radius)
		var lo := 0.0
		var hi := upper
		var probe := _probe(_allocator)
		for _s in STEPS:
			var mid := (lo + hi) * 0.5
			if _is_clean(_state, probe, dir, mid, TOLERANCE):
				lo = mid
			else:
				hi = mid
		if _min_alignment > 0.0:
			lo = minf(lo, _aimed_thrust(_state, dir, _min_alignment))
		dirs.append(dir)
		values.append(lo)
		_floor = -1.0
	_next = end
	if _next >= COUNT:
		clean_torque = _measure_torque(_state, _allocator)
		_state = null
		_allocator = null
		return true
	return false


## Interpolated clean authority along a unit body direction, N. A weighted
## harmonic mean, so a strong neighbour (e.g. "up") never inflates a weak
## in-between direction: overestimates make the allocator spill force. Samples are
## floored at a small share of the strongest, so a far-off zero can't drag a strong
## direction down.
func lookup(dir: Vector3) -> float:
	var inv_sum := 0.0
	var weight := 0.0
	if _floor < 0.0:
		_floor = 1.0
		for v in values:
			_floor = maxf(_floor, v * FLOOR)
	var floor_value := _floor
	for i in dirs.size():
		var d := dirs[i].dot(dir)
		if d <= 0.0:
			continue
		var w := pow(d, SHARPNESS)
		inv_sum += w / maxf(values[i], floor_value)
		weight += w
	return weight / inv_sum if inv_sum > 0.0 else 0.0


## Largest torque about each axis (the weaker of its two directions) the allocator
## delivers with little force or off-axis torque on the side.
static func _measure_torque(state: FlightState, allocator: ThrustAllocator) -> Vector3:
	var out := Vector3.ZERO
	var arm := 4.0
	if allocator is ConeProjectedAllocator:
		arm = (allocator as ConeProjectedAllocator).reference_arm
	for k in 3:
		var clean := INF
		for sign: float in [1.0, -1.0]:
			var axis := Vector3.ZERO
			axis[k] = sign
			var probe := _probe(allocator)
			var lo := 0.0
			var hi := state.max_torque_ideal[k]
			for _s in STEPS:
				var mid := (lo + hi) * 0.5
				var u := probe.allocate(state, Wrench.new(Vector3.ZERO, axis * mid))
				u = probe.allocate(state, Wrench.new(Vector3.ZERO, axis * mid))
				var force := Vector3.ZERO
				var torque := Vector3.ZERO
				for i in u.size():
					var f := u[i] * state.thruster_max[i]
					force += f
					torque += state.thruster_positions[i].cross(f)
				var along := torque.dot(axis)
				if along >= mid * (1.0 - TOLERANCE) and (torque - axis * along).length() <= mid * TOLERANCE \
						and force.length() * arm <= mid * TOLERANCE:
					lo = mid
				else:
					hi = mid
			clean = minf(clean, lo)
		out[k] = clean
	return out


## A copy of the allocator for probing: warm-started across the bisection steps (their
## solutions differ mostly in scale), without the propellant price, so it measures
## what the thrusters can physically do.
static func _probe(allocator: ThrustAllocator) -> ThrustAllocator:
	var probe: ThrustAllocator = allocator.duplicate()
	if probe is ConeProjectedAllocator:
		var cone := probe as ConeProjectedAllocator
		cone.iterations = PROBE_ITERATIONS
		cone.warm_start_decay = 1.0
		cone.fuel_cost = 0.0
	return probe


## Thrust along dir from the thrusters whose gimbal can aim within acos(min_alignment) of it.
static func _aimed_thrust(state: FlightState, dir: Vector3, min_alignment: float) -> float:
	var sum := 0.0
	for i in state.thruster_axes.size():
		var c := cos(maxf(0.0, state.thruster_axes[i].angle_to(dir) - state.thruster_cone[i]))
		if c >= min_alignment:
			sum += state.thruster_max[i] * c
	return sum


static func _is_clean(state: FlightState, probe: ThrustAllocator, dir: Vector3,
		magnitude: float, tolerance: float) -> bool:
	var r := _result(state, probe, dir, magnitude)
	return r[0] >= magnitude * (1.0 - tolerance) and r[1] <= magnitude * tolerance \
			and r[2] <= magnitude * tolerance * 4.0


## [force along dir, sideways force, torque, total thrust] of an allocation.
static func _result(state: FlightState, probe: ThrustAllocator, dir: Vector3,
		magnitude: float) -> PackedFloat32Array:
	var u := probe.allocate(state, Wrench.new(dir * magnitude, Vector3.ZERO))
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var thrust := 0.0
	for i in u.size():
		var f := u[i] * state.thruster_max[i]
		force += f
		torque += state.thruster_positions[i].cross(f)
		thrust += f.length()
	var along := force.dot(dir)
	return PackedFloat32Array([along, (force - dir * along).length(), torque.length(), thrust])
