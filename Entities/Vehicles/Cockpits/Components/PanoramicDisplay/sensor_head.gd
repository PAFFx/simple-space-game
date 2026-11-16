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

@export_group("Overlay")
## Seconds the suit's own overlay (its outlines, or its body) takes to resolve in from blue
## blocks, and to break up and go.
@export var overlay_in_time: float = 0.5
@export var overlay_out_time: float = 0.3

@export_group("Zoom window")
## The zoom window's half size on the screen, deg (4:3, like its image), and its image.
@export var zoom_half_deg: float = 7.0
@export var zoom_size := Vector2i(640, 480)
## Seconds it takes to resolve in from blocks (opening, or a new level), and to go.
@export var zoom_in_time: float = 0.35
@export var zoom_out_time: float = 0.15

## 0 = overlay gone, 1 = fully resolved (PanoramicScreen composites with it).
var overlay_reveal := 0.0
## Zoom window: 0 = closed, 1 = fully resolved.
var zoom_reveal := 0.0
## Where the zoom window looks, world direction from the head, and its frame (right, up).
var zoom_direction := Vector3.FORWARD
var zoom_basis := Basis.IDENTITY
## The magnification shown (kept while the window breaks up).
var zoom_magnification := 0.0

var _viewport: SubViewport
var _camera: Camera3D
# The suit's own overlay: drawn by a second camera on its own transparent image, so the
# screen can pixelate it in and out without touching the outside view.
var _overlay_viewport: SubViewport
var _overlay_camera: Camera3D
var _overlay_layers := 0
var _overlay_target := 0

# The zoom window: a narrow camera on the same head, rendering only while it is open.
var _zoom_viewport: SubViewport
var _zoom_camera: Camera3D
var _zoom_wanted := 0.0
var _zoom_point := Vector3.ZERO

var _dbg_last_vfov: float = 0.0
var _dbg_last_hfov: float = 0.0
var _dbg_last_viewport: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_auto_discover()
	_create_viewport()
	_create_camera()
	_create_overlay()
	_create_zoom()


func _process(_delta: float) -> void:
	var viewer := get_active_viewer()
	if viewer == null:
		return
	if panoramic_screen == null:
		_update_camera_fallback(viewer)
	else:
		_update_camera(viewer)
	_update_overlay(_delta)
	_update_zoom(_delta)


## Shows these layers (Layers.SENSOR_COMBAT, SENSOR_BODY_PARTS; 0 = none) as the suit's own
## overlay. A change breaks the old one up first, then resolves the new one in.
func set_overlay(layers: int) -> void:
	_overlay_target = layers


func get_overlay_texture() -> ViewportTexture:
	return _overlay_viewport.get_texture()


## Opens the zoom window on `world_point` at `magnification` (0 = close it). A new
## magnification resolves in again from blocks.
func set_zoom(world_point: Vector3, magnification: float) -> void:
	if magnification > 0.0 and zoom_magnification > 0.0 and magnification != zoom_magnification:
		zoom_reveal = minf(zoom_reveal, 0.25)
	_zoom_wanted = magnification
	if magnification > 0.0:
		_zoom_point = world_point
		zoom_magnification = magnification


func get_zoom_texture() -> ViewportTexture:
	return _zoom_viewport.get_texture()


## tan of the window's half size across and up.
func get_zoom_half_tan() -> Vector2:
	var t := tan(deg_to_rad(zoom_half_deg))
	return Vector2(t, t * float(zoom_size.y) / float(zoom_size.x))


func get_zoom_viewport() -> SubViewport:
	return _zoom_viewport


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
	# The outside world is drawn here, not in the window: give it the project's
	# anti-aliasing so far suits and thin beams don't break up into crawling pixels.
	_viewport.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", Viewport.MSAA_4X)
	_viewport.screen_space_aa = ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)
	add_child(_viewport)


func _create_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "SensorCamera"
	# Hide the mech body and all equipment from the sensor by default.
	# Use set_group_visible() to selectively re-enable layers once individual
	# body parts have been assigned their own sensor sub-layers.
	_camera.cull_mask = Layers.WORLD | Layers.FX
	_camera.near = 0.5
	# Placed every frame from interpolated transforms; never interpolate it again.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Far enough to see a beam fight: targets and bolts out to a few kilometres.
	_camera.far = 20000.0
	_viewport.add_child(_camera)


