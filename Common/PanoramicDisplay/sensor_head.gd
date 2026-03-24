class_name SensorHead
extends Node3D

## Manages a sensor camera at the mech's head pivot.
## Tracks the viewer camera's look direction and renders only the angular
## slice of the world the viewer is currently looking at, feeding the result
## to PanoramicScreen via a SubViewport texture.
##
## When panoramic_screen is set, FOV and viewport size are computed each frame
## by casting the viewer's frustum corner rays through the screen sphere.
## This gives the exact sensor FOV needed without any static margin guesswork,
## and scales resolution proportionally to how much of the screen is visible.

@export var viewer_camera: Camera3D

## Reference to the panoramic screen sphere for geometry-based FOV computation.
## If null, falls back to viewer_fov + 90° static margin.
@export var panoramic_screen: PanoramicScreen

## Render quality relative to the player's display resolution.
## 1.0 = sensor renders at exactly display resolution (1:1 pixel ratio on screen).
## 2.0 = 2× display resolution (super-sampled, sharper, more expensive).
## 0.5 = half display resolution (cheaper, blurrier).
## The actual pixels_per_degree is computed automatically from the display size and
## viewer FOV each frame, so this stays correct across 1080p / 2K / 4K displays.
@export var quality_scale: float = 1.0

## Safety margin added on top of the geometry-computed FOV.
## Covers 1-frame rotation lag and floating-point precision at sphere edges.
@export var fov_safety_margin_degrees: float = 2.0

@export var min_viewport_size: int = 256
@export var max_viewport_size: int = 4096

var _viewport: SubViewport
var _camera: Camera3D

var _dbg_last_vfov: float = 0.0
var _dbg_last_hfov: float = 0.0
var _dbg_last_viewport: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_create_viewport()
	_create_camera()


func _process(_delta: float) -> void:
	if viewer_camera == null:
		return
	_update_camera()


# --- Private ---

func _create_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SensorViewport"
	_viewport.size = Vector2i(min_viewport_size, min_viewport_size)
	# Share the main scene's World3D so the sensor camera sees the same objects.
	_viewport.own_world_3d = false
	_viewport.disable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)


func _create_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "SensorCamera"
	# Hide the mech body and all equipment from the sensor by default.
	# Use set_group_visible() to selectively re-enable layers once individual
	# body parts have been assigned their own sensor sub-layers.
	_camera.cull_mask = Layers.WORLD | Layers.FX
	_camera.near = 0.5
	_camera.far = 2000.0
	_viewport.add_child(_camera)


func _update_camera() -> void:
	if panoramic_screen == null:
		_update_camera_fallback()
		return

	var viewer_pos    := viewer_camera.global_position
	var viewer_basis  := viewer_camera.global_transform.basis
	var sensor_pos    := global_position
	var sphere_center := panoramic_screen.global_position
	var sphere_radius := panoramic_screen.screen_radius

	# Sensor camera is always aimed in the viewer's look direction.
	# SubViewport has no spatial transform — _camera.transform IS world-space.
	var world_look := -viewer_basis.z
	var viewer_up  := viewer_basis.y
	var up := viewer_up if abs(world_look.dot(viewer_up)) < 0.99 else viewer_basis.x
	_camera.transform = Transform3D(Basis.looking_at(world_look, up), sensor_pos)

	# Decompose the sensor camera's local axes for per-axis FOV computation.
	# cam_right and cam_up are used to project panoramic directions into
	# horizontal and vertical angular components separately.
	var cam_basis := _camera.transform.basis
	var cam_right := cam_basis.x          # camera local +X (rightward)
	var cam_up    := cam_basis.y          # camera local +Y (upward)

	# Sample 9 frustum points: center + 4 corners + 4 edge midpoints.
	# Corners capture diagonal worst-case; edge midpoints isolate each axis cleanly.
	var vp_size := viewer_camera.get_viewport().get_visible_rect().size
	var sample_pixels: Array[Vector2] = [
		vp_size * 0.5,                                    # centre
		Vector2(0.0,          0.0),                       # top-left
		Vector2(vp_size.x,    0.0),                       # top-right
		Vector2(0.0,          vp_size.y),                 # bottom-left
		vp_size,                                           # bottom-right
		Vector2(vp_size.x * 0.5, 0.0),                   # top-centre    (pure V)
		Vector2(vp_size.x * 0.5, vp_size.y),             # bottom-centre (pure V)
		Vector2(0.0,          vp_size.y * 0.5),           # left-centre   (pure H)
		Vector2(vp_size.x,    vp_size.y * 0.5),          # right-centre  (pure H)
	]

	var max_h_half_angle := 0.0
	var max_v_half_angle := 0.0
	var any_hit          := false

	for idx in range(sample_pixels.size()):
		var ray_dir := viewer_camera.project_ray_normal(sample_pixels[idx])
		var t := _ray_sphere_intersect(viewer_pos, ray_dir, sphere_center, sphere_radius)
		if t < 0.0:
			continue
		any_hit = true
		var panoramic_dir := (viewer_pos + ray_dir * t - sphere_center).normalized()

		# Project panoramic_dir into sensor camera's local H and V planes.
		# atan2(lateral, forward) gives the perspective angle in each axis.
		# d_fwd > 0 means the direction is in front of the sensor camera.
		var d_fwd := panoramic_dir.dot(world_look)
		var h_angle: float = abs(atan2(panoramic_dir.dot(cam_right), d_fwd))
		var v_angle: float = abs(atan2(panoramic_dir.dot(cam_up),    d_fwd))

		if h_angle > max_h_half_angle:
			max_h_half_angle = h_angle
		if v_angle > max_v_half_angle:
			max_v_half_angle = v_angle

	if not any_hit:
		_camera.fov = 10.0
		return

	var required_vfov := clampf(
		rad_to_deg(max_v_half_angle) * 2.0 + fov_safety_margin_degrees, 10.0, 160.0)
	var required_hfov := clampf(
		rad_to_deg(max_h_half_angle) * 2.0 + fov_safety_margin_degrees, 10.0, 160.0)

	# Camera3D.fov is vertical FOV (keep_aspect = KEEP_HEIGHT default).
	# Horizontal FOV is derived automatically from the viewport aspect ratio.
	_camera.fov = required_vfov

	# Compute pixels_per_degree from the actual display resolution and viewer FOV.
	# quality_scale = 1.0 gives exactly 1 sensor pixel per display pixel on the vertical axis.
	var display_h := viewer_camera.get_viewport().get_visible_rect().size.y
	var ppd       := (display_h / viewer_camera.fov) * quality_scale

	var new_vpx := int(clampf(ppd * required_vfov, float(min_viewport_size), float(max_viewport_size)))
	# Derive horizontal pixels from the true perspective aspect ratio, not the FOV ratio.
	# tan(hfov/2) / tan(vfov/2) is the correct pixel aspect for a perspective camera.
	var aspect  := tan(deg_to_rad(required_hfov * 0.5)) / tan(deg_to_rad(required_vfov * 0.5))
	var new_hpx := int(clampf(
			float(new_vpx) * aspect, float(min_viewport_size), float(max_viewport_size)))

	# Resize only when either dimension changes by > 10%.
	var size_changed := (
		absf(float(new_vpx - _viewport.size.y)) > float(_viewport.size.y) * 0.1 or
		absf(float(new_hpx - _viewport.size.x)) > float(_viewport.size.x) * 0.1
	)
	if size_changed:
		_viewport.size = Vector2i(new_hpx, new_vpx)

	# _debug_log(required_hfov, required_vfov, Vector2i(new_hpx, new_vpx), ppd)


