class_name ThrusterGuards
extends Node

## Turns the model's own nozzles with their thrusters' actual gimbal, and swings guard
## plates to follow them. Purely visual: the thrusters stay on their own bones, so this
## motion doesn't add to the nozzle's aim.

@export var skeleton: Skeleton3D
@export var guards: Array[ThrusterGuard] = []

var angles := PackedFloat32Array()   ## Current guard angles, rad
var _thrusters: Array = []           ## Per guard: Array[Thruster]
var _open := PackedByteArray()       ## Cover mode: open
var _calm := PackedFloat32Array()    ## Cover mode: time the nozzle has been back, s
var _smoothed: Array[Quaternion] = []  ## Full rotation: low-passed aim


func _ready() -> void:
	if skeleton == null:
		push_error("ThrusterGuards: skeleton not assigned")
		return
	var vehicle := VehicleBase.find_vehicle(self)
	var by_name := {}
	for t in (vehicle if vehicle else get_parent()).find_children("*", "Thruster", true, false):
		by_name[t.name] = t
	angles.resize(guards.size())
	_open.resize(guards.size())
	_calm.resize(guards.size())
	for g in guards:
		_smoothed.append(Quaternion.IDENTITY)
	for g in guards:
		var list: Array[Thruster] = []
		for n in g.thrusters:
			if by_name.has(n):
				list.append(by_name[n])
			else:
				push_warning("ThrusterGuards: no thruster '%s'" % n)
		_thrusters.append(list)
	var modifier := ThrusterGuardModifier.new()
	modifier.name = "ThrusterGuardModifier"
	modifier.guards = self
	skeleton.add_child(modifier)


## Skeleton-space rotation for guard i at its bone.
func rotation_of(i: int, delta: float) -> Quaternion:
	var g := guards[i]
	if g.open_angle_deg != 0.0:
		return Quaternion(g.axis.normalized(), _cover_angle(i, delta))
	if not g.full_rotation:
		var k := 1.0 if g.smoothing_time <= 0.0 else 1.0 - exp(-delta / g.smoothing_time)
		angles[i] = lerpf(angles[i], measure(i), k)
		return Quaternion(g.axis.normalized(), angles[i])
	var list: Array = _thrusters[i]
	if list.is_empty():
		return Quaternion.IDENTITY
	# Average over the part's thrusters (a pod carrying two nozzles), weighted by how hard
	# each fires, in skeleton space; then low-passed.
	var skel := skeleton.global_basis.get_rotation_quaternion()
	var q := Quaternion.IDENTITY
	var weight := 0.0
	for t: Thruster in list:
		var from := t.get_nominal_direction_global()
		if g.rest_thrust != Vector3.ZERO:
			from = (skeleton.global_basis * g.rest_thrust).normalized()
		var w := maxf(t.throttle, 0.02)
		weight += w
		q = q.slerp(Quaternion(from, t.get_thrust_direction_global()), w / weight)
	q = skel.inverse() * q * skel
	var k := 1.0 if g.smoothing_time <= 0.0 else 1.0 - exp(-delta / g.smoothing_time)
	_smoothed[i] = _smoothed[i].slerp(q, k).normalized()
	angles[i] = _smoothed[i].get_angle()
	return _smoothed[i]


## Cover: opens out (one way only) while the nozzle is swung, holds, then closes a moment
## after it's back, each at a steady rate, so it never flaps with small adjustments.
func _cover_angle(i: int, delta: float) -> float:
	var g := guards[i]
	var swing := 0.0
	for t: Thruster in _thrusters[i]:
		swing = maxf(swing, t.get_nominal_direction_global().angle_to(t.get_thrust_direction_global()))
	swing = rad_to_deg(swing)
	if swing > g.open_above_deg:
		_open[i] = 1
		_calm[i] = 0.0
	elif swing < g.close_below_deg and _open[i] == 1:
		_calm[i] += delta
		if _calm[i] >= g.close_delay:
			_open[i] = 0
	else:
		_calm[i] = 0.0
	var target := deg_to_rad(g.open_angle_deg) if _open[i] == 1 else 0.0
	var rate := deg_to_rad(g.open_rate_deg if _open[i] == 1 else g.close_rate_deg)
	angles[i] = move_toward(angles[i], target, rate * delta)
	return angles[i]


## Deflection of the guard's nozzles about its hinge, rad (average over its thrusters).
func measure(i: int) -> float:
	var g := guards[i]
	var list: Array = _thrusters[i]
	if list.is_empty():
		return 0.0
	var hinge := (skeleton.global_basis * g.axis).normalized()
	var sum := 0.0
	for t: Thruster in list:
		var nominal := t.get_nominal_direction_global()
		var actual := t.get_thrust_direction_global()
		var a := nominal - hinge * nominal.dot(hinge)
		var b := actual - hinge * actual.dot(hinge)
		if a.length_squared() > 1e-8 and b.length_squared() > 1e-8:
			sum += a.signed_angle_to(b, hinge)
	var angle := sum / list.size() * g.follow
	return clampf(angle, deg_to_rad(g.min_angle_deg), deg_to_rad(g.max_angle_deg))
