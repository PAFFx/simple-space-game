class_name ThrusterGuards
extends Node

## Turns the model's own nozzles with their thrusters' actual gimbal, and swings guard
## plates to follow them. Purely visual: the thrusters stay on their own bones, so this
## motion doesn't add to the nozzle's aim.

@export var skeleton: Skeleton3D
@export var guards: Array[ThrusterGuard] = []

var angles := PackedFloat32Array()   ## Current guard angles, rad
var _thrusters: Array = []           ## Per guard: Array[Thruster]


func _ready() -> void:
	if skeleton == null:
		push_error("ThrusterGuards: skeleton not assigned")
		return
	var vehicle := VehicleBase.find_vehicle(self)
	var by_name := {}
	for t in (vehicle if vehicle else get_parent()).find_children("*", "Thruster", true, false):
		by_name[t.name] = t
	angles.resize(guards.size())
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
func rotation_of(i: int) -> Quaternion:
	var g := guards[i]
	if not g.full_rotation:
		var angle := measure(i)
		angles[i] = angle
		return Quaternion(g.axis.normalized(), angle)
	var list: Array = _thrusters[i]
	if list.is_empty():
		return Quaternion.IDENTITY
	var t: Thruster = list[0]
	var from := t.get_nominal_direction_global()
	if g.rest_thrust != Vector3.ZERO:
		from = (skeleton.global_basis * g.rest_thrust).normalized()
	var q := Quaternion(from, t.get_thrust_direction_global())
	angles[i] = q.get_angle()
	var skel := skeleton.global_basis.get_rotation_quaternion()
	return skel.inverse() * q * skel


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