func _create_overlay() -> void:
	_overlay_viewport = SubViewport.new()
	_overlay_viewport.name = "OverlayViewport"
	_overlay_viewport.size = _viewport.size
	_overlay_viewport.own_world_3d = false
	_overlay_viewport.transparent_bg = true
	_overlay_viewport.msaa_3d = _viewport.msaa_3d
	_overlay_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_overlay_viewport)
	_overlay_camera = Camera3D.new()
	_overlay_camera.name = "OverlayCamera"
	_overlay_camera.cull_mask = 0
	_overlay_camera.near = _camera.near
	_overlay_camera.far = 200.0
	_overlay_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_overlay_viewport.add_child(_overlay_camera)
	# The scene's look (tonemapping, ambient) but no sky behind: only the overlay is drawn.
	var world_env := _camera.get_world_3d().environment if _camera.get_world_3d() != null else null
	var env := world_env.duplicate() as Environment if world_env != null else Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	_overlay_camera.environment = env


func _create_zoom() -> void:
	_zoom_viewport = SubViewport.new()
	_zoom_viewport.name = "ZoomViewport"
	_zoom_viewport.size = zoom_size
	_zoom_viewport.own_world_3d = false
	_zoom_viewport.msaa_3d = _viewport.msaa_3d
	_zoom_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_zoom_viewport)
	_zoom_camera = Camera3D.new()
	_zoom_camera.name = "ZoomCamera"
	_zoom_camera.near = _camera.near
	_zoom_camera.far = _camera.far
	_zoom_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_zoom_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_zoom_viewport.add_child(_zoom_camera)


func _update_zoom(delta: float) -> void:
	if _zoom_wanted > 0.0:
		zoom_reveal = move_toward(zoom_reveal, 1.0, delta / maxf(zoom_in_time, 0.01))
	else:
		zoom_reveal = move_toward(zoom_reveal, 0.0, delta / maxf(zoom_out_time, 0.01))
		if zoom_reveal <= 0.0:
			zoom_magnification = 0.0
	var drawing := zoom_reveal > 0.0 and _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED
	_zoom_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if drawing else SubViewport.UPDATE_DISABLED
	if not drawing:
		return
	var origin := get_global_transform_interpolated().origin
	var to := _zoom_point - origin
	if to.length_squared() > 1.0:
		zoom_direction = to.normalized()
	# The window stands upright on the screen: its up is the display's.
	var up := panoramic_screen.get_display_basis().y if panoramic_screen != null else Vector3.UP
	if absf(zoom_direction.dot(up.normalized())) > 0.99:
		up = panoramic_screen.get_display_basis().z if panoramic_screen != null else Vector3.BACK
	zoom_basis = Basis.looking_at(zoom_direction, up)
	_zoom_camera.transform = Transform3D(zoom_basis, origin)
	_zoom_camera.cull_mask = _camera.cull_mask
	# A frustum, not a fov: past ×10 the view is narrower than a Camera3D fov may be (1°).
	_zoom_camera.size = 2.0 * _zoom_camera.near * get_zoom_half_tan().y / maxf(zoom_magnification, 1.0)
	if _zoom_viewport.size != zoom_size:
		_zoom_viewport.size = zoom_size


func _update_overlay(delta: float) -> void:
	if _overlay_layers != _overlay_target:
		# Break the old one up first (nothing to break up: switch at once).
		overlay_reveal = move_toward(overlay_reveal, 0.0, delta / maxf(overlay_out_time, 0.01))
		if overlay_reveal <= 0.0:
			_overlay_layers = _overlay_target
			_overlay_camera.cull_mask = _overlay_layers
	elif _overlay_layers != 0:
		overlay_reveal = move_toward(overlay_reveal, 1.0, delta / maxf(overlay_in_time, 0.01))
	var drawing := overlay_reveal > 0.0 or _overlay_layers != 0
	drawing = drawing and _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED
	_overlay_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if drawing else SubViewport.UPDATE_DISABLED
	if drawing:
		_overlay_camera.transform = _camera.transform
		_overlay_camera.fov = _camera.fov
		if _overlay_viewport.size != _viewport.size:
			_overlay_viewport.size = _viewport.size


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
	var origin := get_global_transform_interpolated().origin
	_camera.transform = Transform3D(Basis.looking_at(look, up), origin)
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
	_camera.transform = Transform3D(Basis.looking_at(world_look, up),
			get_global_transform_interpolated().origin)
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