## Logs sensor FOV, player FOV, and viewport whenever any value changes by > 1°/1px.
func _debug_log(hfov: float, vfov: float, vp: Vector2i, ppd: float) -> void:
	if absf(hfov - _dbg_last_hfov) < 1.0 and absf(vfov - _dbg_last_vfov) < 1.0 \
			and vp == _dbg_last_viewport:
		return
	_dbg_last_hfov     = hfov
	_dbg_last_vfov     = vfov
	_dbg_last_viewport = vp
	var player_fov := viewer_camera.fov if viewer_camera != null else 0.0
	var aspect     := float(vp.x) / float(vp.y) if vp.y > 0 else 0.0
	print("[SensorHead] sensor H=%.1f° V=%.1f°  player_fov=%.1f°  viewport=%dx%d (%.2f)  ppd=%.1f" \
		% [hfov, vfov, player_fov, vp.x, vp.y, aspect, ppd])


## Fallback: simple viewer-direction tracking with a wide static FOV margin.
## Used when panoramic_screen is not wired (e.g. during early setup or testing).
func _update_camera_fallback() -> void:
	var viewer_basis := viewer_camera.global_transform.basis
	var world_look   := -viewer_basis.z
	var viewer_up    := viewer_basis.y
	var up := viewer_up if abs(world_look.dot(viewer_up)) < 0.99 else viewer_basis.x
	_camera.transform = Transform3D(Basis.looking_at(world_look, up), global_position)
	var vfov := clampf(viewer_camera.fov + 90.0, 10.0, 160.0)
	_camera.fov = vfov
	var display_size := viewer_camera.get_viewport().get_visible_rect().size
	var ppd          := (display_size.y / viewer_camera.fov) * quality_scale
	var vpx := int(clampf(ppd * vfov, float(min_viewport_size), float(max_viewport_size)))
	var hpx := int(clampf(float(vpx) * (display_size.x / display_size.y),
			float(min_viewport_size), float(max_viewport_size)))
	_viewport.size = Vector2i(hpx, vpx)


## Returns the nearest positive ray parameter t where (ray_origin + t*ray_dir) hits the sphere.
## Returns -1.0 if the ray misses or all intersections are behind the ray origin.
## Uses half-b form (a=1 for unit ray): disc = b²-c where b=d·dir, c=|d|²-r².
func _ray_sphere_intersect(
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


# --- Sensor data accessors (called by PanoramicScreen each frame) ---

func get_viewport_texture() -> ViewportTexture:
	return _viewport.get_texture()


func get_view_proj() -> Projection:
	# Use _camera.transform (local) — consistent with what the SubViewport renderer
	# actually uses as the camera's world-space transform.
	var view_matrix := _camera.transform.affine_inverse()
	return _camera.get_camera_projection() * Projection(view_matrix)


func get_world_pos() -> Vector3:
	# Local origin == world position because SubViewport has no spatial transform.
	return _camera.transform.origin


func get_sensor_basis() -> Basis:
	# Return the SensorHead's OWN fixed orientation, not the camera's tracking rotation.
	# This defines the panoramic coordinate system: which world direction azimuth=0 maps to.
	# If the camera's rotating basis were used here, it would cancel with the view matrix
	# inverse and the screen content would never change.
	return global_transform.basis


# --- Occlusion group toggle interface ---

## Adds or removes a layer bit from the sensor camera's cull mask.
## Use with Layers.SENSOR_BODY_PARTS, Layers.SENSOR_WEAPONS, Layers.SENSOR_SHIELDS.
## Does not affect the third-person or first-person camera masks.
func set_group_visible(layer_bit: int, visible: bool) -> void:
	if visible:
		_camera.cull_mask |= layer_bit
	else:
		_camera.cull_mask &= ~layer_bit
