@tool
class_name PanoramicScreen
extends Node3D

## Panoramic cockpit display screen.
## Generates a spherical ArrayMesh with panoramic UV2 coordinates baked in,
## then each frame projects those directions through the SensorHead's camera
## to create the illusion of a full 360° display from a single sensor camera.

const _SHADER := preload("res://Common/PanoramicDisplay/panoramic_screen.gdshader")

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

var _material: ShaderMaterial
var _mask_image: Image
var _mask_texture: ImageTexture

@onready var _mesh_instance: MeshInstance3D = $ScreenMesh


func _ready() -> void:
	_mesh_instance.mesh = _build_mesh()

	if Engine.is_editor_hint():
		# Show a semi-transparent placeholder so the cylinder is visible and
		# positionable in the editor without needing a live sensor connection.
		var preview_mat := StandardMaterial3D.new()
		preview_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.35)
		preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		preview_mat.cull_mode = BaseMaterial3D.CULL_BACK
		preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh_instance.material_override = preview_mat
		return

	_setup_material()
	# Visible to the first-person cockpit camera AND to outside cameras when
	# the cockpit door is open. Excluded from the sensor mask so the screen
	# can never appear recursively on its own display.
	_mesh_instance.layers = Layers.COCKPIT | Layers.VEHICLE_EXT


func _process(_delta: float) -> void:
	if sensor_head == null:
		return
	_push_shader_uniforms()


# --- Private ---

func _rebuild_in_editor() -> void:
	# Called by export setters so the preview updates live when you tweak
	# arc_angle, screen_radius, etc. in the Inspector.
	if not Engine.is_editor_hint() or _mesh_instance == null:
		return
	_mesh_instance.mesh = _build_mesh()


func _setup_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _SHADER

	# Initialise the segment mask as fully enabled (all white).
	_mask_image = Image.create(segment_count, 1, false, Image.FORMAT_R8)
	_mask_image.fill(Color.WHITE)
	_mask_texture = ImageTexture.create_from_image(_mask_image)

	_material.set_shader_parameter("segment_mask", _mask_texture)
	_material.set_shader_parameter("panoramic_elevation_range", elevation_range)
	_mesh_instance.material_override = _material


func _push_shader_uniforms() -> void:
	_material.set_shader_parameter("sensor_viewport",  sensor_head.get_viewport_texture())
	_material.set_shader_parameter("sensor_view_proj", sensor_head.get_view_proj())
	_material.set_shader_parameter("sensor_world_pos", sensor_head.get_world_pos())
	_material.set_shader_parameter("sensor_basis",     sensor_head.get_sensor_basis())


func _build_mesh() -> ArrayMesh:
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()   # UV0: standard wrap for optional overlays
	var uv2s    := PackedVector2Array()   # UV2: panoramic direction (azimuth, elevation)
	var indices := PackedInt32Array()

	for row in range(elevation_segments + 1):
		var t_elev: float = float(row) / float(elevation_segments)
		var elevation: float = (t_elev - 0.5) * elevation_range

		for col in range(arc_segments + 1):
			var t_arc: float = float(col) / float(arc_segments)
			var azimuth: float = arc_offset + t_arc * arc_angle
			var cos_el: float = cos(elevation)

			verts.append(Vector3(
				screen_radius * sin(azimuth) * cos_el,
				screen_radius * sin(elevation),
				-screen_radius * cos(azimuth) * cos_el  # -Z is forward in Godot
			))

			# Inward-facing normals so the screen surface faces the pilot.
			normals.append(Vector3(
				-sin(azimuth) * cos_el,
				-sin(elevation),
				cos(azimuth) * cos_el
			))

			# UV0: standard spherical wrap.
			uvs.append(Vector2(t_arc, 1.0 - t_elev))

			# UV2: panoramic direction encoded as (azimuth/TAU, elevation_normalised).
			# azimuth/TAU may be outside [0,1] if arc_offset != 0; the shader uses
			# fract() when sampling the segment mask, and sin/cos are periodic so
			# the direction maths is always correct.
			uv2s.append(Vector2(azimuth / TAU, t_elev))

	# Build quad indices as two triangles each.
	for row in range(elevation_segments):
		for col in range(arc_segments):
			var i: int = row * (arc_segments + 1) + col
			indices.append(i)
			indices.append(i + arc_segments + 1)
			indices.append(i + 1)
			indices.append(i + 1)
			indices.append(i + arc_segments + 1)
			indices.append(i + arc_segments + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]    = verts
	arrays[Mesh.ARRAY_NORMAL]    = normals
	arrays[Mesh.ARRAY_TEX_UV]    = uvs
	arrays[Mesh.ARRAY_TEX_UV2]   = uv2s
	arrays[Mesh.ARRAY_INDEX]     = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
