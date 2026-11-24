class_name HoleSet
extends Node

## Beam holes on meshes (Docs/Damage/beam_effects.md). Each hole is a record in its part's
## space: a bone's for a skinned part, the mesh's own for a rigid one. A mesh keeps its
## original material until its first hole; then each surface gets a copy of the damage
## shader with the original's values, and its records are uploaded every frame (with the
## bone's current pose, so the hole rides the limb).

const SHADER := preload("res://Entities/Vehicles/Components/Damage/Shader/damage_surface.gdshader")
const MAX_HOLES := 16

class Hole:
	var origin := Vector3.ZERO     ## part space
	var axis := Vector3.FORWARD
	var radius := 0.6
	var s_in := 0.0
	var s_out := 1.0
	var s_drill := 0.0
	var time := 0.0
	var peak := 2200.0

class Surface:
	var mesh: MeshInstance3D
	var skeleton: Skeleton3D
	var bone := -1
	var holes: Array[Hole] = []
	var materials: Array[ShaderMaterial] = []
	var body_heat := Vector2(0.0, -1000.0)

var now := 0.0
var _surfaces := {}   ## MeshInstance3D → Surface


func _process(delta: float) -> void:
	now += delta
	for s: Surface in _surfaces.values():
		if not is_instance_valid(s.mesh):
			continue
		_upload(s)


## The part frame of `mesh` in the world: its bone posed (skinned) or the mesh itself.
static func part_frame(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int) -> Transform3D:
	if skeleton != null and bone >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	return mesh.global_transform


## A new hole where a beam entered `mesh` at `entry` (world) going `direction`; it crosses
## the part over `chord` m. Returns its record (grow s_drill as the beam drills).
func add_hole(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int, entry: Vector3,
		direction: Vector3, radius: float, chord: float, peak := 2300.0) -> Hole:
	var s := _surface(mesh, skeleton, bone)
	var frame := part_frame(mesh, skeleton, bone).affine_inverse()
	var h := Hole.new()
	h.origin = frame * entry
	h.axis = (frame.basis * direction).normalized()
	h.radius = radius
	h.s_in = 0.0
	h.s_out = maxf(chord, 0.05)
	h.s_drill = 0.0
	h.time = now
	h.peak = peak
	if s.holes.size() >= MAX_HOLES:
		s.holes.remove_at(0)
	s.holes.append(h)
	_upload(s)
	return h


## Makes the whole of `mesh` hot (e.g. a part thrown off by a reactor breach), K above ambient.
func heat(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int, kelvin: float) -> void:
	var s := _surface(mesh, skeleton, bone)
	s.body_heat = Vector2(kelvin, now)
	_upload(s)


func get_hole_count(mesh: MeshInstance3D) -> int:
	var s: Surface = _surfaces.get(mesh)
	return s.holes.size() if s != null else 0


## Holes on `mesh`, part space (copies for a debris body baked from it).
func get_holes(mesh: MeshInstance3D) -> Array[Hole]:
	var s: Surface = _surfaces.get(mesh)
	return s.holes if s != null else ([] as Array[Hole])


## Puts `holes` (from another mesh, same part space) on `mesh`, which is rigid now: its part
## frame in its own space is `part_in_mesh`.
func adopt(mesh: MeshInstance3D, holes: Array[Hole], part_in_mesh: Transform3D, body_heat := Vector2.ZERO) -> void:
	var s := _surface(mesh, null, -1)
	for src in holes:
		var h := Hole.new()
		h.origin = part_in_mesh * src.origin
		h.axis = (part_in_mesh.basis * src.axis).normalized()
		h.radius = src.radius
		h.s_in = src.s_in
		h.s_out = src.s_out
		h.s_drill = src.s_drill
		h.time = src.time
		h.peak = src.peak
		s.holes.append(h)
	if body_heat.x > 0.0:
		s.body_heat = body_heat
	_upload(s)


func forget(mesh: MeshInstance3D) -> void:
	_surfaces.erase(mesh)


## Every hole gone, every mesh back on its own material.
func clear() -> void:
	for s: Surface in _surfaces.values():
		if not is_instance_valid(s.mesh):
			continue
		for i in s.mesh.get_surface_override_material_count():
			s.mesh.set_surface_override_material(i, null)
	_surfaces.clear()


func _surface(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int) -> Surface:
	var s: Surface = _surfaces.get(mesh)
	if s != null:
		return s
	s = Surface.new()
	s.mesh = mesh
	s.skeleton = skeleton
	s.bone = bone
	for i in mesh.mesh.get_surface_count():
		var m := _convert(mesh.get_active_material(i))
		mesh.set_surface_override_material(i, m)
		s.materials.append(m)
	_surfaces[mesh] = s
	return s


static func _convert(source: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var std := source as BaseMaterial3D
	if std != null:
		m.set_shader_parameter(&"albedo_texture", std.albedo_texture)
		m.set_shader_parameter(&"albedo_color", std.albedo_color)
		m.set_shader_parameter(&"roughness", std.roughness)
		m.set_shader_parameter(&"metallic", std.metallic)
		m.set_shader_parameter(&"specular", std.metallic_specular)
		if std.emission_enabled:
			m.set_shader_parameter(&"emission_color", std.emission)
			m.set_shader_parameter(&"emission_energy", std.emission_energy_multiplier)
	return m


func _upload(s: Surface) -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var c := PackedVector4Array()
	a.resize(MAX_HOLES)
	b.resize(MAX_HOLES)
	c.resize(MAX_HOLES)
	for i in s.holes.size():
		var h := s.holes[i]
		a[i] = Vector4(h.origin.x, h.origin.y, h.origin.z, h.radius)
		b[i] = Vector4(h.axis.x, h.axis.y, h.axis.z, h.s_in)
		c[i] = Vector4(h.s_drill, h.s_out, h.time, h.peak)
	var part_to_model := s.mesh.global_transform.affine_inverse() * part_frame(s.mesh, s.skeleton, s.bone)
	var p2m := Projection(part_to_model)
	var m2p := Projection(part_to_model.affine_inverse())
	for m in s.materials:
		m.set_shader_parameter(&"hole_count", s.holes.size())
		m.set_shader_parameter(&"hole_a", a)
		m.set_shader_parameter(&"hole_b", b)
		m.set_shader_parameter(&"hole_c", c)
		m.set_shader_parameter(&"part_to_model", p2m)
		m.set_shader_parameter(&"model_to_part", m2p)
		m.set_shader_parameter(&"hole_now", now)
		m.set_shader_parameter(&"body_heat", s.body_heat)
