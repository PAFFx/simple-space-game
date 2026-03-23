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

## Target render quality in pixels per degree of sensor FOV.
## 12 px/deg → ~1080px at 90° FOV; 16 px/deg → ~1440px.
@export var pixels_per_degree: float = 32.0

## Safety margin added on top of the geometry-computed FOV.
## Covers 1-frame rotation lag and floating-point precision at sphere edges.
@export var fov_safety_margin_degrees: float = 8.0

@export var min_viewport_size: int = 256
@export var max_viewport_size: int = 4096

var _viewport: SubViewport
var _camera: Camera3D


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
	_camera.far = 10000.0
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
	# The shader samples world_dir = sensor_basis * local_dir(UV2), and those directions
	# are centred around the viewer's forward, so the sensor must face the same way.
	# SubViewport has no spatial transform — _camera.transform IS world-space.
	var world_look := -viewer_basis.z
	var viewer_up  := viewer_basis.y
	var up := viewer_up if abs(world_look.dot(viewer_up)) < 0.99 else viewer_basis.x
	_camera.transform = Transform3D(Basis.looking_at(world_look, up), sensor_pos)

	# Cast the viewer's frustum corner rays through the screen sphere.
	# For each hit, the panoramic direction the shader will sample is the direction
	# FROM sphere centre TO the hit point (= sensor_basis * local_dir for that fragment).
	# The angle of that direction from world_look gives how far the sensor FOV must reach.
	var vp_size := viewer_camera.get_viewport().get_visible_rect().size
	var sample_pixels: Array[Vector2] = [
		vp_size * 0.5,
		Vector2(0.0, 0.0),
		Vector2(vp_size.x, 0.0),
		Vector2(0.0, vp_size.y),
		vp_size,
	]

	var max_half_angle := 0.0
	var any_hit        := false

	for idx in range(sample_pixels.size()):
		var ray_dir := viewer_camera.project_ray_normal(sample_pixels[idx])
		var t := _ray_sphere_intersect(viewer_pos, ray_dir, sphere_center, sphere_radius)
		if t < 0.0:
			continue
		any_hit = true
		var hit           := viewer_pos + ray_dir * t
		var panoramic_dir := (hit - sphere_center).normalized()
		var angle         := acos(clampf(panoramic_dir.dot(world_look), -1.0, 1.0))
		if angle > max_half_angle:
			max_half_angle = angle

	if not any_hit:
		# Viewer not looking at screen — camera is already placed, keep minimal FOV.
		_camera.fov = 10.0
		return

	var required_fov := clampf(
		rad_to_deg(max_half_angle) * 2.0 + fov_safety_margin_degrees,
		10.0, 160.0
	)
	_camera.fov = required_fov

	# Scale viewport resolution to maintain pixels_per_degree quality target.
	# Only resize when the change exceeds 10% to avoid per-frame texture reallocation.
	var new_size := int(clampf(pixels_per_degree * required_fov,
			float(min_viewport_size), float(max_viewport_size)))
	if absf(float(new_size - _viewport.size.x)) > float(_viewport.size.x) * 0.1:
		_viewport.size = Vector2i(new_size, new_size)


## Fallback: simple viewer-direction tracking with a wide static FOV margin.
## Used when panoramic_screen is not wired (e.g. during early setup or testing).
func _update_camera_fallback() -> void:
	var viewer_basis := viewer_camera.global_transform.basis
	var world_look   := -viewer_basis.z
	var viewer_up    := viewer_basis.y
	var up := viewer_up if abs(world_look.dot(viewer_up)) < 0.99 else viewer_basis.x
	_camera.transform = Transform3D(Basis.looking_at(world_look, up), global_position)
	_camera.fov = clampf(viewer_camera.fov + 90.0, 10.0, 160.0)


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
