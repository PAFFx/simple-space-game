class_name SensorFovSolver

## Works out which part of the panoramic sphere a viewer camera can see, and the
## sensor camera aim / FOV / SubViewport size needed to cover exactly that part.
## Works for a viewer inside the sphere (pilot) and outside it (looking in through
## the open hatch). All functions are stateless.

const _APERTURE_GRID := Vector2i(7, 5)


## Screen-local unit directions (from the sphere centre) of the screen points the
## viewer can see. Empty when none are visible (e.g. outside with the hatch shut).
static func sample_visible_directions(
	viewer_camera: Camera3D, screen: PanoramicScreen
) -> PackedVector3Array:
	var screen_xf := screen.get_display_transform()
	var to_local := screen_xf.affine_inverse()
	var origin := to_local * viewer_camera.global_position
	var radius := screen.screen_radius
	var dirs := PackedVector3Array()
	var inside := origin.length() < radius

	if not inside and screen.get_aperture_amount() <= 0.0:
		return dirs

	# Frustum rays: centre, corners, edge midpoints.
	var vp := viewer_camera.get_viewport().get_visible_rect().size
	for f: Vector2 in [Vector2(0.5, 0.5), Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
			Vector2(1, 1), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0, 0.5), Vector2(1, 0.5)]:
		var ray := (to_local.basis * viewer_camera.project_ray_normal(vp * f)).normalized()
		var t := SpatialMath.ray_sphere_entry_exit(origin, ray, Vector3.ZERO, radius)
		if t.y <= 0.0:
			continue
		# Outside: the near wall is back-face culled, so the visible pixel is where
		# the ray leaves the sphere, and only rays entering through the hatch count.
		if not inside and not screen.is_in_aperture((origin + ray * t.x).normalized()):
			continue
		dirs.append((origin + ray * t.y).normalized())

	if inside:
		return dirs

	# From outside the opening is usually a small patch of the frame that the
	# frustum rays miss, so also aim rays through a grid over the aperture.
	var amount := screen.get_aperture_amount()
	var centre := screen.get_aperture_center_rad()
	var half := screen.get_aperture_half_size_rad() * Vector2(1.0, amount)
	for ix in _APERTURE_GRID.x:
		for iy in _APERTURE_GRID.y:
			var g := Vector2(ix, iy) / Vector2(_APERTURE_GRID - Vector2i.ONE) * 2.0 - Vector2.ONE
			var a := centre + g * half
			var entry := PanoramicScreen.angles_to_direction(a.x, a.y) * radius
			if (origin - entry).dot(entry) <= 0.0:
				continue  # opening faces away from the viewer
			if not viewer_camera.is_position_in_frustum(screen_xf * entry):
				continue
			var ray := (entry - origin).normalized()
			var t := SpatialMath.ray_sphere_entry_exit(origin, ray, Vector3.ZERO, radius)
			dirs.append((origin + ray * t.y).normalized())
	return dirs


## Mean of the directions: the sensor camera aims here. Zero if dirs is empty.
static func aim_direction(dirs: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for d in dirs:
		sum += d
	return sum.normalized()


## Minimum H/V FOV in degrees for a camera looking along `look` (with the given
## right/up axes) to contain every direction in `dirs`.
static func solve_required_fov(
	dirs: PackedVector3Array,
	look: Vector3,
	cam_right: Vector3,
	cam_up: Vector3,
	safety_margin_deg: float
) -> Vector2:
	var max_h := 0.0
	var max_v := 0.0
	for d in dirs:
		var fwd := d.dot(look)
		max_h = maxf(max_h, absf(atan2(d.dot(cam_right), fwd)))
		max_v = maxf(max_v, absf(atan2(d.dot(cam_up), fwd)))
	return Vector2(
		clampf(rad_to_deg(max_h) * 2.0 + safety_margin_deg, 10.0, 160.0),
		clampf(rad_to_deg(max_v) * 2.0 + safety_margin_deg, 10.0, 160.0)
	)


## Computes the ideal SubViewport size (pixels) given the viewer camera,
## quality scale, and required H/V FOV.
##
## Derives horizontal pixels from the true perspective aspect ratio so the
## sensor camera's projection stays geometrically accurate.
## tan(hfov/2) / tan(vfov/2) is the correct pixel aspect for a perspective camera —
## NOT the simple FOV ratio, which would mis-size the viewport for wide-angle cases.
static func compute_viewport_size(
	viewer_camera: Camera3D,
	quality_scale: float,
	required_vfov_deg: float,
	required_hfov_deg: float,
	min_size: int,
	max_size: int
) -> Vector2i:
	var display_h := viewer_camera.get_viewport().get_visible_rect().size.y
	var ppd       := (display_h / viewer_camera.fov) * quality_scale

	var new_vpx := int(clampf(ppd * required_vfov_deg, float(min_size), float(max_size)))
	var aspect  := tan(deg_to_rad(required_hfov_deg * 0.5)) / tan(deg_to_rad(required_vfov_deg * 0.5))
	var new_hpx := int(clampf(float(new_vpx) * aspect, float(min_size), float(max_size)))
	return Vector2i(new_hpx, new_vpx)
