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
	var cut_edges := PackedVector4Array()   ## the cut's outline: (nx, ny, c) half-planes in its plane
	var cap: MeshInstance3D                  ## the cut's face (stencil cap), if cut
	var cap_root: Node3D                     ## what holds it (a bone attachment for a skinned part)
	var writers: Array[ShaderMaterial] = []  ## next passes marking the cross-section
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
		if s.cap != null and is_instance_valid(s.cap):
			s.cap.visible = s.mesh.is_visible_in_tree()
		if s.dirty or fresh:
			_upload(s)
		else:
			for m in s.materials:
				m.set_shader_parameter(&"hole_now", now)
			if s.cap != null and is_instance_valid(s.cap):
				(s.cap.material_override as ShaderMaterial).set_shader_parameter(&"hole_now", now)


## A skeleton has its final pose for this frame (after its modifiers): its skinned parts' frames
## go to their materials now, so the holes sit where the mesh is drawn.
func _on_final_pose(skeleton: Skeleton3D) -> void:
	for s: Surface in _surfaces.values():
		if s.skeleton != skeleton or s.bone < 0 or not is_instance_valid(s.mesh):
			continue
		var part_to_model := s.mesh.global_transform.affine_inverse() * part_frame(s.mesh, s.skeleton, s.bone)
		var p2m := Projection(part_to_model)
		var m2p := Projection(part_to_model.affine_inverse())
		for m in s.materials + s.writers:
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
## `section` (part space: where the plane meets the part's skin; its convex outline is used).
## Open shells and thin plates show back faces that would otherwise draw the face floating
## outside the part.
func cut(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int, point: Vector3, normal: Vector3,
		keep_below: bool, section: PackedVector3Array, peak := 1800.0) -> void:
	var s := _surface(mesh, skeleton, bone)
	var n := normal.normalized()
	s.cut_plane = Vector4(n.x, n.y, n.z, n.dot(point))
	s.cut_side = 1.0 if keep_below else -1.0
	s.cut_heat = Vector2(peak, now)
	s.cut_edges = _outline(n, section)
	_make_cap(s, n, point, section)
	_upload(s)


const CUT_STENCIL := "res://Entities/Vehicles/Components/Damage/Shader/cut_stencil.gdshaderinc"
const CUT_CAP := "res://Entities/Vehicles/Components/Damage/Shader/cut_cap.gdshaderinc"
const STENCIL_REFS := 8
static var _next_ref := 0
static var _stencil_shaders := {}   ## [kind, ref] → Shader


static func _stencil_shader(kind: String, ref: int) -> Shader:
	var key := [kind, ref]
	if _stencil_shaders.has(key):
		return _stencil_shaders[key]
	var sh := Shader.new()
	if kind == "write":
		sh.code = "shader_type spatial;\nrender_mode cull_front, diffuse_burley;\nstencil_mode write, compare_always, %d;\n#include \"%s\"\n" % [ref, CUT_STENCIL]
	else:
		sh.code = "shader_type spatial;\nrender_mode cull_disabled, depth_draw_always, diffuse_burley, specular_schlick_ggx;\nstencil_mode read, compare_equal, %d;\n#include \"%s\"\n" % [ref, CUT_CAP]
	_stencil_shaders[key] = sh
	return sh


