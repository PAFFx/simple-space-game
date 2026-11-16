@tool
class_name PanoramicScreen
extends Node3D

## Panoramic cockpit display screen.
## Generates a spherical ArrayMesh with panoramic UV2 coordinates baked in,
## then each frame projects those directions through the SensorHead's camera
## to create the illusion of a full 360° display from a single sensor camera.
##
## sensor_head is discovered automatically by walking up to the nearest VehicleBase.
## Set the export manually only when testing outside a full vehicle hierarchy.

const _SHADER := preload("res://Entities/Vehicles/Cockpits/Components/PanoramicDisplay/Shader/panoramic_screen.gdshader")

## Optional override — auto-discovered from the vehicle's SensorHead if left empty.
@export var sensor_head: SensorHead

## Total arc angle of the cylindrical screen in radians. TAU = full 360°.
@export var arc_angle: float = TAU:
	set(v): arc_angle = v; _rebuild_in_editor()

## Starting azimuth offset in radians. 0 = screen starts facing -Z (forward).
@export var arc_offset: float = 0.0:
	set(v): arc_offset = v; _rebuild_in_editor()

## Total vertical angle span in radians. PI = ±90° complete horizontal.
@export var elevation_range: float = PI:
	set(v): elevation_range = v; _rebuild_in_editor()

## Radius of the spherical screen in metres.
@export var screen_radius: float = 1.2:
	set(v): screen_radius = v; _rebuild_in_editor()

## Number of arc subdivisions. Higher = smoother curve, more vertices.
@export var arc_segments: int = 128:
	set(v): arc_segments = v; _rebuild_in_editor()

## Number of vertical subdivisions.
@export var elevation_segments: int = 128:
	set(v): elevation_segments = v; _rebuild_in_editor()

## Number of independently togglable arc segments for damage / door masking.
## Each segment spans arc_angle / segment_count radians.
@export var segment_count: int = 64

@export_group("Hatch Aperture")
## Centre of the hatch opening in degrees (x = azimuth, y = elevation). 0,0 = straight ahead.
@export var aperture_center_deg := Vector2.ZERO
## Half extent of the hatch opening in degrees (x = azimuth, y = elevation).
@export var aperture_half_size_deg := Vector2(35.0, 35.0)

var _material: ShaderMaterial
var _hud_texture: Texture2D
var _hud_parameters := {}
var _aperture_amount: float = 0.0
var _mask_image: Image
var _mask_texture: ImageTexture

@onready var _mesh_instance: MeshInstance3D = $ScreenMesh


func _ready() -> void:
	_mesh_instance.mesh = PanoramicMeshBuilder.build(
		arc_angle, arc_offset, elevation_range,
		screen_radius, arc_segments, elevation_segments
	)

	if Engine.is_editor_hint():
		# Show a semi-transparent placeholder so the sphere is visible and
		# positionable in the editor without needing a live sensor connection.
		var preview_mat := StandardMaterial3D.new()
		preview_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.35)
		preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview_mat.cull_mode = BaseMaterial3D.CULL_BACK
		preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh_instance.material_override = preview_mat
		return

	_auto_discover()
	_setup_material()
	# Visible to the first-person cockpit camera AND to outside cameras when
	# the cockpit door is open. Excluded from the sensor mask so the screen
	# can never appear recursively on its own display.
	_mesh_instance.layers = Layers.COCKPIT | Layers.VEHICLE_EXT


func _process(_delta: float) -> void:
	if sensor_head == null:
		return
	_push_shader_uniforms()


# --- Auto-discovery ---

func _auto_discover() -> void:
	if sensor_head != null:
		return  # Manual override provided — skip discovery.
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle == null:
		push_error("PanoramicScreen: no VehicleBase found in parent chain")
		return
	sensor_head = vehicle.get_sensor_head()
	if sensor_head == null:
		push_error("PanoramicScreen: no SensorHead found in vehicle")


# --- Private ---

func _rebuild_in_editor() -> void:
	# Called by export setters so the preview updates live when you tweak
	# arc_angle, screen_radius, etc. in the Inspector.
	if not Engine.is_editor_hint() or _mesh_instance == null:
		return
	_mesh_instance.mesh = PanoramicMeshBuilder.build(
		arc_angle, arc_offset, elevation_range,
		screen_radius, arc_segments, elevation_segments
	)


func _setup_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _SHADER

	# Initialise the segment mask as fully enabled (all white).
	_mask_image = Image.create(segment_count, 1, false, Image.FORMAT_R8)
	_mask_image.fill(Color.WHITE)
	_mask_texture = ImageTexture.create_from_image(_mask_image)

	_material.set_shader_parameter("segment_mask", _mask_texture)
	_material.set_shader_parameter("panoramic_elevation_range", elevation_range)
	_material.set_shader_parameter("aperture_center", _deg_to_rad_v2(aperture_center_deg))
	_material.set_shader_parameter("aperture_half_size", _deg_to_rad_v2(aperture_half_size_deg))
	_material.set_shader_parameter("aperture_amount", _aperture_amount)
	_material.set_shader_parameter("hud_texture", _hud_texture)
	for param: StringName in _hud_parameters:
		_material.set_shader_parameter(param, _hud_parameters[param])
	_mesh_instance.material_override = _material


