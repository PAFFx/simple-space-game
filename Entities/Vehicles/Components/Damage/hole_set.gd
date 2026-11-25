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
	var shell := Vector2(1e6, -1e6)   ## real skin along the axis: material where s <= x or s >= y

class Surface:
	var mesh: MeshInstance3D
	var skeleton: Skeleton3D
	var bone := -1
	var holes: Array[Hole] = []
	var materials: Array[ShaderMaterial] = []
	var body_heat := Vector2(0.0, -1000.0)
	var cut_plane := Vector4(0.0, 1.0, 0.0, 0.0)   ## part space normal, offset
	var cut_side := 0.0
	var cut_heat := Vector2(1800.0, -1000.0)
	var cut_box := AABB(Vector3.ONE * -1e4, Vector3.ONE * 2e4)   ## bone space: the part's box
	var cut_box_xf := Transform3D.IDENTITY                         ## part space → bone space
	var dirty := true

var now := 0.0
var _surfaces := {}   ## MeshInstance3D → Surface


func _process(delta: float) -> void:
	now += delta
	for s: Surface in _surfaces.values():
		if not is_instance_valid(s.mesh):
			continue
		# Records only when they changed or a hole is still being drilled; the clock always;
		# the part's pose only for skinned parts (it moves with the limb).
		var fresh := false
		for h in s.holes:
			if now - h.time < 0.6:
				fresh = true
				break
		if s.dirty or fresh:
			_upload(s)
		else:
			for m in s.materials:
				m.set_shader_parameter(&"hole_now", now)


## A skeleton has its final pose for this frame (after its modifiers): its skinned parts' frames
## go to their materials now, so the holes sit where the mesh is drawn.
func _on_final_pose(skeleton: Skeleton3D) -> void:
	for s: Surface in _surfaces.values():
		if s.skeleton != skeleton or s.bone < 0 or not is_instance_valid(s.mesh):
			continue
		var part_to_model := s.mesh.global_transform.affine_inverse() * part_frame(s.mesh, s.skeleton, s.bone)
		var p2m := Projection(part_to_model)
		var m2p := Projection(part_to_model.affine_inverse())
		for m in s.materials:
			m.set_shader_parameter(&"part_to_model", p2m)
			m.set_shader_parameter(&"model_to_part", m2p)


## The part frame of `mesh` in the world: its bone posed (skinned) or the mesh itself.
static func part_frame(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int) -> Transform3D:
	if skeleton != null and bone >= 0:
		return skeleton.global_transform * FinalPoses.of(skeleton).pose(bone)
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


## `mesh` was cut through: the plane (part space: point and normal); `keep_below` keeps the
## side the normal points away from. Its cut face is drawn hot (`peak` K) and cools, only within
## the part's cross-section: the ellipse across its bone's y in `bounds` (bone space; `to_bone`
## takes part space there). Open shells of the mesh elsewhere show back faces that would
## otherwise draw the face floating outside the part.
func cut(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int, point: Vector3, normal: Vector3,
		keep_below: bool, bounds: AABB, to_bone := Transform3D.IDENTITY, peak := 1800.0) -> void:
	var s := _surface(mesh, skeleton, bone)
	var n := normal.normalized()
	s.cut_plane = Vector4(n.x, n.y, n.z, n.dot(point))
	s.cut_side = 1.0 if keep_below else -1.0
	s.cut_heat = Vector2(peak, now)
	s.cut_box = bounds
	s.cut_box_xf = to_bone
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
		h.shell = src.shell
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
	if skeleton != null and bone >= 0:
		var fp := FinalPoses.of(skeleton)
		var call := _on_final_pose.bind(skeleton)
		if not fp.updated.is_connected(call):
			fp.updated.connect(call)
	for i in mesh.mesh.get_surface_count():
		var m := _convert(mesh.get_active_material(i))
		mesh.set_surface_override_material(i, m)
		s.materials.append(m)
	_surfaces[mesh] = s
	return s


## Height of re-melted metal for the damage shader's bump: blobby dross with a little flow
## (warped simplex FBM, tiling). Baked to a file: generating it at run time took 190 ms.
const MELT_HEIGHT := preload("res://Entities/Vehicles/Components/Damage/Shader/melt_height.png")


static func melt_texture() -> Texture2D:
	return MELT_HEIGHT


static func _convert(source: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"melt_height", melt_texture())
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
	s.dirty = false
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var c := PackedVector4Array()
	var dd := PackedVector4Array()
	dd.resize(MAX_HOLES)
	a.resize(MAX_HOLES)
	b.resize(MAX_HOLES)
	c.resize(MAX_HOLES)
	for i in s.holes.size():
		var h := s.holes[i]
		a[i] = Vector4(h.origin.x, h.origin.y, h.origin.z, h.radius)
		b[i] = Vector4(h.axis.x, h.axis.y, h.axis.z, h.s_in)
		c[i] = Vector4(h.s_drill, h.s_out, h.time, h.peak)
		dd[i] = Vector4(h.shell.x, h.shell.y, 0.0, 0.0)
	var part_to_model := s.mesh.global_transform.affine_inverse() * part_frame(s.mesh, s.skeleton, s.bone)
	var p2m := Projection(part_to_model)
	var m2p := Projection(part_to_model.affine_inverse())
	for m in s.materials:
		m.set_shader_parameter(&"hole_count", s.holes.size())
		m.set_shader_parameter(&"hole_a", a)
		m.set_shader_parameter(&"hole_b", b)
		m.set_shader_parameter(&"hole_c", c)
		m.set_shader_parameter(&"hole_d", dd)
		m.set_shader_parameter(&"part_to_model", p2m)
		m.set_shader_parameter(&"model_to_part", m2p)
		m.set_shader_parameter(&"hole_now", now)
		m.set_shader_parameter(&"body_heat", s.body_heat)
		m.set_shader_parameter(&"cut_plane", s.cut_plane)
		m.set_shader_parameter(&"cut_side", s.cut_side)
		m.set_shader_parameter(&"cut_heat", s.cut_heat)
		m.set_shader_parameter(&"cut_box_min", s.cut_box.position)
		m.set_shader_parameter(&"cut_box_max", s.cut_box.end)
		m.set_shader_parameter(&"cut_box_xf", Projection(s.cut_box_xf))
