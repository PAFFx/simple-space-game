class_name SensorOutline
extends Node3D

## Shows equipment on the panoramic screen as an outline: the real meshes are drawn
## into the sensor image, but only their rim, so the outline is the model's true
## silhouette from the sensor head, at any angle and distance, and the view through it
## stays clear. Only the sensor camera sees it (a sensor sub-layer).
##
## Each unit (every mesh under the parent, or all of them as one) is drawn in steps: its
## body writes a stencil value and depth but no colour, then the same mesh pushed out
## along its normals by a few pixels is drawn where that value isn't (a dark halo first,
## then the rim). Units go one after another, so overlapping units (stowed fin funnels)
## each keep a whole outline.
##
## A silhouette alone reads badly for a big plate seen at a slant from close by (a shield
## beside the head), so the unit's creases are drawn too, finer and dimmer, hidden where
## its own body covers them: the outline then reads as the object in perspective.

## One outline per mesh instead of one round them all.
@export var per_mesh: bool = false
@export var color := Color(0.74, 0.7, 0.86, 0.85)
## Rim width in sensor pixels (about screen pixels at SensorHead.quality_scale 1).
@export var width_px: float = 2.5
## Dark edge round the rim, so it reads over a bright background. Alpha 0 = none.
@export var halo_color := Color(0.0, 0.0, 0.0, 0.5)
@export var halo_px: float = 1.5
## Edges sharper than this (and open edges) are drawn as creases, deg. 0 = none.
@export var crease_deg: float = 38.0
@export var crease_px: float = 1.4
@export_range(0.0, 1.0) var crease_alpha: float = 0.55
## Sensor sub-layer the outline is drawn on (Layers.SENSOR_WEAPONS / SENSOR_SHIELDS /
## SENSOR_COMBAT).
@export_flags_3d_render var sensor_layer: int = 1 << 8
## Outline only the meshes with these names (empty = every mesh under the parent).
@export var only_meshes: Array[StringName] = []
## Leave showing the layer to FireControl (SENSOR_COMBAT: only in a weapons mode) instead
## of turning it on once built.
@export var shown_by_fire_control: bool = false