static func _deg_to_rad_v2(v: Vector2) -> Vector2:
	return Vector2(deg_to_rad(v.x), deg_to_rad(v.y))


func _push_shader_uniforms() -> void:
	_material.set_shader_parameter("sensor_viewport",  sensor_head.get_viewport_texture())
	_material.set_shader_parameter("sensor_view_proj", sensor_head.get_view_proj())
	_material.set_shader_parameter("sensor_world_pos", sensor_head.get_world_pos())
	_material.set_shader_parameter("display_basis",    get_display_basis())
	_material.set_shader_parameter("overlay_viewport", sensor_head.get_overlay_texture())
	_material.set_shader_parameter("overlay_reveal",   sensor_head.overlay_reveal)


## World orientation of the panoramic frame: screen-local direction d shows world direction
## get_display_basis() * d. Follows the cockpit, not the sensor.
func get_display_basis() -> Basis:
	return get_display_transform().basis.orthonormalized()


## Where the screen is actually drawn this frame (interpolated between physics ticks).
func get_display_transform() -> Transform3D:
	return get_global_transform_interpolated()


# --- Segment mask API ---

## Enable or disable a single segment by index (0 = first segment at arc_offset).
func set_segment_enabled(index: int, enabled: bool) -> void:
	if index < 0 or index >= segment_count:
		return
	var value := Color.WHITE if enabled else Color.BLACK
	_mask_image.set_pixel(index, 0, value)
	_mask_texture.update(_mask_image)


## Enable or disable all segments whose centre falls within [start_rad, end_rad].
## Handles wraparound (e.g. start=5.5, end=0.5 radians crosses the 0/TAU boundary).
func set_arc_range_enabled(start_rad: float, end_rad: float, enabled: bool) -> void:
	var start_n := fposmod(start_rad / TAU, 1.0)
	var end_n   := fposmod(end_rad   / TAU, 1.0)
	for i in range(segment_count):
		var centre: float = (float(i) + 0.5) / float(segment_count)
		var in_range: bool
		if start_n <= end_n:
			in_range = centre >= start_n and centre <= end_n
		else:
			# Range wraps around the 0/TAU boundary.
			in_range = centre >= start_n or centre <= end_n
		if in_range:
			set_segment_enabled(i, enabled)


## Enable all segments (fully operational display).
func enable_all_segments() -> void:
	_mask_image.fill(Color.WHITE)
	_mask_texture.update(_mask_image)


## Disable all segments (screen fully off).
func disable_all_segments() -> void:
	_mask_image.fill(Color.BLACK)
	_mask_texture.update(_mask_image)


# --- HUD overlay API ---

## Texture drawn over the sensor image in equirectangular panoramic space
## (see panoramic_screen.gdshader). Pass null to remove the HUD.
func set_hud_texture(texture: Texture2D) -> void:
	_hud_texture = texture
	if _material != null:
		_material.set_shader_parameter("hud_texture", texture)


## A HUD layer texture or uniform (see PanoramicHud/Shader/hud_layers.gdshaderinc).
func set_hud_parameter(param: StringName, value: Variant) -> void:
	_hud_parameters[param] = value
	if _material != null:
		_material.set_shader_parameter(param, value)


# --- Hatch aperture API ---

## 0 = screen closed, 1 = hatch opening fully cut out of the sphere.
func set_aperture_amount(amount: float) -> void:
	_aperture_amount = clampf(amount, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("aperture_amount", _aperture_amount)


func get_aperture_amount() -> float:
	return _aperture_amount


func get_aperture_center_rad() -> Vector2:
	return _deg_to_rad_v2(aperture_center_deg)


func get_aperture_half_size_rad() -> Vector2:
	return _deg_to_rad_v2(aperture_half_size_deg)


## True if a screen-local direction currently falls in the cut-out (same test as the shader).
func is_in_aperture(local_dir: Vector3) -> bool:
	if _aperture_amount <= 0.0:
		return false
	var centre := get_aperture_center_rad()
	var half := get_aperture_half_size_rad()
	var d_az := wrapf(atan2(local_dir.x, -local_dir.z) - centre.x, -PI, PI)
	var d_el := asin(clampf(local_dir.y, -1.0, 1.0)) - centre.y
	return absf(d_az) < half.x and absf(d_el) < half.y * _aperture_amount


## Screen-local unit direction for an azimuth/elevation (azimuth 0 = -Z, positive = +X).
static func angles_to_direction(azimuth: float, elevation: float) -> Vector3:
	var cos_el := cos(elevation)
	return Vector3(sin(azimuth) * cos_el, sin(elevation), -cos(azimuth) * cos_el)
