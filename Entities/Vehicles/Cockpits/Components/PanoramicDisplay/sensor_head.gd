class_name SensorHead
extends Node3D

## Manages a sensor camera at the mech's head pivot.
## Tracks the viewer camera's look direction and renders only the angular
## slice of the world the viewer is currently looking at, feeding the result
## to PanoramicScreen via a SubViewport texture.
##
## Dependencies (viewer_camera, panoramic_screen) are discovered automatically
## by walking up to the nearest VehicleBase ancestor. Set the exports manually
## only when testing outside a full vehicle hierarchy.

## Optional override — auto-discovered from the vehicle's cockpit if left empty.
@export var viewer_camera: Camera3D

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
	if viewer_camera == null:
		return
	_update_camera()


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


func _update_camera() -> void:
	if panoramic_screen == null:
		_update_camera_fallback()
		return

	var viewer_basis := viewer_camera.global_transform.basis
	var world_look   := -viewer_basis.z
	var viewer_up    := viewer_basis.y
	var up := viewer_up if abs(world_look.dot(viewer_up)) < 0.99 else viewer_basis.x

	# Sensor camera is always aimed in the viewer's look direction.
	# SubViewport has no spatial transform — _camera.transform IS world-space.
	_camera.transform = Transform3D(Basis.looking_at(world_look, up), global_position)

	# Decompose the sensor camera's local axes for per-axis FOV computation.
	var cam_basis := _camera.transform.basis

	var fov_result := SensorFovSolver.solve_required_fov(
		viewer_camera,
		panoramic_screen.global_position,
		panoramic_screen.screen_radius,
		global_position,
		world_look,
		cam_basis.x,  # cam_right
		cam_basis.y,  # cam_up
		fov_safety_margin_degrees
	)

	if fov_result.x < 0.0:
		# No frustum ray hit the sphere — park at narrow FOV.
		_camera.fov = 10.0
		return

	# Camera3D.fov is vertical FOV (keep_aspect = KEEP_HEIGHT default).
	_camera.fov = fov_result.y

	var new_size := SensorFovSolver.compute_viewport_size(
		viewer_camera, quality_scale,
		fov_result.y, fov_result.x,
		min_viewport_size, max_viewport_size
	)

	# Resize only when either dimension changes by > 10% to avoid per-frame GPU realloc.
	var size_changed := (
		absf(float(new_size.y - _viewport.size.y)) > float(_viewport.size.y) * 0.1 or
		absf(float(new_size.x - _viewport.size.x)) > float(_viewport.size.x) * 0.1
	)
	if size_changed:
		_viewport.size = new_size

	# _debug_log(fov_result.x, fov_result.y, new_size)


## Logs sensor FOV, player FOV, and viewport whenever any value changes by > 1°/1px.
func _debug_log(hfov: float, vfov: float, vp: Vector2i) -> void:
	if absf(hfov - _dbg_last_hfov) < 1.0 and absf(vfov - _dbg_last_vfov) < 1.0 \
			and vp == _dbg_last_viewport:
		return
	_dbg_last_hfov     = hfov
	_dbg_last_vfov     = vfov
	_dbg_last_viewport = vp
	var player_fov := viewer_camera.fov if viewer_camera != null else 0.0
	var ppd        := (viewer_camera.get_viewport().get_visible_rect().size.y / player_fov) \
			* quality_scale if viewer_camera != null else 0.0
	var aspect     := float(vp.x) / float(vp.y) if vp.y > 0 else 0.0
	print("[SensorHead] sensor H=%.1f° V=%.1f°  player_fov=%.1f°  viewport=%dx%d (%.2f)  ppd=%.1f" \
		% [hfov, vfov, player_fov, vp.x, vp.y, aspect, ppd])


## Fallback when panoramic_screen is not available (e.g. standalone testing).
## Uses a wide static FOV margin to ensure the display stays covered.
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
