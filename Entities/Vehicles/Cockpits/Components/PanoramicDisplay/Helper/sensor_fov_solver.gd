class_name SensorFovSolver

## Computes the minimum sensor camera FOV and SubViewport size needed to cover
## the visible portion of a panoramic sphere from the viewer's perspective.
##
## Extracted from SensorHead to keep that class focused on lifecycle management.
## All functions are stateless — no node is required to call them.


## Casts 9 frustum sample rays against the panoramic sphere and returns the minimum
## H/V FOV (in degrees) the sensor camera needs to cover every visible point.
##
## Sample layout: centre + 4 corners + 4 edge midpoints.
## Corners catch diagonal worst-case; edge midpoints isolate each axis cleanly.
##
## Returns Vector2(required_hfov_deg, required_vfov_deg).
## Returns Vector2(-1.0, -1.0) if no sample ray hits the sphere.
static func solve_required_fov(
	viewer_camera: Camera3D,
	sphere_center: Vector3,
	sphere_radius: float,
	sensor_position: Vector3,
	world_look: Vector3,
	cam_right: Vector3,
	cam_up: Vector3,
	safety_margin_deg: float
) -> Vector2:
	var viewer_pos := viewer_camera.global_position
	var vp_size    := viewer_camera.get_viewport().get_visible_rect().size

	var sample_pixels: Array[Vector2] = [
		vp_size * 0.5,                            # centre
		Vector2(0.0,          0.0),               # top-left
		Vector2(vp_size.x,    0.0),               # top-right
		Vector2(0.0,          vp_size.y),         # bottom-left
		vp_size,                                   # bottom-right
		Vector2(vp_size.x * 0.5, 0.0),           # top-centre    (pure V)
		Vector2(vp_size.x * 0.5, vp_size.y),     # bottom-centre (pure V)
		Vector2(0.0,          vp_size.y * 0.5),   # left-centre   (pure H)
		Vector2(vp_size.x,    vp_size.y * 0.5),  # right-centre  (pure H)
	]

	var max_h_half_angle := 0.0
	var max_v_half_angle := 0.0
	var any_hit          := false

	for pixel in sample_pixels:
		var ray_dir := viewer_camera.project_ray_normal(pixel)
		var t := SpatialMath.ray_sphere_intersect(
			viewer_pos, ray_dir, sphere_center, sphere_radius)
		if t < 0.0:
			continue
		any_hit = true
		var panoramic_dir := (viewer_pos + ray_dir * t - sphere_center).normalized()

		# Project panoramic_dir into sensor camera's local H and V planes.
		# atan2(lateral, forward) gives the perspective angle in each axis.
		# d_fwd > 0 means the direction is in front of the sensor camera.
		var d_fwd   := panoramic_dir.dot(world_look)
		var h_angle := absf(atan2(panoramic_dir.dot(cam_right), d_fwd))
		var v_angle := absf(atan2(panoramic_dir.dot(cam_up),    d_fwd))

		if h_angle > max_h_half_angle:
			max_h_half_angle = h_angle
		if v_angle > max_v_half_angle:
			max_v_half_angle = v_angle

	if not any_hit:
		return Vector2(-1.0, -1.0)

	return Vector2(
		clampf(rad_to_deg(max_h_half_angle) * 2.0 + safety_margin_deg, 10.0, 160.0),
		clampf(rad_to_deg(max_v_half_angle) * 2.0 + safety_margin_deg, 10.0, 160.0)
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
