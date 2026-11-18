class_name SpatialMath

## General-purpose 3D spatial math utilities.
## Named SpatialMath to avoid shadowing Godot's built-in Geometry3D singleton.


## Returns the nearest positive ray parameter t where (ray_origin + t * ray_dir) hits the sphere.
## Returns -1.0 if the ray misses or all intersections are behind the ray origin.
##
## Uses the half-b form (assumes unit ray direction):
##   disc = b² - c,  b = d·dir,  c = |d|² - r²,  d = ray_origin - sphere_center
static func ray_sphere_intersect(
	ray_origin: Vector3, ray_dir: Vector3,
	sphere_center: Vector3, sphere_radius: float
) -> float:
	var d    := ray_origin - sphere_center
	var b    := d.dot(ray_dir)
	var c    := d.dot(d) - sphere_radius * sphere_radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t0 := -b - sq
	var t1 := -b + sq
	if t0 > 0.001:
		return t0
	if t1 > 0.001:
		return t1
	return -1.0


## Returns Vector2(t_enter, t_exit) for a unit-direction ray against a sphere, or
## Vector2(-1, -1) if the line misses. Either t may be negative (behind the origin).
static func ray_sphere_entry_exit(
	ray_origin: Vector3, ray_dir: Vector3,
	sphere_center: Vector3, sphere_radius: float
) -> Vector2:
	var d    := ray_origin - sphere_center
	var b    := d.dot(ray_dir)
	var disc := b * b - (d.dot(d) - sphere_radius * sphere_radius)
	if disc < 0.0:
		return Vector2(-1.0, -1.0)
	var sq := sqrt(disc)
	return Vector2(-b - sq, -b + sq)


## Time for a shot of constant `speed` to meet a target at `rel_pos` moving at `rel_vel`
## (both relative to the shooter, whose velocity the shot inherits). -1 if it never does.
static func intercept_time(rel_pos: Vector3, rel_vel: Vector3, speed: float) -> float:
	var a := rel_vel.length_squared() - speed * speed
	var b := 2.0 * rel_pos.dot(rel_vel)
	var c := rel_pos.length_squared()
	if absf(a) < 1e-9:
		return -c / b if b < 0.0 else -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t0 := (-b - sq) / (2.0 * a)
	var t1 := (-b + sq) / (2.0 * a)
	var lo := minf(t0, t1)
	var hi := maxf(t0, t1)
	if lo > 0.0:
		return lo
	return hi if hi > 0.0 else -1.0


## intercept_time for a beam whose front is already `reach` out: t when
## |rel_pos + rel_vel·t| = reach + speed·t (0 if already within reach, -1 if never).
static func intercept_time_ahead(rel_pos: Vector3, rel_vel: Vector3, speed: float, reach: float) -> float:
	if rel_pos.length() <= reach:
		return 0.0
	var a := rel_vel.dot(rel_vel) - speed * speed
	var b := 2.0 * (rel_pos.dot(rel_vel) - reach * speed)
	var c := rel_pos.dot(rel_pos) - reach * reach
	if absf(a) < 1e-6:
		return -c / b if b < 0.0 else -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var r := sqrt(disc)
	var t1 := (-b - r) / (2.0 * a)
	var t2 := (-b + r) / (2.0 * a)
	var t := minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	return t if t > 0.0 else -1.0


## Direction for azimuth (+ = right) and elevation (+ = up) in degrees; forward is -Z.
static func angles_to_direction(angles_deg: Vector2) -> Vector3:
	var az := deg_to_rad(angles_deg.x)
	var el := deg_to_rad(angles_deg.y)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


## Azimuth and elevation in degrees of a direction (see angles_to_direction).
static func direction_to_angles(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(rad_to_deg(atan2(d.x, -d.z)), rad_to_deg(asin(clampf(d.y, -1.0, 1.0))))
