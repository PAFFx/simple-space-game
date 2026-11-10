class_name SensorHead
extends Node3D

## Manages a sensor camera at the mech's head pivot.
## Renders only the angular slice of the world covering the part of the screen
## the active camera can currently see (from the seat or through the hatch), feeding the result
## to PanoramicScreen via a SubViewport texture.
##
## Dependencies (viewer_camera, panoramic_screen) are discovered automatically
## by walking up to the nearest VehicleBase ancestor. Set the exports manually
## only when testing outside a full vehicle hierarchy.

## Default viewer (the pilot's camera). Auto-discovered from the vehicle's cockpit if left empty.
@export var viewer_camera: Camera3D

## Render for whichever camera is currently active, so the screen also looks
## right from external cameras. Off = always render for viewer_camera.
@export var follow_active_camera: bool = true

## Optional override — auto-discovered from the vehicle's cockpit if left empty.
@export var panoramic_screen: PanoramicScreen

## Render quality relative to the player's display resolution.
## 1.0 = sensor renders at exactly display resolution (1:1 pixel ratio on screen).
## 2.0 = 2× super-sampled. 0.5 = half-resolution (cheaper, blurrier).
@export var quality_scale: float = 1.0

## Safety margin added on top of the geometry-computed FOV.
## Covers 1-frame rotation lag and floating-point precision at sphere edges.
@export var fov_safety_margin_degrees: float = 8.0

@export var min_viewport_size: int = 256
@export var max_viewport_size: int = 4096

var _viewport: SubViewport
var _camera: Camera3D

var _dbg_last_vfov: float = 0.0
var _dbg_last_hfov: float = 0.0
var _dbg_last_viewport: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_auto_discover()
	_create_viewport()
	_create_camera()


func _process(_delta: float) -> void:
	var viewer := get_active_viewer()
	if viewer == null:
		return
	if panoramic_screen == null:
		_update_camera_fallback(viewer)
	else:
		_update_camera(viewer)


## The camera the screen is rendered for: whatever camera is currently showing
## the main viewport (cockpit, external, cinematic...), else viewer_camera.
func get_active_viewer() -> Camera3D:
	if follow_active_camera:
		var active := get_viewport().get_camera_3d()
		if active != null:
			return active
	return viewer_camera


# --- Auto-discovery ---

func _auto_discover() -> void:
	if viewer_camera != null and panoramic_screen != null:
		return  # Both provided as manual overrides — skip discovery.
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle == null:
		push_error("SensorHead: no VehicleBase found in parent chain")
		return
	var cockpit := vehicle.get_cockpit()
	if cockpit == null:
		push_error("SensorHead: no CockpitBase found in vehicle")
		return
	if viewer_camera == null:
		viewer_camera = cockpit.get_player_camera()
	if panoramic_screen == null:
		panoramic_screen = cockpit.get_panoramic_screen()


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


func _update_camera(viewer: Camera3D) -> void:
	# Same mapping as the shader: screen-local direction → world through the display basis.
	var screen_to_world := panoramic_screen.get_display_basis()
	var dirs := SensorFovSolver.sample_visible_directions(viewer, panoramic_screen)
	for i in dirs.size():
		dirs[i] = screen_to_world * dirs[i]

	# Nothing on the screen is visible (e.g. outside with the hatch shut): skip rendering.
	_set_rendering(not dirs.is_empty())
	if dirs.is_empty():
		return

	var look := SensorFovSolver.aim_direction(dirs)
	if look.is_zero_approx():
		look = -viewer.global_basis.z
	var viewer_up := viewer.global_basis.y
	var up := viewer_up if absf(look.dot(viewer_up)) < 0.99 else viewer.global_basis.x

	# SubViewport has no spatial transform — _camera.transform IS world-space.
	_camera.transform = Transform3D(Basis.looking_at(look, up), global_position)
	var cam_basis := _camera.transform.basis
	var fov := SensorFovSolver.solve_required_fov(
		dirs, look, cam_basis.x, cam_basis.y, fov_safety_margin_degrees)

	# Camera3D.fov is vertical FOV (keep_aspect = KEEP_HEIGHT default).
	_camera.fov = fov.y

	var new_size := SensorFovSolver.compute_viewport_size(
		viewer, quality_scale, fov.y, fov.x, min_viewport_size, max_viewport_size)

	# Resize only when either dimension changes by > 10% to avoid per-frame GPU realloc.
	var size_changed := (
		absf(float(new_size.y - _viewport.size.y)) > float(_viewport.size.y) * 0.1 or
		absf(float(new_size.x - _viewport.size.x)) > float(_viewport.size.x) * 0.1
	)
	if size_changed:
		_viewport.size = new_size

	# _debug_log(viewer, fov.x, fov.y, new_size)


func _set_rendering(enabled: bool) -> void:
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED)


## Logs sensor FOV, player FOV, and viewport whenever any value changes by > 1°/1px.
func _debug_log(viewer: Camera3D, hfov: float, vfov: float, vp: Vector2i) -> void:
	if absf(hfov - _dbg_last_hfov) < 1.0 and absf(vfov - _dbg_last_vfov) < 1.0 \
			and vp == _dbg_last_viewport:
		return
	_dbg_last_hfov     = hfov
	_dbg_last_vfov     = vfov
	_dbg_last_viewport = vp
	var player_fov := viewer.fov if viewer != null else 0.0
	var ppd        := (viewer.get_viewport().get_visible_rect().size.y / player_fov) \
			* quality_scale if viewer != null else 0.0
	var aspect     := float(vp.x) / float(vp.y) if vp.y > 0 else 0.0
	print("[SensorHead] sensor H=%.1f° V=%.1f°  player_fov=%.1f°  viewport=%dx%d (%.2f)  ppd=%.1f" \
		% [hfov, vfov, player_fov, vp.x, vp.y, aspect, ppd])


## Fallback when panoramic_screen is not available (e.g. standalone testing).
## Uses a wide static FOV margin to ensure the display stays covered.
func _update_camera_fallback(viewer: Camera3D) -> void:
	var viewer_basis := viewer.global_transform.basis
	var world_look   := -viewer_basis.z
	var viewer_up    := viewer_basis.y
	var up := viewer_up if abs(world_look.dot(viewer_up)) < 0.99 else viewer_basis.x
	_camera.transform = Transform3D(Basis.looking_at(world_look, up), global_position)
	var vfov := clampf(viewer.fov + 90.0, 10.0, 160.0)
	_camera.fov = vfov
	var display_size := viewer.get_viewport().get_visible_rect().size
	var ppd          := (display_size.y / viewer.fov) * quality_scale
	var vpx := int(clampf(ppd * vfov, float(min_viewport_size), float(max_viewport_size)))
	var hpx := int(clampf(float(vpx) * (display_size.x / display_size.y),
			float(min_viewport_size), float(max_viewport_size)))
	_viewport.size = Vector2i(hpx, vpx)


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