const _SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, %s, shadows_disabled, fog_disabled;
stencil_mode %s, %d;
uniform vec4 color : source_color;
uniform float width_px;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// The rim: out along the normal as seen on screen, a fixed number of pixels.
	vec4 n = PROJECTION_MATRIX * vec4(MODELVIEW_NORMAL_MATRIX * NORMAL, 0.0);
	float len = length(n.xy);
	if (len > 1e-6) {
		clip.xy += n.xy / len * (width_px * 2.0 / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""

# Creases: every edge is a quad, each vertex carrying the edge's other end (UV, UV2.x)
# and its side (UV2.y), widened on screen. Pulled a touch toward the eye so edges lying
# on the body pass its depth and edges behind it don't.
const _CREASE_SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color;
uniform float width_px;

void vertex() {
	vec4 here = PROJECTION_MATRIX * vec4((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * 0.996, 1.0);
	vec4 there = PROJECTION_MATRIX * vec4((MODELVIEW_MATRIX * vec4(UV, UV2.x, 1.0)).xyz * 0.996, 1.0);
	if (there.w < 0.01 && here.w > 0.01) {
		there = mix(here, there, (here.w - 0.01) / (here.w - there.w));   // other end behind the eye
	}
	vec2 along = (there.xy / max(there.w, 0.01) - here.xy / max(here.w, 0.01)) * VIEWPORT_SIZE;
	float len = length(along);
	if (len > 1e-6) {
		vec2 across = vec2(-along.y, along.x) / len;
		here.xy += across * UV2.y * (width_px / VIEWPORT_SIZE) * here.w;
	}
	POSITION = here;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""

# Units are drawn in the order they were made (three render priorities each); the stencil
# value only has to differ from the units drawn before.
static var _units := 0


func _ready() -> void:
	# After the equipment's own _ready, which puts every mesh under it on the suit's layer.
	_build.call_deferred()


func _build() -> void:
	var meshes := get_parent().find_children("*", "MeshInstance3D", true, false)
	if not only_meshes.is_empty():
		meshes = meshes.filter(func(m: Node) -> bool: return m.name in only_meshes)
	if meshes.is_empty():
		push_warning("SensorOutline: no meshes under " + String(get_parent().name))
		return
	var unit := _next_unit()
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			continue
		if per_mesh:
			unit = _next_unit()
		_add_outline(mesh, unit)
	var vehicle := VehicleBase.find_vehicle(self)
	var sensor := vehicle.get_sensor_head() if vehicle != null else null
	if sensor != null and not shown_by_fire_control:
		sensor.set_group_visible(sensor_layer, true)


static func _next_unit() -> int:
	_units += 1
	return _units


func _add_outline(source: MeshInstance3D, unit: int) -> void:
	var shell := _smooth_shell(source.mesh)
	var reference := 1 + (unit - 1) % 255
	var priority := clampi(-120 + ((unit - 1) % 80) * 3, -128, 125)
	# [depth modes, stencil mode, colour, width]: the body at its true size and fully
	# transparent (stencil and depth only), then the halo and the rim outside it.
	var steps := [
		# (Stencil is written behind nearer units too, or the rim would fill in there.)
		["depth_draw_always", "write, write_depth_fail, compare_always", Color(color, 0.0), 0.0],
		["depth_test_disabled, depth_draw_never", "read, compare_not_equal", halo_color, width_px + halo_px],
		["depth_test_disabled, depth_draw_never", "read, compare_not_equal", color, width_px],
	]
	# Creases carry their other end unskinned: only for rigid meshes.
	if crease_deg > 0.0 and source.skin == null:
		var creases := _crease_mesh(source.mesh, crease_deg)
		if creases != null:
			var crease_shader := Shader.new()
			crease_shader.code = _CREASE_SHADER
			var crease_mat := ShaderMaterial.new()
			crease_mat.shader = crease_shader
			crease_mat.render_priority = priority + 2
			crease_mat.set_shader_parameter(&"color", Color(color, color.a * crease_alpha))
			crease_mat.set_shader_parameter(&"width_px", crease_px)
			_add_instance(source, "SensorCreases", creases, crease_mat)
	for step in steps.size():
		if step == 1 and halo_color.a <= 0.0:
			continue
		var shader := Shader.new()
		shader.code = _SHADER % [steps[step][0], steps[step][1], reference]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = priority + step
		mat.set_shader_parameter(&"color", steps[step][2])
		mat.set_shader_parameter(&"width_px", steps[step][3])
		_add_instance(source, "SensorOutline%d" % step, shell, mat)


func _add_instance(source: MeshInstance3D, instance_name: String, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = instance_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = sensor_layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1.0
	source.add_child(mi)
	if source.skin != null:
		# Deforms with the same skeleton as its source (the suit's arms).
		mi.skin = source.skin
		mi.skeleton = mi.get_path_to(source.get_node(source.skeleton))


## The mesh's surfaces as one, its normals averaged over every vertex sharing a place, so
## pushing it out along them keeps hard edges closed.
static func _smooth_shell(mesh: Mesh) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	# Skinned: keep the bone weights so the shell deforms with the mesh.
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var skinned := mesh.get_surface_count() > 0
	var flags := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		skinned = skinned and arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null
		if skinned:
			bones.append_array(arrays[Mesh.ARRAY_BONES])
			weights.append_array(arrays[Mesh.ARRAY_WEIGHTS])
			flags = (mesh as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if mesh is ArrayMesh else 0
		var surface_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(surface_verts)
		var surface_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if surface_indices == null:
			for i in surface_verts.size():
				indices.append(base + i)
		else:
			for i: int in surface_indices:
				indices.append(base + i)
	# Area-weighted face normals summed per place.
	var sums := {}
	for t in range(0, indices.size() - 2, 3):
		var a := verts[indices[t]]
		var b := verts[indices[t + 1]]
		var c := verts[indices[t + 2]]
		var n := (c - a).cross(b - a)   # Godot winds front faces clockwise
		for p: Vector3 in [a, b, c]:
			var key := p.snappedf(1e-4)
			sums[key] = (sums.get(key, Vector3.ZERO) as Vector3) + n
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = sums.get(verts[i].snappedf(1e-4), Vector3.UP)
		normals[i] = n.normalized() if n.length_squared() > 1e-16 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var shell := ArrayMesh.new()
	shell.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return shell


## The mesh's sharp and open edges as screen-widened quads (see _CREASE_SHADER), or null
## if it has none. Edges are matched by place, so split vertices along a hard edge count
## as one edge between two faces.
static func _crease_mesh(mesh: Mesh, sharp_deg: float) -> ArrayMesh:
	var edges := {}   # [place a, place b] sorted → [a, b, first face normal, face count, sharp]
	var cos_sharp := cos(deg_to_rad(sharp_deg))
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var surface_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = surface_verts.size() if surface_indices == null else (surface_indices as PackedInt32Array).size()
		for t in range(0, count - 2, 3):
			var tri: Array[Vector3] = []
			for k in 3:
				tri.append(surface_verts[t + k if surface_indices == null else surface_indices[t + k]])
			var n := (tri[2] - tri[0]).cross(tri[1] - tri[0])
			if n.length_squared() < 1e-16:
				continue
			n = n.normalized()
			for k in 3:
				var a := tri[k].snappedf(1e-4)
				var b := tri[(k + 1) % 3].snappedf(1e-4)
				var key := [a, b] if a < b else [b, a]
				if not edges.has(key):
					edges[key] = [tri[k], tri[(k + 1) % 3], n, 1, false]
				else:
					var edge: Array = edges[key]
					edge[3] += 1
					edge[4] = edge[4] or (edge[2] as Vector3).dot(n) < cos_sharp
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for edge: Array in edges.values():
		if edge[3] != 1 and not edge[4]:
			continue
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		var base := verts.size()
		# Sides are mirrored at the far end, where "along the edge" points back.
		for corner in [[a, b, 1.0], [a, b, -1.0], [b, a, -1.0], [b, a, 1.0]]:
			verts.append(corner[0])
			uvs.append(Vector2(corner[1].x, corner[1].y))
			uv2s.append(Vector2(corner[1].z, corner[2]))
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	if verts.is_empty():
		return null
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_TEX_UV2] = uv2s
	out[Mesh.ARRAY_INDEX] = indices
	var creases := ArrayMesh.new()
	creases.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return creases
