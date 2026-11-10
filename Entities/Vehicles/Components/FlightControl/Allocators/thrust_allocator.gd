@abstract
class_name ThrustAllocator
extends Resource

## Distributes a desired body wrench over the available thrusters.
##
## Pure math: reads thruster geometry from FlightState and returns one vector
## per thruster, in the body frame, whose direction is the thrust direction and
## whose length is the throttle in [0, 1]. Thruster nodes are never touched
## here, which keeps allocators swappable and testable in isolation.


## Override: return state.thruster_axes.size() command vectors.
@abstract func allocate(state: FlightState, wrench: Wrench) -> PackedVector3Array


## Projects u onto {v : angle(v, axis) <= cone, |v| <= 1}: the set of thrust
## vectors a gimballed thruster can actually produce (throttle-normalised).
static func project_to_cone(u: Vector3, axis: Vector3, cone: float) -> Vector3:
	var a := u.dot(axis)
	var perp := u - axis * a
	var s := perp.length()
	var tan_c := tan(cone)
	var v: Vector3
	if s <= a * tan_c:
		v = u                                   # already inside the cone
	elif s * tan_c <= -a:
		v = Vector3.ZERO                        # in the polar cone: nearest point is the apex
	elif s < 1e-9:
		v = axis * maxf(a, 0.0)
	else:
		var edge := axis * cos(cone) + perp / s * sin(cone)
		v = edge * (a * cos(cone) + s * sin(cone))
	var length := v.length()
	return v / length if length > 1.0 else v
