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