## The cut's face: back faces seen through the cut mark the stencil (a next pass on each
## surface), a grid across the cut plane draws the face where they did: the real cross-section,
## concave or not, never outside it.
func _make_cap(s: Surface, n: Vector3, point: Vector3, section: PackedVector3Array) -> void:
	_drop_cap(s)
	_next_ref = _next_ref % STENCIL_REFS + 1
	var ref := _next_ref
	for m in s.materials:
		var w := ShaderMaterial.new()
		w.shader = _stencil_shader("write", ref)
		m.next_pass = w
		s.writers.append(w)
	# A grid over the section's extent on the plane, part space (the shader lifts it onto the
	# torn surface).
	var e1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := n.cross(e1)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in section:
		var uv := Vector2((p - point).dot(e1), (p - point).dot(e2))
		lo = lo.min(uv)
		hi = hi.max(uv)
	if section.size() < 3:
		lo = Vector2(-2.0, -2.0)
		hi = Vector2(2.0, 2.0)
	lo -= Vector2(0.3, 0.3)
	hi += Vector2(0.3, 0.3)
	var steps := 24
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in steps + 1:
		for i in steps + 1:
			var u := lerpf(lo.x, hi.x, float(i) / steps)
			var v := lerpf(lo.y, hi.y, float(j) / steps)
			verts.append(point + e1 * u + e2 * v)
	for j in steps:
		for i in steps:
			var a := j * (steps + 1) + i
			idx.append_array([a, a + 1, a + steps + 1, a + 1, a + steps + 2, a + steps + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var cap := MeshInstance3D.new()
	cap.name = "CutCap"
	cap.mesh = mesh
	cap.layers = s.mesh.layers
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Never culled away by its own (flat) bounds while the torn offset lifts it.
	cap.extra_cull_margin = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = _stencil_shader("cap", ref)
	mat.set_shader_parameter(&"melt_height", melt_texture())
	cap.material_override = mat
	if s.skeleton != null and s.bone >= 0:
		var attach := BoneAttachment3D.new()
		attach.name = "CutCapMount"
		attach.bone_name = s.skeleton.get_bone_name(s.bone)
		s.skeleton.add_child(attach)
		attach.add_child(cap)
		s.cap_root = attach
	else:
		s.mesh.add_child(cap)
		s.cap_root = cap
	s.cap = cap


func _drop_cap(s: Surface) -> void:
	if s.cap_root != null and is_instance_valid(s.cap_root):
		s.cap_root.queue_free()
	s.cap = null
	s.cap_root = null
	for m in s.materials:
		m.next_pass = null
	s.writers.clear()


## The convex outline of `points` (on the plane of normal `n`) in the plane's own coordinates
## (as the shader builds them), as half-planes nx·u + ny·v <= c, a few cm outside.
static func _outline(n: Vector3, points: PackedVector3Array) -> PackedVector4Array:
	var out := PackedVector4Array()
	if points.size() < 3:
		return out
	var e1 := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := n.cross(e1)
	var flat := PackedVector2Array()
	for p in points:
		flat.append(Vector2(p.dot(e1), p.dot(e2)))
	var hull := Geometry2D.convex_hull(flat)
	if hull.size() < 4:
		return out
	var centre := Vector2.ZERO
	for i in hull.size() - 1:
		centre += hull[i]
	centre /= float(hull.size() - 1)
	for i in hull.size() - 1:
		var a := hull[i]
		var b := hull[i + 1]
		var nn := Vector2(b.y - a.y, a.x - b.x).normalized()
		if nn.dot(centre - a) > 0.0:
			nn = -nn
		out.append(Vector4(nn.x, nn.y, nn.dot(a) + 0.05, 0.0))
	return out


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
	var s: Surface = _surfaces.get(mesh)
	if s != null:
		_drop_cap(s)
	_surfaces.erase(mesh)


## Every hole gone, every mesh back on its own material.
func clear() -> void:
	for s: Surface in _surfaces.values():
		_drop_cap(s)
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
		var edges := s.cut_edges.duplicate()
		var count := mini(edges.size(), 24)
		edges.resize(24)
		m.set_shader_parameter(&"cut_edge_count", count)
		m.set_shader_parameter(&"cut_edges", edges)
		m.set_shader_parameter(&"cut_capped", s.cap != null)
	# The writers and the cap need the cut (and the writers the part's frame) too.
	var users: Array = s.writers.duplicate()
	if s.cap != null and is_instance_valid(s.cap):
		users.append(s.cap.material_override)
	for w: ShaderMaterial in users:
		w.set_shader_parameter(&"cut_plane", s.cut_plane)
		w.set_shader_parameter(&"cut_side", s.cut_side)
		w.set_shader_parameter(&"cut_heat", s.cut_heat)
		w.set_shader_parameter(&"hole_now", now)
		w.set_shader_parameter(&"part_to_model", p2m)
		w.set_shader_parameter(&"model_to_part", m2p)
