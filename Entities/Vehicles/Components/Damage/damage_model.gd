class_name DamageModel
extends Node

## What shots physically do to the suit (Docs/Damage). The suit is its parts, each a convex
## hull posed with the skeleton (an Area3D on Layers.PHYS_DAMAGE, built at start from the
## part's mesh), with the mass model's dry mass, volume and tank (LimbReaction), and the
## components inside them: the pilot, the cockpit, the reactor, water tank cells,
## thrusters, cameras, the vulcans and the carried equipment.
##
## A beam drills (beam_contact, called by ProjectileManager every tick it touches the suit):
## its energy removes the column of material along its line, part after part, at
## COUPLING / REMOVAL_ENERGY kg per J; the front stands at the drill face until the column is
## gone, then the beam goes on from the far side with what is left. Every part it enters gets
## a hole (HoleSet); every component it reaches is hit: the pilot (killed: game over), the
## reactor (breach: the 200 m flash), a tank cell (steam burst), a thruster (dead), a camera
## (the sensors lose it), a weapon (broken, its stores go off). A part that loses too much of
## its cross-section breaks off at its joint and flies away (sever), with everything beyond.
## Bullets push and break thin things; missile bursts throw fragments (apply_impact).
## Everything the flight computer, AMBAC, the sensors and the weapons use follows.

signal part_damaged(part: StringName)
signal part_severed(part: StringName)
signal component_destroyed(kind: StringName, component: StringName)
signal pilot_killed
signal reactor_breached
signal cockpit_holed(entry: Vector3, exit: Vector3)
## Everything was put back (repair).
signal repaired
## A shot reached the suit's structure (once per shot).
signal hit(position: Vector3, direction: Vector3)

## Share of a beam's energy that removes material, and the energy that removes one kg
## (Docs/Damage/physics.md §1).
const COUPLING := 0.6
const REMOVAL_ENERGY := 3.0e6
const WATER_DENSITY := 1000.0
## Drill resolution along the line, m.
const STEP := 0.1
## A part breaks off when less than this share of its cross-section is left.
const BREAK_LEFT := 0.35
## A limb with less than this left snaps off by itself (after a moment); between it and
## STRESS_LEFT it holds until the suit's acceleration at the wound is too much for what is left.
const SNAP_LEFT := 0.5
## Below this share of its section left a part's thrusters are dead (lines and mounts gone).
const THRUSTER_LEFT := 0.3
## Parts with a real joint inside (frame, actuators, cables): torn off they leave a frame stub.
## The rest (skirts, pods, nozzles, guards, shoulder armour) are bolted on: only a socket crater.
const JOINTED := ["head", "upper_arm", "forearm", "hand", "thigh", "shin", "foot"]
## A breach makes its debris a few pieces per physics tick, under the flash.
const PIECES_PER_TICK := 4
## A limb shot off may stay hanging on its last strut and cables (chance; more with more of its
## section left), until the load on it passes DANGLE_HOLD m/s² of its own mass (a hard boost)
## or what it hangs from comes off.
const DANGLE_CHANCE := 0.5
const DANGLE_HOLD := 20.0
const PIECE_TICK := 1.0 / 60.0
const STRESS_LEFT := 0.8
## Blow-off radius of a burst, m per J^(1/3) (cube-root scaling).
const BLAST_K := 0.0025
const REACTOR_YIELD := 2.5e12
## Parts that never break off (the suit's core): losing them is the reactor or the pilot.
const CORE_PARTS: Array[StringName] = [&"chest", &"spine", &"pelvis"]
## Long parts (limbs, pods, nozzles) break where a hole leaves less than BREAK_LEFT of the
## section; the blocky ones (head, backpack, shoulders, skirts) only once nothing is left.
const LIMB_PREFIXES := ["upper_arm", "forearm", "hand", "thigh", "shin", "foot", "main_pod",
		"main_nozzle", "calf_guard"]
## Secondary yield of each piece of equipment's stores, J (physics.md §6).
const STORES := {
	&"BeamRifle": 5.0e8, &"HyperBazooka": 8.4e8, &"FinFunnels": 1.0e8, &"BeamSaber": 5.0e7,
}

enum Kind { PILOT, COCKPIT, REACTOR, TANK, THRUSTER, EYES, BODY_CAMERA, VULCAN, EQUIPMENT }
const KIND_NAMES := [&"pilot", &"cockpit", &"reactor", &"tank", &"thruster", &"eyes", &"camera", &"vulcan", &"equipment"]

class Part:
	var name: StringName
	var bone := -1
	var mesh: MeshInstance3D
	var area: Area3D
	var dry := 0.0
	var tank := 0.0
	var volume := 0.0
	var density := 0.0        ## dry kg/m³
	var width := 2.0          ## of its cross-section, m
	var section := 4.0        ## cross-section across its bone, m²
	var limb := false
	var last_hole := Vector3.ZERO   ## part space: where it was last holed / torn
	var has_hole := false
	var cut_y := INF                ## bone space: it was cut through here
	var hull_points := PackedVector3Array()
	var aabb := AABB()        ## bone space
	var left := 1.0           ## share of its cross-section still there
	var severed := false
	var equipment: MsEquipment   ## equipment as a part: a box per mesh, not a hull
	var box := AABB()
	var boxes: Array = []        ## [MeshInstance3D, AABB in its own space]
	var skin_faces := PackedVector3Array()   ## its mesh's triangles in bone space, outward wound
	## Its skin split into small triangles (edges ≤ 0.45 m), bone space, for torn panels; built a
	## little each frame after load (`small_done`).
	var small_pos := PackedVector3Array()    ## 3 per triangle
	var small_nrm := PackedVector3Array()    ## 3 per triangle
	var small_uv := PackedVector2Array()     ## 3 per triangle
	var small_mat: Array = []                ## 1 per triangle
	var small_done := false
	var small_next := 0                      ## next skin triangle to split

class Component:
	var kind := 0
	var name: StringName
	var part: Part
	var node: Node3D          ## frame: this node, else the bone, else the body
	var bone := -1
	var local := Vector3.ZERO
	var tip := Vector3.ZERO   ## capsule: second point (local)
	var capsule := false
	var radius := 0.5
	var box := AABB()         ## box component (local)
	var is_box := false
	var alive := true
	var ref: Object
	var index := -1
	var facing := Vector3.ZERO   ## cameras: which way it looks (body frame)
	var half_deg := 65.0         ## cameras: half its field, deg
	var grade := 1               ## cameras: 0 the head's main camera, 1 a body camera
	var markers: Array[CameraMarker] = []   ## cameras: where it sits, its lens light(s)

class Drill:
	var key := 0
	var last := 0.0
	var from_body := Vector3.ZERO
	var dir_body := Vector3.FORWARD
	var t0 := 0.0
	var t_end := 0.0
	var kg := PackedFloat32Array()
	var cells: Array = []     ## per step: the tank cell there, or null
	var pos := 0
	var spare := 0.0
	var segs: Array = []      ## [part, t_in, t_out, hole, through]
	var events: Array = []    ## [t, component], sorted
	var next_event := 0
	var radius := 0.6
	var deposited := {}       ## tank cell → J
	var due := {}             ## tank cells whose burst is scheduled
	var done := false
	var counted := false

## Off: shots only count as hits (hit), nothing is damaged (tools that measure hits).
@export var enabled: bool = true

var parts: Array[Part] = []
var components: Array[Component] = []
var pilot_dead := false
var reactor_gone := false
var destroyed := false
var holes: HoleSet
## Last thing that happened, for the range panel.
var last_event := ""

var _vehicle: VehicleBase
var _body: RigidBody3D
var _skel: Skeleton3D
var _reaction: LimbReaction
var _built := false
var _area_rids: Array[RID] = []
var _part_of_rid := {}
var _drills := {}
var _clock := 0.0
var _capability_dirty := false
var _capability_due := 0.0
var _saved_priority := {}     ## AmbacJoint → priority
var _hidden_nodes: Array[Node3D] = []
var _debris: Array[Node] = []
var _unequipped: Array[MsEquipment] = []
var _mass_removed := {}       ## part name → [dry, tank]
var _queue: Array = []        ## [time, Callable]
var _rng := RandomNumberGenerator.new()
var _hull_layers: Array = []
var _stubs: Array[Node] = []
var _snapping := {}          ## Part → true: about to snap off
var _joint_out := {}         ## bone name → true: its joint (to its parent) was shot
var limp := {}               ## Part → true: can't be controlled (severed, or a joint up its chain out)
## Time spent per damage function (µs): [calls, total, worst]. Read by the fuzz test.
static var timings := {}
var _followers := {}         ## Part → [Node3D]: what rides its bone (attachments, props)
var _dangles: Array = []     ## [joint, piece body, part it hangs from, suit-local anchor, piece-local anchor, cables mesh, smoothed accel, last velocity]
var _last_v := Vector3.INF
var _last_w := Vector3.ZERO
var _accel := Vector3.ZERO
var _alpha := Vector3.ZERO
var _capacity_built := 0.0   ## the flight computer's propellant capacity as built, kg
var _boost_accel := 0.0
var _breach_v := Vector3.ZERO   ## the suit's velocity when its reactor went
var _breach_w := Vector3.ZERO      ## the suit's full thrust / mass, m/s² (set when built)
var _opaque: Array[Node] = []
var _glow_slots := {}   ## CameraMarker → [overlay ShaderMaterial, lens index]
var _thruster_saved := {}     ## Thruster → [max thrust, gimbal limits ×3] as built
var _leaks: Array = []        ## [node, local point, local jet direction, N, until]


func _ready() -> void:
	_vehicle = VehicleBase.find_vehicle(self)
	_body = _vehicle as Node as RigidBody3D
	holes = HoleSet.new()
	holes.name = "Holes"
	add_child(holes)
	_rng.seed = hash(get_path())
	_build.call_deferred()


func _physics_process(delta: float) -> void:
	_clock += delta
	for key in _drills.keys():
		var d: Drill = _drills[key]
		if _clock - d.last > 0.25:
			_finish(d)
			_drills.erase(key)
	var i := 0
	while i < _queue.size():
		if _queue[i][0] <= _clock:
			var call: Callable = _queue[i][1]
			_queue.remove_at(i)
			call.call()
		else:
			i += 1
	for li in range(_leaks.size() - 1, -1, -1):
		var lk: Array = _leaks[li]
		if _clock > float(lk[4]) or not is_instance_valid(lk[0]) or reactor_gone:
			_leaks.remove_at(li)
			continue
		var xf := (lk[0] as Node3D).global_transform
		var at: Vector3 = xf * (lk[1] as Vector3)
		var jet: Vector3 = (xf.basis * (lk[2] as Vector3)).normalized()
		# The jet goes out; the suit is pushed the other way.
		_body.apply_force(-jet * float(lk[3]), at - _body.global_position)
	_stress(delta)
	_hold_dangles(delta)
	_prep_small(1500)
	if _capability_dirty and _clock >= _capability_due:
		_capability_dirty = false
		var fc := _flight()
		if fc != null and not reactor_gone:
			fc.rebuild_capability_map_async()


func is_built() -> bool:
	return _built


func find_part(part_name: StringName) -> Part:
	for p in parts:
		if p.name == part_name:
			return p
	return null


# --- Building ---

func _build() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_reaction = _vehicle.find_component(LimbReaction) as LimbReaction
	if _reaction == null or _reaction.skeleton == null or _body == null:
		return
	_skel = _reaction.skeleton
	for seg in _reaction.segments:
		var bone := _skel.find_bone(seg.bone_name)
		var mesh_name := seg.mesh_name if seg.mesh_name != &"" else StringName(String(seg.bone_name).replace(".", "_").to_pascal_case())
		var mesh := _skel.get_node_or_null(NodePath(String(mesh_name))) as MeshInstance3D
		if bone < 0 or mesh == null:
			continue
		var points := bone_space_points(mesh, _skel, bone)
		if points.size() < 4:
			continue
		var p := Part.new()
		p.name = seg.bone_name
		p.bone = bone
		p.mesh = mesh
		p.dry = seg.mass
		p.tank = seg.propellant_capacity
		var box := AABB(points[0], Vector3.ZERO)
		for v in points:
			box = box.expand(v)
		p.aabb = box
		p.volume = seg.volume if seg.volume > 0.0 else box.get_volume() * 0.45
		p.density = p.dry / maxf(p.volume, 0.1)
		p.width = maxf(box.size.x, box.size.z)
		p.section = maxf(box.size.x * box.size.z * 0.785, 0.2)
		for prefix in LIMB_PREFIXES:
			if String(p.name).begins_with(prefix):
				p.limb = true
		_make_area(p, points)
		_make_skin_probe(p)
		parts.append(p)
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			if eq is MsShield:
				continue   # solid on its own: it drills itself (MsShield.beam_contact)
			var p := Part.new()
			p.name = eq.name
			p.equipment = eq
			p.box = MsLoadout.local_box(eq)
			p.dry = eq.mass
			var solid := 0.0
			for node in eq.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				if mi.mesh != null:
					p.boxes.append([mi, mi.get_aabb()])
					solid += mi.get_aabb().get_volume()
			p.volume = maxf((solid if solid > 0.0 else p.box.get_volume()) * 0.35, 0.1)
			p.density = p.dry / p.volume
			var dims := p.box.size
			p.width = maxf(dims.x, dims.y)
			p.section = maxf(dims.x * dims.y * 0.785, 0.2)
			p.limb = true
			parts.append(p)
			var c := _add_component(Kind.EQUIPMENT, eq.name, p, eq, Vector3.ZERO, 0.0)
			c.is_box = true
			c.box = p.box
			c.ref = eq
	_build_components()
	_place_cameras()
	_build_followers()
	for node in _vehicle.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null and not _prep_meshes.has(mi.mesh):
			_prep_meshes.append(mi.mesh)
	var fx := DamageFx.of(self)
	if fx != null:
		fx.prewarm()
	_prewarm_holes()
	var fcb := _flight()
	if fcb != null:
		_capacity_built = fcb.propellant_capacity
	# Full boost: the main thrust along the strongest axis, over the suit's mass.
	var thrust := {}
	for t in _vehicle.find_children("*", "", true, false):
		if t is Thruster:
			var th := t as Thruster
			var axis := (_body.global_basis.inverse() * -th.global_basis.z).round()
			thrust[axis] = float(thrust.get(axis, 0.0)) + th.max_thrust
	for k in thrust:
		_boost_accel = maxf(_boost_accel, float(thrust[k]) / maxf(_body.mass, 1.0))
	_built = true


## The part's skin as triangles in its bone's space, wound outward (for _skin_shells).
func _make_skin_probe(p: Part) -> void:
	var faces := PackedVector3Array()
	var to_bone := FinalPoses.of(_skel).pose(p.bone).affine_inverse()
	var mesh_in_skel := _skel.global_transform.affine_inverse() * p.mesh.global_transform
	for si in p.mesh.mesh.get_surface_count():
		var arrays := arrays_of(p.mesh.mesh, si)
		var skinned := skin_surface(p.mesh, _skel, arrays)
		var v: PackedVector3Array = skinned[0]
		var nrm: PackedVector3Array = skinned[1]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n_tri := (idx.size() if not idx.is_empty() else v.size()) / 3
		for t in n_tri:
			var i0 := idx[t * 3] if not idx.is_empty() else t * 3
			var i1 := idx[t * 3 + 1] if not idx.is_empty() else t * 3 + 1
			var i2 := idx[t * 3 + 2] if not idx.is_empty() else t * 3 + 2
			var a := to_bone * (mesh_in_skel * v[i0])
			var b := to_bone * (mesh_in_skel * v[i1])
			var c := to_bone * (mesh_in_skel * v[i2])
			# Wound so its normal points out (as the vertex normals do).
			if not nrm.is_empty():
				var vn := nrm[i0] + nrm[i1] + nrm[i2]
				if (b - a).cross(c - a).dot(to_bone.basis * (mesh_in_skel.basis * vn)) < 0.0:
					var tmp := b
					b = c
					c = tmp
			faces.append(a)
			faces.append(b)
			faces.append(c)
	p.skin_faces = faces


## Where the plane across `p`'s bone at height `y` (bone space) meets its skin: the points
## where its triangles' edges cross it, taken to the cut mesh's part space by `to_part`.
func _section(p: Part, y: float, to_part: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var f := p.skin_faces
	for t in range(0, f.size(), 3):
		for k in 3:
			var a := f[t + k]
			var b := f[t + (k + 1) % 3]
			if (a.y - y) * (b.y - y) < 0.0:
				out.append(to_part * a.lerp(b, (y - a.y) / (b.y - a.y)))
	return out


## Where `p`'s real skin is along a beam entering it at `entry` (world) going `dir` (`s` from the
## entry, m): it enters the skin at x and leaves it for good at y (inner shells, the inside
## between them: all counted as the part). No skin data: the whole line.
func _skin_shells(p: Part, entry: Vector3, dir: Vector3, length: float) -> Vector2:
	if p.skin_faces.is_empty():
		return Vector2(-1e6, 1e6)
	var to_bone := (_skel.global_transform * FinalPoses.of(_skel).pose(p.bone)).affine_inverse()
	var d := (to_bone.basis * dir).normalized()
	var o := to_bone * entry - d   # from 1 m before the entry
	var f := p.skin_faces
	var hits: Array = []   # [s, entering]
	for t in range(0, f.size(), 3):
		var x: Variant = Geometry3D.ray_intersects_triangle(o, d, f[t], f[t + 1], f[t + 2])
		if x == null:
			continue
		var hs: float = ((x as Vector3) - o).dot(d) - 1.0
		if hs > length + 0.5:
			continue
		hits.append([hs, (f[t + 1] - f[t]).cross(f[t + 2] - f[t]).dot(d) < 0.0])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# Metal wherever the line is inside at least one shell (an armour plate around an inner
	# piece nests them).
	var spans: Array = []
	var depth := 0
	var start := -1.0
	for h in hits:
		if h[1]:
			if depth == 0:
				start = h[0]
			depth += 1
		elif depth > 0:
			depth -= 1
			if depth == 0:
				spans.append([start, h[0]])
		else:
			spans.append([-1.0, h[0]])   # began inside (an open shell)
	if spans.is_empty():
		return Vector2(-1e6, 1e6)
	return Vector2(spans[0][0], spans[-1][1])


## The mesh's vertices, skinned in the skeleton's current pose, in `bone`'s space.
static func bone_space_points(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var to_bone := FinalPoses.of(skeleton).pose(bone).affine_inverse()
	var mesh_in_skel := skeleton.global_transform.affine_inverse() * mesh.global_transform
	for s in mesh.mesh.get_surface_count():
		var arrays := arrays_of(mesh.mesh, s)
		var skinned: PackedVector3Array = skin_surface(mesh, skeleton, arrays)[0]
		for v in skinned:
			out.append(to_bone * (mesh_in_skel * v))
	return out


## A surface's vertices and normals skinned in the skeleton's current pose (mesh space):
## [PackedVector3Array, PackedVector3Array].
static func skin_surface(mesh: MeshInstance3D, skeleton: Skeleton3D, arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var bones_arr: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var skin := mesh.skin
	if skin == null or bones_arr.is_empty() or skeleton == null:
		return [verts.duplicate(), normals.duplicate()]
	# Rigid (every vertex on one bind): one transform for all, done natively.
	var rigid := rigid_bind(bones_arr, weights, verts.size())
	if rigid >= 0:
		var xf := bind_transform(mesh, skeleton, rigid)
		return [xf * verts, Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * normals]
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		mats.append(FinalPoses.of(skeleton).pose(maxi(bone, 0)) * skin.get_bind_pose(b))
	var per := bones_arr.size() / maxi(verts.size(), 1)
	var out := PackedVector3Array()
	out.resize(verts.size())
	var nout := PackedVector3Array()
	nout.resize(normals.size())
	for i in verts.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var m := mats[bones_arr[i * per + k]]
			p += (m * verts[i]) * w
			if not normals.is_empty():
				n += (m.basis * normals[i]) * w
		out[i] = p
		if not normals.is_empty():
			nout[i] = n.normalized()
	return [out, nout]


static var _hulls := {}    ## Mesh instance id → its convex hull (debris collision)


## A mesh's convex hull for debris collision, from its cached vertices (asking the mesh reads it
## back from the render thread, ~9 ms), at most ~256 points; kept.
static func hull_of(mesh: Mesh) -> Shape3D:
	var key := mesh.get_instance_id()
	if _hulls.has(key):
		return _hulls[key]
	var pts := PackedVector3Array()
	for si in mesh.get_surface_count():
		pts.append_array(arrays_of(mesh, si)[Mesh.ARRAY_VERTEX])
	var step := maxi(1, pts.size() / 256)
	if step > 1:
		var few := PackedVector3Array()
		for i in range(0, pts.size(), step):
			few.append(pts[i])
		pts = few
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	_hulls[key] = hull
	return hull
static var _arrays := {}   ## Mesh instance id → its surfaces' arrays (static data, read once)
static var _rigid := {}    ## bones array hash → its single bind, or -1


## A mesh surface's arrays, read from the renderer once (with the render thread on, a read
## waits for it) and kept. Don't change what it returns.
static func arrays_of(mesh: Mesh, si: int) -> Array:
	var key := mesh.get_instance_id()
	var surfaces: Array = _arrays.get(key, [])
	if surfaces.is_empty():
		for i in mesh.get_surface_count():
			surfaces.append(mesh.surface_get_arrays(i))
		_arrays[key] = surfaces
	return surfaces[si]


## The one bind every vertex is fully weighted to, or -1 (skinned across bones).
static func rigid_bind(bones_arr: PackedInt32Array, weights: PackedFloat32Array, count: int) -> int:
	var key := hash(bones_arr) ^ hash(weights)
	if _rigid.has(key):
		return _rigid[key]
	var per := bones_arr.size() / maxi(count, 1)
	var found := -1
	for i in count:
		for k in per:
			var w := weights[i * per + k]
			if w <= 1e-3:
				continue
			var b := bones_arr[i * per + k]
			if w < 0.999 or (found >= 0 and b != found):
				_rigid[key] = -1
				return -1
			found = b
	_rigid[key] = found
	return found


## Mesh space → skeleton space for a mesh rigidly on bind `b`, in the pose as drawn.
static func bind_transform(mesh: MeshInstance3D, skeleton: Skeleton3D, b: int) -> Transform3D:
	var skin := mesh.skin
	var bone := skin.get_bind_bone(b)
	if bone < 0:
		bone = skeleton.find_bone(skin.get_bind_name(b))
	return FinalPoses.of(skeleton).pose(maxi(bone, 0)) * skin.get_bind_pose(b)


func _make_area(p: Part, points: PackedVector3Array) -> void:
	var attach := BoneAttachment3D.new()
	attach.name = "DamageHull_" + String(p.name).replace(".", "_")
	attach.bone_name = p.name
	_skel.add_child(attach)
	var area := Area3D.new()
	area.collision_layer = Layers.PHYS_DAMAGE
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	p.hull_points = points
	shape.shape = hull
	area.add_child(shape)
	attach.add_child(area)
	p.area = area
	_area_rids.append(area.get_rid())
	_part_of_rid[area.get_rid()] = p


func _add_component(kind: int, cname: StringName, part: Part, node: Node3D, local: Vector3, radius: float) -> Component:
	var c := Component.new()
	c.kind = kind
	c.name = cname
	c.part = part
	c.node = node
	c.local = local
	c.radius = radius
	components.append(c)
	return c


func _bone_component(kind: int, cname: StringName, part: Part, local: Vector3, radius: float) -> Component:
	var c := _add_component(kind, cname, part, null, local, radius)
	c.bone = part.bone if part != null else -1
	return c


func _build_components() -> void:
	var chest := find_part(&"chest")
	var pelvis := find_part(&"pelvis")
	var head := find_part(&"head")
	# Pilot and cockpit: the seated pilot around the cockpit camera (eye point).
	var cockpit := _vehicle.get_cockpit()
	var cam := cockpit.get_player_camera() if cockpit != null else null
	if cam != null:
		var pilot := _add_component(Kind.PILOT, &"pilot", chest, cam, Vector3(0.0, 0.1, 0.05), 0.3)
		pilot.capsule = true
		pilot.tip = Vector3(0.0, -0.75, 0.15)
		var legs := _add_component(Kind.PILOT, &"pilot", chest, cam, Vector3(0.0, -0.7, 0.1), 0.22)
		legs.capsule = true
		legs.tip = Vector3(0.0, -0.95, -0.85)
		_add_component(Kind.COCKPIT, &"cockpit", chest, cam, Vector3.ZERO, 1.6)
	# Reactor: below the cockpit around the waist (top of the pelvis).
	if pelvis != null:
		var at := pelvis.aabb.get_center() + Vector3(0.0, pelvis.aabb.size.y * 0.22, 0.0)
		_bone_component(Kind.REACTOR, &"reactor", pelvis, at, 0.85)
	# Water tank cells: each tank fills a box in its part, split in four along its longest
	# side: the chest's behind the cockpit, the pelvis's below the reactor, others centred.
	for p in parts:
		if p.tank <= 0.0 or p.equipment != null:
			continue
		var vol := p.tank / WATER_DENSITY
		var k := clampf(pow(vol / maxf(p.aabb.get_volume(), 0.01), 1.0 / 3.0), 0.05, 0.8)
		var size := p.aabb.size * k
		var centre := p.aabb.get_center()
		var to_bone := (_skel.global_transform * FinalPoses.of(_skel).pose(p.bone)).affine_inverse().basis * _body.global_basis
		var shift := Vector3.ZERO
		if p == chest:
			shift = (to_bone * Vector3.BACK).normalized()
		elif p == pelvis:
			shift = (to_bone * Vector3.DOWN).normalized()
		if shift != Vector3.ZERO:
			var room := ((p.aabb.size - size) * 0.5 * shift.abs())
			centre += shift * (room.x + room.y + room.z) * 0.9
		var axis := 0
		for ax in 3:
			if size[ax] > size[axis]:
				axis = ax
		for cell in 4:
			var cs := size
			cs[axis] = size[axis] / 4.0
			var origin := centre - size * 0.5
			origin[axis] += cs[axis] * cell
			var c := _bone_component(Kind.TANK, StringName("%s tank %d" % [p.name, cell + 1]), p, Vector3.ZERO, 0.0)
			c.is_box = true
			c.box = AABB(origin, cs)
	# Thrusters.
	var root := _vehicle.get_node_or_null(^"Thrusters")
	if root != null:
		for node in root.find_children("*", "", true, false):
			var t := node as Thruster
			if t == null:
				continue
			var attach := t.get_parent() as BoneAttachment3D
			var part := find_part(attach.bone_name) if attach != null else null
			var c := _add_component(Kind.THRUSTER, t.name, part, t, Vector3.ZERO, 0.3 + 0.6 * sqrt(t.max_thrust / 1.6e6))
			c.ref = t
	# Head: the main camera's eyes and the vulcans.
	var sensors := _comp(SensorSuite) as SensorSuite
	if head != null:
		var eye := head.aabb.get_center() + Vector3(0.0, 0.0, -head.aabb.size.z * 0.3)
		var eyes := _bone_component(Kind.EYES, &"main camera", head, eye, 0.6)
		eyes.facing = Vector3.FORWARD
		eyes.half_deg = 105.0   # the head turns
		eyes.grade = 0
		_panoramic_camera(&"rear head camera", head, Vector3(0.0, 0.5, 1.0), 75.0)
	var fcs := _comp(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			if w.equipment == null and head != null and String(w.mount_bone).begins_with("head"):
				var c := _add_component(Kind.VULCAN, w.name, head, w, Vector3.ZERO, 0.7)
				c.ref = w
	# Body cameras (SensorSuite, body frame): each belongs to the part it sits nearest.
	if sensors != null:
		for i in sensors.body_camera_positions.size():
			var c := _add_component(Kind.BODY_CAMERA, StringName("camera %d" % i), null, null, sensors.body_camera_positions[i], 0.35)
			c.index = i
			c.ref = sensors
			c.part = _nearest_part(_body.global_transform * sensors.body_camera_positions[i])
			c.facing = sensors.body_camera_facings[i].normalized() if i < sensors.body_camera_facings.size() else Vector3.FORWARD
			c.half_deg = 65.0 if c.facing.dot(Vector3.FORWARD) > 0.5 else 70.0
	# Cameras for the panoramic screen only: rear skirts (past the bazooka), feet, forearms.
	for spec in [[&"skirt_rear.R", Vector3(0.5, -0.5, 1.0), 65.0], [&"skirt_rear.L", Vector3(-0.5, -0.5, 1.0), 65.0],
			[&"foot.R", Vector3(0.3, -1.0, 0.0), 70.0], [&"foot.L", Vector3(-0.3, -1.0, 0.0), 70.0],
			[&"forearm.R", Vector3(1.0, -0.3, 0.0), 60.0], [&"forearm.L", Vector3(-1.0, -0.3, 0.0), 60.0]]:
		var part := find_part(spec[0])
		if part != null:
			_panoramic_camera(StringName("%s camera" % spec[0]), part, spec[1], spec[2])


const GLOW_SHADER := preload("res://Entities/Vehicles/Components/Damage/Shader/sensor_glow.gdshader")


## The cameras sit where the suit scene's CameraMarkers put them (Cameras/Attach_<bone>/…):
## the camera's position, its facing (−Z) and its lens light. A painted lens makes its green
## paint on the part's mesh glow (an overlay), instead of a light.
func _place_cameras() -> void:
	_glow_slots.clear()
	var sensors := _comp(SensorSuite) as SensorSuite
	var to_body := _body.global_transform.affine_inverse()
	for node in _vehicle.find_children("*", "Marker3D", true, false):
		var m := node as CameraMarker
		if m == null:
			continue
		var c := _find_component(m.camera)
		if c == null:
			push_warning("CameraMarker %s: no camera '%s'" % [m.name, m.camera])
			continue
		c.markers.append(m)
		var attach := m.get_parent() as BoneAttachment3D
		var part := find_part(attach.bone_name) if attach != null else null
		if not m.glow_only:
			c.node = m
			c.local = Vector3.ZERO
			c.bone = -1
			if part != null:
				c.part = part
			if c.kind != Kind.EYES:
				c.facing = (to_body.basis * -m.global_basis.z).normalized()
			if c.kind == Kind.BODY_CAMERA and c.ref is SensorSuite and c.index >= 0:
				sensors.body_camera_positions[c.index] = to_body * m.global_position
				if c.index < sensors.body_camera_facings.size():
					sensors.body_camera_facings[c.index] = c.facing
		if m.is_painted() and part != null and part.mesh != null:
			_add_glow(part.mesh, m)
		m.set_alive(c.alive)


func _add_glow(mesh: MeshInstance3D, m: CameraMarker) -> void:
	var mat := mesh.material_overlay as ShaderMaterial
	if mat == null or mat.shader != GLOW_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = GLOW_SHADER
		var src := mesh.get_active_material(0) as BaseMaterial3D
		if src != null:
			mat.set_shader_parameter(&"albedo_texture", src.albedo_texture)
		mat.set_meta(&"rects", PackedVector4Array())
		mat.set_meta(&"energy", PackedFloat32Array())
		mesh.material_overlay = mat
	var rects: PackedVector4Array = mat.get_meta(&"rects")
	var energy: PackedFloat32Array = mat.get_meta(&"energy")
	for r in m.painted_uv:
		if rects.size() >= 8:
			break
		_glow_slots[m] = _glow_slots.get(m, []) + [[mat, rects.size()]]
		rects.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		energy.append(m.brightness)
	mat.set_meta(&"rects", rects)
	mat.set_meta(&"energy", energy)
	_upload_glow(mat)


func _upload_glow(mat: ShaderMaterial) -> void:
	var rects: PackedVector4Array = mat.get_meta(&"rects")
	var energy: PackedFloat32Array = mat.get_meta(&"energy")
	mat.set_shader_parameter(&"lens_count", rects.size())
	mat.set_shader_parameter(&"lens_rect", rects)
	mat.set_shader_parameter(&"lens_energy", energy)


## A camera's lens lights (and painted lenses) lit or dark.
func _light_camera(c: Component, alive: bool) -> void:
	for m in c.markers:
		if not is_instance_valid(m):
			continue
		m.set_alive(alive)
		for slot in _glow_slots.get(m, []):
			var mat: ShaderMaterial = slot[0]
			var energy: PackedFloat32Array = mat.get_meta(&"energy")
			energy[slot[1]] = m.brightness if alive else 0.0
			mat.set_meta(&"energy", energy)
			_upload_glow(mat)


func _find_component(cname: StringName) -> Component:
	for c in components:
		if c.name == cname:
			return c
	return null


func _panoramic_camera(cname: StringName, part: Part, facing: Vector3, half_deg: float) -> Component:
	var c := _bone_component(Kind.BODY_CAMERA, cname, part, part.aabb.get_center(), 0.35)
	c.facing = facing.normalized()
	c.half_deg = half_deg
	return c


## The cameras still giving a picture: [world direction, cos of half field, grade] each,
## for the panoramic screen's coverage (0 grade: the head's main camera).
func get_camera_cones() -> Array:
	var out: Array = []
	if not _built:
		return out
	var basis := _body.global_basis
	for c in components:
		if not c.alive or c.facing == Vector3.ZERO or (c.part != null and c.part.severed):
			continue
		if c.kind != Kind.EYES and c.kind != Kind.BODY_CAMERA:
			continue
		# A camera on a marker turns with its bone (a forearm camera with the arm).
		var dir := (basis * c.facing).normalized()
		if c.kind != Kind.EYES and c.node is CameraMarker:
			dir = -c.node.global_basis.z
		out.append([dir, cos(deg_to_rad(c.half_deg)), c.grade])
	return out


## `node`'s meshes show on the panoramic screen (no camera sees past it any more), or not.
func set_opaque(node: Node, opaque: bool) -> void:
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var vi := child as VisualInstance3D
		vi.layers = (vi.layers | Layers.SENSOR_OPAQUE) if opaque else (vi.layers & ~Layers.SENSOR_OPAQUE)
	if opaque:
		_opaque.append(node)


## The shield's camera was shot out: the shield stops being see-through.
func shield_camera_lost(shield: MsShield) -> void:
	set_opaque(shield, true)
	_event("shield camera out")
	component_destroyed.emit(&"camera", &"shield camera")


func _nearest_part(world: Vector3) -> Part:
	var best: Part = null
	var best_d := INF
	for p in parts:
		if p.equipment != null:
			continue
		var c := _skel.global_transform * FinalPoses.of(_skel).pose(p.bone) * p.aabb.get_center()
		var d := c.distance_to(world)
		if d < best_d:
			best_d = d
			best = p
	return best


# --- Frames ---

func _part_frame(p: Part) -> Transform3D:
	if p.equipment != null:
		return p.equipment.global_transform
	return _skel.global_transform * FinalPoses.of(_skel).pose(p.bone)


func _component_frame(c: Component) -> Transform3D:
	if c.node != null:
		return c.node.global_transform
	if c.bone >= 0:
		return _skel.global_transform * FinalPoses.of(_skel).pose(c.bone)
	return _body.global_transform


func component_position(c: Component) -> Vector3:
	return _component_frame(c) * (c.box.get_center() if c.is_box else c.local)


# --- Beams ---

## One tick of a beam on the suit (ProjectileManager.BeamContact).
func beam_contact(contact: ProjectileManager.BeamContact) -> void:
	var __t := Time.get_ticks_usec()
	beam_contact_body(contact)
	_time(&"beam_contact", __t)


func beam_contact_body(contact: ProjectileManager.BeamContact) -> void:
	if not enabled:
		if not _drills.has(contact.key):
			_drills[contact.key] = Drill.new()
			hit.emit(contact.point, contact.direction)
		(_drills[contact.key] as Drill).last = _clock
		contact.absorbed = contact.energy
		return
	if not _built or reactor_gone:
		contact.through = true
		contact.exit_point = contact.point
		return
	var d: Drill = _drills.get(contact.key)
	if d == null:
		d = _start_drill(contact)
		if d == null:
			contact.through = true
			contact.exit_point = contact.point
			return
		_drills[contact.key] = d
	d.last = _clock
	if not d.counted:
		d.counted = true
		var xf := _body.global_transform
		hit.emit(xf * (d.from_body + d.dir_body * d.t0), xf.basis * d.dir_body)
	if d.done:
		contact.through = true
		contact.absorbed = 0.0
		contact.exit_point = _drill_point(d, d.t_end + 0.05)
		return
	var left := _feed(d, contact.energy * COUPLING)
	if d.done:
		contact.through = true
		contact.absorbed = contact.energy - left / COUPLING
		contact.exit_point = _drill_point(d, d.t_end + 0.05)
	else:
		contact.absorbed = contact.energy
		contact.front = _drill_point(d, _drill_t(d))


func _drill_point(d: Drill, t: float) -> Vector3:
	return _body.global_transform * (d.from_body + d.dir_body * t)


func _drill_t(d: Drill) -> float:
	if d.pos >= d.kg.size():
		return d.t_end
	return d.t0 + (d.pos + d.spare / maxf(d.kg[d.pos], 1e-6)) * STEP


## What lies along the beam's line through the suit: hulls and equipment in order, the
## column mass per STEP, and the components it will reach.
func _start_drill(contact: ProjectileManager.BeamContact) -> Drill:
	var dir := contact.direction.normalized()
	var from := contact.point - dir * 30.0
	var spans := _hull_spans(from, dir, 100.0)
	for p in parts:
		if p.equipment == null or p.severed or not p.equipment.is_visible_in_tree():
			continue
		var t := _equipment_span(p, from, dir, 0.0)
		if t.x >= 0.0:
			spans.append([p, t.x, t.y])
	if spans.is_empty():
		return null
	spans.sort_custom(func(x: Array, y: Array) -> bool: return x[1] < y[1])
	var d := Drill.new()
	d.key = contact.key
	d.radius = contact.radius
	var area := PI * d.radius * d.radius
	d.t0 = spans[0][1]
	for s in spans:
		d.t_end = maxf(d.t_end, s[2])
		d.segs.append([s[0], s[1], s[2], null, false])
	var xf_inv := _body.global_transform.affine_inverse()
	d.from_body = xf_inv * from
	d.dir_body = (xf_inv.basis * dir).normalized()
	# Tank cells on the line.
	var fill := _reaction.get_fill() if _reaction != null else 1.0
	var cells: Array = []
	for c in components:
		if c.kind != Kind.TANK or not c.alive or (c.part != null and c.part.severed):
			continue
		var t := _ray_box(_component_frame(c), c.box, from, dir)
		if t.x >= 0.0:
			cells.append([c, t.x, t.y])
	# Holes already in each part on the line: what lies inside an old channel is gone.
	var old := {}   ## Part → [world → part transform, holes]
	for sp in spans:
		var p: Part = sp[0]
		if p.mesh != null and not old.has(p):
			var hs := holes.get_holes(p.mesh)
			if not hs.is_empty():
				old[p] = [_part_frame(p).affine_inverse(), hs]
	var n := ceili((d.t_end - d.t0) / STEP)
	d.kg.resize(n)
	d.cells.resize(n)
	var seg_kg := PackedFloat32Array()
	seg_kg.resize(spans.size())
	for i in n:
		var tc := d.t0 + (i + 0.5) * STEP
		var at := from + dir * tc
		var kg := 0.0
		for k in spans.size():
			var sp: Array = spans[k]
			if tc >= sp[1] and tc <= sp[2]:
				var p: Part = sp[0]
				var solid := 1.0 - (_channel_share(old[p], at, d.radius) if old.has(p) else 0.0)
				kg += p.density * STEP * area * solid
				seg_kg[k] += p.density * STEP * area * solid
		for cell in cells:
			if tc >= cell[1] and tc <= cell[2]:
				kg += WATER_DENSITY * fill * STEP * area
				d.cells[i] = cell[0]
		d.kg[i] = kg
	# A part the line only crosses through its old channels gets no new hole.
	for k in spans.size():
		var p: Part = spans[k][0]
		var full := p.density * (float(spans[k][2]) - float(spans[k][1])) * area
		if seg_kg[k] < full * 0.08:
			d.segs[k][4] = true
			d.segs[k][3] = &"open"
	# Components the drilled cylinder reaches.
	for c in components:
		if not c.alive or c.kind == Kind.TANK or (c.part != null and c.part.severed):
			continue
		if c.kind == Kind.EQUIPMENT and not (c.ref as MsEquipment).is_visible_in_tree():
			continue
		var t := _component_t(c, from, dir, d.radius)
		if t > -INF and t <= d.t_end + 3.0 and t >= d.t0 - 3.0:
			d.events.append([t, c])
	d.events.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return d


## Share of a beam's disc (radius `r`, its axis at `at`, world) that lies inside one of
## `info`'s old channels ([world → part, holes]): 1 = all of it already drilled away.
static func _channel_share(info: Array, at: Vector3, r: float) -> float:
	var q: Vector3 = (info[0] as Transform3D) * at
	var best := 0.0
	for h: HoleSet.Hole in info[1]:
		if h.s_drill < 0.0:
			continue   # a scorch mark, not a channel
		var rel := q - h.origin
		var s := rel.dot(h.axis)
		if s < h.s_in - r or s > h.s_drill + r * 0.25:
			continue
		var dd := (rel - h.axis * s).length()
		best = maxf(best, clampf((h.radius + r - dd) / (2.0 * r), 0.0, 1.0))
	return best


## [part, t_in, t_out] for every hull of this suit on the line from `from` along `dir`.
func _hull_spans(from: Vector3, dir: Vector3, length: float) -> Array:
	var space := _body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, Layers.PHYS_DAMAGE)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var excl: Array[RID] = []
	var found: Array = []
	for _i in 48:
		q.exclude = excl
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		excl.append(r.rid)
		var p: Part = _part_of_rid.get(r.rid)
		if p != null and not p.severed:
			found.append([p, from.distance_to(r.position), r.rid])
	var out: Array = []
	var back := PhysicsRayQueryParameters3D.create(from + dir * length, from, Layers.PHYS_DAMAGE)
	back.collide_with_areas = true
	back.collide_with_bodies = false
	for f in found:
		var others: Array[RID] = []
		for rid in excl:
			if rid != f[2]:
				others.append(rid)
		back.exclude = others
		var r := space.intersect_ray(back)
		var t_out: float = from.distance_to(r.position) if not r.is_empty() else f[1] + 0.2
		out.append([f[0], f[1], maxf(t_out, f[1] + 0.05)])
	return out


## Where a ray enters the first of `p`'s mesh boxes and leaves the last (grown by `grow`).
func _equipment_span(p: Part, from: Vector3, dir: Vector3, grow: float) -> Vector2:
	var t0 := INF
	var t1 := -INF
	for b in p.boxes:
		var mi := b[0] as MeshInstance3D
		if not is_instance_valid(mi) or not mi.is_visible_in_tree():
			continue
		var t := _ray_box(mi.global_transform, (b[1] as AABB).grow(grow), from, dir)
		if t.x >= 0.0:
			t0 = minf(t0, t.x)
			t1 = maxf(t1, t.y)
	if p.boxes.is_empty():
		return _ray_box(p.equipment.global_transform, p.box.grow(grow), from, dir)
	return Vector2(t0, t1) if t0 < INF else Vector2(-1, -1)


## Entry and exit distances of a ray through a box (Vector2(-1, -1): misses).
static func _ray_box(frame: Transform3D, box: AABB, from: Vector3, dir: Vector3) -> Vector2:
	var inv := frame.affine_inverse()
	var o := inv * from
	var v := inv.basis * dir
	var t0 := -INF
	var t1 := INF
	for ax in 3:
		if absf(v[ax]) < 1e-9:
			if o[ax] < box.position[ax] or o[ax] > box.end[ax]:
				return Vector2(-1, -1)
			continue
		var a := (box.position[ax] - o[ax]) / v[ax]
		var b := (box.end[ax] - o[ax]) / v[ax]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	if t1 < maxf(t0, 0.0):
		return Vector2(-1, -1)
	return Vector2(maxf(t0, 0.0), t1)


## Where along the line the drilled cylinder reaches `c`, or -INF if it misses.
func _component_t(c: Component, from: Vector3, dir: Vector3, beam_radius: float) -> float:
	var xf := _component_frame(c)
	if c.kind == Kind.EQUIPMENT and c.part != null:
		var te := _equipment_span(c.part, from, dir, beam_radius * 0.5)
		return te.x if te.x >= 0.0 else -INF
	if c.is_box:
		var grown := c.box.grow(beam_radius * 0.5)
		var t := _ray_box(xf, grown, from, dir)
		return t.x if t.x >= 0.0 else -INF
	var a := xf * c.local
	if c.capsule:
		var b := xf * c.tip
		# Closest approach between the line and the segment a-b.
		var best := INF
		var best_t := 0.0
		for k in 9:
			var p := a.lerp(b, k / 8.0)
			var t := (p - from).dot(dir)
			var dist := (from + dir * t).distance_to(p)
			if dist < best:
				best = dist
				best_t = t
		return best_t if best <= c.radius + beam_radius else -INF
	var t := (a - from).dot(dir)
	var dist := (from + dir * t).distance_to(a)
	return t if dist <= c.radius + beam_radius else -INF


## Spends `coupled` J on the column; returns what is left once through.
func _feed(d: Drill, coupled: float) -> float:
	var kg_left := coupled / REMOVAL_ENERGY
	while d.pos < d.kg.size():
		var need := d.kg[d.pos] - d.spare
		var take := minf(kg_left, need)
		var cell: Component = d.cells[d.pos]
		if cell != null:
			d.deposited[cell] = d.deposited.get(cell, 0.0) + take * REMOVAL_ENERGY
			if cell.alive and not d.due.has(cell):
				d.due[cell] = true
				_burst_cell_later(d, cell)
		if kg_left < need:
			d.spare += kg_left
			kg_left = 0.0
			break
		kg_left -= need
		d.spare = 0.0
		d.pos += 1
	if d.pos >= d.kg.size():
		d.done = true
	_advance(d, _drill_t(d) if not d.done else d.t_end + 3.0)
	return kg_left * REMOVAL_ENERGY


## The drill face reached `t`: holes in every part it entered, components it got to.
func _advance(d: Drill, t: float) -> void:
	var xf := _body.global_transform
	for seg in d.segs:
		var p: Part = seg[0]
		if p.severed or t < seg[1]:
			continue
		var chord: float = seg[2] - seg[1]
		if seg[3] is StringName:
			continue
		if seg[3] == null and p.mesh != null:
			var entry: Vector3 = xf * (d.from_body + d.dir_body * float(seg[1]))
			seg[3] = holes.add_hole(p.mesh, _skel, p.bone, entry, xf.basis * d.dir_body, d.radius, chord)
			_knock_stubs(p, entry, xf.basis * d.dir_body, chord, d.radius)
			(seg[3] as HoleSet.Hole).shell = _skin_shells(p, entry, xf.basis * d.dir_body, chord)
			part_damaged.emit(p.name)
			var fx := DamageFx.of(self)
			if fx != null:
				fx.drill_in(entry, xf.basis * d.dir_body, _body.linear_velocity, d.radius, p.area)
		var drilled := clampf(t - float(seg[1]), 0.0, chord)
		if seg[3] != null:
			(seg[3] as HoleSet.Hole).s_drill = chord if drilled >= chord - 1e-3 else drilled
		if drilled >= chord - 1e-3 and not seg[4]:
			seg[4] = true
			if seg[3] is HoleSet.Hole:
				var h := seg[3] as HoleSet.Hole
				p.last_hole = h.origin + h.axis * (h.s_in + h.s_out) * 0.5
				p.has_hole = true
			var mid_t := (float(seg[1]) + float(seg[2])) * 0.5
			_through_part(p, d, chord, xf * (d.from_body + d.dir_body * mid_t),
					xf * (d.from_body + d.dir_body * float(seg[2])))
			var fx := DamageFx.of(self)
			if fx != null and p.mesh != null:
				fx.blow_out(xf * (d.from_body + d.dir_body * float(seg[2])), xf.basis * d.dir_body,
						_body.linear_velocity, d.radius, p.area)
	while d.next_event < d.events.size() and d.events[d.next_event][0] <= t:
		var c: Component = d.events[d.next_event][1]
		d.next_event += 1
		if c.alive:
			_hit_component(c, d)


## Share of `p`'s cross-section a hole of `radius` takes over `chord` m of it.
static func _hole_share(p: Part, radius: float, chord: float) -> float:
	return 2.0 * radius * minf(chord, p.width) / p.section


## The beam came out of `p`'s far side: the cross-section it took, its actuators.
func _through_part(p: Part, d: Drill, chord: float, mid := Vector3.INF, exit := Vector3.INF) -> void:
	_remove_section(p, _hole_share(p, d.radius, chord))
	if p.equipment == null:
		_hit_joints(p, 0.6)
		if mid != Vector3.INF:
			_minovsky_rupture(p, mid, exit, _body.global_basis * d.dir_body)


## The beam cut the Minovsky lines in `p` (the generator's particles run through the whole
## body as its high-power hydraulics and power): they rupture a moment later at `at` (world),
## a burst with fire and smoke, and the cut line leaks smoke from `exit` for a while.
func _minovsky_rupture(p: Part, at: Vector3, exit: Vector3, dir: Vector3) -> void:
	var energy := _rng.randf_range(2e7, 6e7) * clampf(p.dry / 1500.0, 0.4, 1.6)
	_later(0.03 + _rng.randf() * 0.12, func() -> void:
		if reactor_gone or p.severed:
			return
		_burst(at, energy, &"minovsky", 1)
		var fx := DamageFx.of(self)
		if fx != null and exit != Vector3.INF and p.area != null:
			var inv := p.area.global_transform.affine_inverse()
			fx.smoke_leak(p.area, inv * exit, (inv.basis * dir).normalized(), _rng.randf_range(5.0, 9.0)))


## A drill that ended (no contact for a while): partial holes cost their share too.
func _finish(d: Drill) -> void:
	for seg in d.segs:
		if seg[4] or seg[3] == null or seg[3] is StringName:
			continue
		var p: Part = seg[0]
		var chord: float = seg[2] - seg[1]
		var hh := seg[3] as HoleSet.Hole
		var frac := hh.s_drill / maxf(chord, 0.01)
		if frac > 0.3 and p.equipment == null:
			# Stopped deep inside: the lines it reached still rupture there.
			var face: Vector3 = _part_frame(p) * (hh.origin + hh.axis * hh.s_drill)
			_minovsky_rupture(p, face, Vector3.INF, Vector3.ZERO)
		p.last_hole = hh.origin + hh.axis * hh.s_drill * 0.5
		p.has_hole = true
		_remove_section(p, _hole_share(p, d.radius, chord) * frac)
		if frac > 0.5 and p.equipment == null:
			_hit_joints(p, 0.3)


func _remove_section(p: Part, share: float) -> void:
	if p.severed:
		return
	p.left -= share
	# Too little left to feed or hold them: the part's thrusters go with it.
	if p.left < THRUSTER_LEFT:
		for c in components:
			if c.part == p and c.kind == Kind.THRUSTER and c.alive:
				_kill_component(c, true)
	if p.equipment != null:
		if p.left < BREAK_LEFT:
			_break_equipment(p.equipment)
	elif not CORE_PARTS.has(p.name) and p.left < (BREAK_LEFT if p.limb else 0.0):
		_later(0.03, func() -> void: sever(p))
	elif p.limb and p.left < SNAP_LEFT and not _snapping.has(p):
		# Too little left to hold: it groans at the wound and goes.
		_snapping[p] = true
		_groan(p)
		_later(_rng.randf_range(0.3, 1.2), func() -> void:
			_snapping.erase(p)
			if not p.severed:
				_groan(p)
				sever(p))


## Weakened limbs carry the suit's acceleration through what is left of them: the load at the
## wound (linear + angular acceleration there) against a limit that falls with the section lost,
## the suit's full boost acceleration at STRESS_LEFT, nothing at BREAK_LEFT.
func _stress(delta: float) -> void:
	var v := _body.linear_velocity
	var w := _body.angular_velocity
	if _last_v == Vector3.INF or delta <= 0.0:
		_last_v = v
		_last_w = w
		return
	# Smoothed over ~0.1 s: a single tick's jolt (an impulse, a contact) isn't a sustained load.
	var k := 1.0 - exp(-delta / 0.1)
	_accel = _accel.lerp((v - _last_v) / delta, k)
	_alpha = _alpha.lerp((w - _last_w) / delta, k)
	var a := _accel
	var alpha := _alpha
	_last_v = v
	_last_w = w
	if reactor_gone or _boost_accel <= 0.0:
		return
	var com := _body.global_transform * _body.center_of_mass
	for p in parts:
		if not p.limb or p.severed or p.equipment != null or p.left >= STRESS_LEFT or _snapping.has(p):
			continue
		var at := _part_frame(p) * (p.last_hole if p.has_hole else p.aabb.get_center())
		var r := at - com
		var load := (a + alpha.cross(r) + w.cross(w.cross(r))).length()
		var limit := _boost_accel * (p.left - BREAK_LEFT) / (STRESS_LEFT - BREAK_LEFT)
		if load > limit:
			_snapping[p] = true
			_groan(p)
			_later(0.05, func() -> void:
				_snapping.erase(p)
				if not p.severed:
					_event("%s snapped under load" % p.name)
					sever(p, false))


## A weakened limb straining at its wound: sparks and arcs.
func _groan(p: Part) -> void:
	var fx := DamageFx.of(self)
	if fx == null:
		return
	var at := _part_frame(p) * (p.last_hole if p.has_hole else p.aabb.get_center())
	fx.creak(at, _velocity_at(at), p.width)


func _hit_joints(p: Part, chance: float) -> void:
	var ambac := _comp(AmbacController) as AmbacController
	if ambac == null:
		return
	for j in ambac.joints:
		if j.bone_name == p.name and j.priority > 0.0 and _rng.randf() < chance:
			_saved_priority[j] = j.priority
			j.priority = 0.0
			_joint_out[p.name] = true
			_event("%s actuator out" % p.name)
	_update_control()


func _hit_component(c: Component, d: Drill) -> void:
	match c.kind:
		Kind.PILOT:
			_event("PILOT HIT")
			_kill_pilot()
		Kind.COCKPIT:
			# Where the beam's line crosses the cockpit's sphere: the screen's two holes.
			var centre := component_position(c)
			var o := _drill_point(d, 0.0)
			var dir := _body.global_basis * d.dir_body
			var along := (centre - o).dot(dir)
			var miss := (o + dir * along).distance_to(centre)
			var half := sqrt(maxf(c.radius * c.radius - miss * miss, 0.0))
			cockpit_holed.emit(o + dir * (along - half), o + dir * (along + half))
			_hole_cockpit(o, dir, d.radius)
			_event("cockpit holed")
		Kind.REACTOR:
			c.alive = false
			_event("REACTOR HIT")
			_later(0.04, _breach_reactor)
		Kind.THRUSTER:
			_kill_component(c)
		Kind.EYES, Kind.BODY_CAMERA, Kind.VULCAN:
			_kill_component(c)
		Kind.EQUIPMENT:
			_break_equipment(c.ref as MsEquipment)


func _kill_component(c: Component, dead := false) -> void:
	if not c.alive:
		return
	c.alive = false
	_light_camera(c, false)
	match c.kind:
		Kind.THRUSTER:
			_hit_thruster(c, dead)
			_capability_changed()
			return
		Kind.EYES:
			var sensors := _comp(SensorSuite) as SensorSuite
			if sensors != null:
				sensors.main_camera_alive = false
		Kind.BODY_CAMERA:
			if c.ref is SensorSuite:
				(c.ref as SensorSuite).body_camera_dead[c.index] = true
		Kind.VULCAN:
			(c.ref as MsWeapon).broken = true
	_event("%s out" % c.name)
	component_destroyed.emit(KIND_NAMES[c.kind], c.name)


## Equipment that went with a severed part: gone, but its stores didn't go off.
## A thruster hit (or gone with its part): out, it can't be fired.
func _hit_thruster(c: Component, _dead: bool) -> void:
	var t := c.ref as Thruster
	if not _thruster_saved.has(t):
		_thruster_saved[t] = [t.max_thrust, t.gimbal_limit_deg, t.gimbal_pitch_limit_deg, t.gimbal_yaw_limit_deg]
	# A hit thruster is out: it can't be fired (user's call, 2026-11-27; derated and stuck-nozzle
	# outcomes dropped).
	t.shut_down()
	var what := "dead"
	_event("%s %s" % [c.name, what])
	component_destroyed.emit(&"thruster", StringName("%s %s" % [c.name, what]))


func _lose_equipment(eq: MsEquipment) -> void:
	for c in components:
		if c.kind == Kind.EQUIPMENT and c.ref == eq:
			c.alive = false
	for p in parts:
		if p.equipment == eq:
			p.severed = true
	var fcs := _comp(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			if w.equipment == eq:
				w.broken = true


func _break_equipment(eq: MsEquipment) -> void:
	for c in components:
		if c.kind == Kind.EQUIPMENT and c.ref == eq:
			if not c.alive:
				return
			c.alive = false
	var fcs := _comp(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			if w.equipment == eq:
				w.broken = true
	_event("%s destroyed" % eq.name)
	component_destroyed.emit(&"equipment", eq.name)
	set_opaque(eq, true)   # its camera went with it: it shows on the screen now
	var stores: float = STORES.get(StringName(eq.name), 0.0)
	if stores > 0.0:
		var at := eq.global_transform * MsLoadout.local_box(eq).get_center()
		_later(0.05, func() -> void: _burst(at, stores, &"stores"))


func _burst_cell_later(d: Drill, cell: Component) -> void:
	_later(0.03, func() -> void:
		if not cell.alive:
			return
		cell.alive = false
		var e: float = d.deposited.get(cell, 0.0)
		_event("%s burst" % cell.name)
		component_destroyed.emit(&"tank", cell.name)
		var at := component_position(cell)
		_burst(at, maxf(e, 5e7), &"steam")
		_vent(cell, at, _body.global_basis * d.dir_body))


# --- Bursts, reactor, pilot ---

## A tank cell holed at `at`: it empties through the hole like a nozzle, F ≈ 2·Cd·P·A
## (~0.4 MN, physics.md §5) for the fraction of a second the water lasts, out along the side
## the beam came out of; then the cut feed line leaks weakly for a while.
func _vent(cell: Component, at: Vector3, beam_dir: Vector3) -> void:
	if cell.part == null or cell.part.area == null:
		return
	var anchor := cell.part.area
	var centre := _part_frame(cell.part) * cell.part.aabb.get_center()
	var out := (beam_dir.normalized() + (at - centre).normalized() * 0.5).normalized()
	var surface := _surface_toward(cell.part, at, out)
	if surface != Vector3.INF:
		at = surface
	var inv := anchor.global_transform.affine_inverse()
	var local_at := inv * at
	var local_dir := (inv.basis * out).normalized()
	var fill := _reaction.get_fill() if _reaction != null else 1.0
	var cell_kg := cell.part.tank * fill / 4.0
	var force := 2.0 * 0.6 * 3.0e5 * 1.13
	var lasts := clampf(cell_kg * 25.0 / force, 0.02, 0.5)
	_leaks.append([anchor, local_at, local_dir, force, _clock + lasts])
	_leaks.append([anchor, local_at, local_dir, 4000.0, _clock + 15.0])
	var fx := DamageFx.of(self)
	if fx != null:
		fx.vent(anchor, local_at, local_dir, lasts, 1.0)
		fx.vent(anchor, local_at, local_dir, 15.0, 0.2)


## Something went off inside the suit at `at` (world) with `energy` J: what is within its
## blow-off radius is torn (parts lose section, thin components are destroyed). Steam from a
## tank cell, an E-pac, electronics.
func _burst(at: Vector3, energy: float, kind: StringName, max_panels := 3) -> void:
	if reactor_gone:
		return
	var r := BLAST_K * pow(energy, 1.0 / 3.0)
	var fx := DamageFx.of(self)
	if fx != null:
		fx.burst(at, _body.linear_velocity, r, kind)
	for p in parts:
		if p.severed:
			continue
		var centre := _part_frame(p) * (p.box.get_center() if p.equipment != null else p.aabb.get_center())
		var reach := r + p.width * 0.5
		var dist := centre.distance_to(at)
		if dist < reach:
			if p.equipment == null:
				var local := _part_frame(p).affine_inverse() * at
				p.last_hole = local.clamp(p.aabb.position, p.aabb.end)
				p.has_hole = true
			# The blast tears what lies within it: about its swept disc of the section.
			_remove_section(p, minf(PI * r * r * 0.35 / p.section, 1.2) * (1.0 - dist / reach))
	for c in components:
		if not c.alive or c.kind == Kind.TANK or c.kind == Kind.REACTOR or c.kind == Kind.COCKPIT:
			continue
		var dist := component_position(c).distance_to(at)
		if c.kind == Kind.PILOT:
			if dist < r * 0.6:
				_kill_pilot()
			continue
		if dist < r + c.radius:
			if c.kind == Kind.EQUIPMENT:
				_break_equipment(c.ref as MsEquipment)
			else:
				_kill_component(c)
	# Armour panels torn off by it: the nearest few parts, facing the burst.
	if energy >= 5e6:
		var near: Array = []
		for p in parts:
			if p.severed or p.equipment != null or p.mesh == null:
				continue
			var centre := _part_frame(p) * p.aabb.get_center()
			var dist := centre.distance_to(at)
			if dist < r + p.width * 0.6:
				near.append([dist, p, centre])
		near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for k in mini(near.size(), max_panels):
			var p: Part = near[k][1]
			var centre: Vector3 = near[k][2]
			var out := (at - centre).normalized() if at.distance_to(centre) > 0.2 else (at - _body.global_position).normalized()
			var radius := clampf(r * (1.0 - float(near[k][0]) / (r + p.width * 0.6)), 0.3, p.width * 0.45)
			var speed := clampf(sqrt(energy / 2.0e5), 8.0, 120.0)
			# One panel per physics tick: each costs several ms to cut.
			_later(k * 0.017, func() -> void:
				if not p.severed and not reactor_gone:
					_blow_panel(p, at, out, radius, speed))
	# Panels blown off carry momentum out: the suit gets the opposite, small.
	var push := sqrt(2.0 * 150.0 * energy) * 0.15
	var away := (_body.global_transform * _body.center_of_mass - at)
	if away.length() > 0.01:
		_body.apply_impulse(away.normalized() * push, at - _body.global_position)


## The beam's line through the cockpit: every interior mesh on it gets a through-hole (in its
## own frame: it rides the cockpit's gimbal), so with the screen and the chest holed the pilot
## sees out. Meshes with their own shaders are left whole.
func _hole_cockpit(origin: Vector3, dir: Vector3, radius: float) -> void:
	var cockpit := _vehicle.get_cockpit()
	if cockpit == null:
		return
	var screen := cockpit.get_panoramic_screen()
	for node in cockpit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or (screen != null and screen.is_ancestor_of(mi)):
			continue
		if mi.skin != null:
			continue   # the pilot
		var plain := true
		for si in mi.mesh.get_surface_count():
			if not (mi.get_active_material(si) is BaseMaterial3D):
				plain = false
		if not plain:
			continue
		var t := _ray_box(mi.global_transform, mi.get_aabb().grow(radius), origin, dir)
		if t.x < 0.0:
			continue
		var entry := origin + dir * t.x
		var h := holes.add_hole(mi, null, -1, entry, dir, radius, maxf(t.y - t.x, 0.1), 1900.0)
		h.s_drill = h.s_out


## Tears an armour panel off `p`: the hull surface from `inside` toward `out`, `radius` m
## across. The part gets a short through-hole there (the opening, with the plate's torn edge);
## the mesh inside that outline is cut out, split into 2-3 jagged plates with thickness, and
## thrown off at `speed`.
func _blow_panel(p: Part, inside: Vector3, out: Vector3, radius: float, speed: float) -> void:
	var __t := Time.get_ticks_usec()
	_blow_panel_body(p, inside, out, radius, speed)
	_time(&"_blow_panel", __t)


func _blow_panel_body(p: Part, inside: Vector3, out: Vector3, radius: float, speed: float) -> void:
	var found := _panel_pieces(p, inside, out, radius)
	if found.is_empty():
		return
	var skin: float = found[0]
	var thickness := 0.35
	var h := holes.add_hole(p.mesh, _skel, p.bone, inside + out * (skin + thickness), -out, radius, thickness * 2.0, 1150.0)
	h.s_drill = h.s_out
	h.shell = _skin_shells(p, inside + out * (skin + thickness), -out, thickness * 2.0)
	for k in range(1, found.size()):
		_launch_plate(found[k], out, speed)
	_knock_stubs(p, inside + out * (skin + thickness), -out, thickness * 2.0, radius)


## Where the line from `inside` along `dir` leaves `p`'s hull (world), or INF.
func _surface_toward(p: Part, inside: Vector3, dir: Vector3) -> Vector3:
	var space := _body.get_world_3d().direct_space_state
	var far := inside + dir * (p.width * 2.0 + 4.0)
	var q := PhysicsRayQueryParameters3D.create(far, inside, Layers.PHYS_DAMAGE)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var others: Array[RID] = []
	for rid in _area_rids:
		if rid != p.area.get_rid():
			others.append(rid)
	q.exclude = others
	var r := space.intersect_ray(q)
	return r.position if not r.is_empty() else Vector3.INF


## The outer skin of `p` around the line from `inside` along `out` (world), inside a ragged
## circle of `radius`, cut from the current pose, finely split, grouped into plates by
## nearest seed. Returns [how far out along the line the skin lies, plate, plate, …], each
## plate [triangles (world), normals, uvs, material]; empty if there is no skin there.
func _panel_pieces(p: Part, inside: Vector3, out: Vector3, radius: float) -> Array:
	if p.small_done:
		return _panel_pieces_small(p, inside, out, radius)
	var mesh_in_world := p.mesh.global_transform
	var e1 := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := out.cross(e1)
	# Candidate skin: outward-facing, around the line, in front of the burst.
	var cand: Array = []
	var max_along := -INF
	for si in p.mesh.mesh.get_surface_count():
		var arrays := arrays_of(p.mesh.mesh, si)
		var skinned := skin_surface(p.mesh, _skel, arrays)
		var verts: PackedVector3Array = skinned[0]
		var norms: PackedVector3Array = skinned[1]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var mat := p.mesh.mesh.surface_get_material(si)
		var world := PackedVector3Array()
		world.resize(verts.size())
		for i in verts.size():
			world[i] = mesh_in_world * verts[i]
		for t in range(0, idx.size(), 3):
			# Whole triangles first: facing out, in front of the burst, touching the circle.
			var a0 := world[idx[t]]
			var a1 := world[idx[t + 1]]
			var a2 := world[idx[t + 2]]
			var facing := 0.0
			for j in 3:
				var vi := idx[t + j]
				facing += (mesh_in_world.basis * (norms[vi] if vi < norms.size() else out)).dot(out)
			if facing < 0.0:
				continue
			var c3 := (a0 + a1 + a2) / 3.0
			var reach := maxf(c3.distance_to(a0), maxf(c3.distance_to(a1), c3.distance_to(a2)))
			var rel3 := c3 - inside
			var along3 := rel3.dot(out)
			if along3 < -0.3 - reach or (rel3 - out * along3).length() > radius * 1.2 + reach:
				continue
			var tri: Array = []
			for j in 3:
				var vi := idx[t + j]
				tri.append([world[vi], (mesh_in_world.basis * (norms[vi] if vi < norms.size() else out)).normalized(),
						uvs[vi] if vi < uvs.size() else Vector2.ZERO])
			for small in _split(tri, 0.45, 4):
				var c: Vector3 = ((small[0][0] as Vector3) + (small[1][0] as Vector3) + (small[2][0] as Vector3)) / 3.0
				var n: Vector3 = (small[0][1] as Vector3) + (small[1][1] as Vector3) + (small[2][1] as Vector3)
				var rel := c - inside
				var along := rel.dot(out)
				var flat := rel - out * along
				var ang := atan2(flat.dot(e2), flat.dot(e1))
				var wob := 1.0 + 0.11 * sin(5.0 * ang) + 0.06 * sin(11.0 * ang)
				if along < -0.3 or flat.length() > radius * wob or n.normalized().dot(out) < 0.15:
					continue
				cand.append([small, c, along, mat])
				max_along = maxf(max_along, along)
	if cand.is_empty():
		return []
	var skin_at := max_along
	var seeds: Array[Vector3] = []
	var centre := inside + out * skin_at
	for k in _rng.randi_range(2, 3):
		var ang := TAU * (k + _rng.randf() * 0.6) / 3.0
		seeds.append(centre + (e1 * cos(ang) + e2 * sin(ang)) * radius * _rng.randf_range(0.3, 0.7))
	# Plain arrays while filling (packed arrays inside an Array are copies).
	var groups: Array = []
	for k in seeds.size():
		groups.append([[], [], [], null])
	for cd in cand:
		if float(cd[2]) < skin_at - 0.9:
			continue   # an inner layer behind the outer skin
		var c: Vector3 = cd[1]
		var best := 0
		for k in seeds.size():
			if c.distance_to(seeds[k]) < c.distance_to(seeds[best]):
				best = k
		var g: Array = groups[best]
		for v in cd[0]:
			(g[0] as Array).append(v[0])
			(g[1] as Array).append(v[1])
			(g[2] as Array).append(v[2])
		if g[3] == null:
			g[3] = cd[3]
	var out_list: Array = [skin_at]
	for g in groups:
		if (g[0] as Array).size() >= 9:
			out_list.append([PackedVector3Array(g[0]), PackedVector3Array(g[1]), PackedVector2Array(g[2]), g[3]])
	return out_list


## _panel_pieces from the part's ready-split skin: the same choice, no splitting at the hit.
func _panel_pieces_small(p: Part, inside: Vector3, out: Vector3, radius: float) -> Array:
	var bone_xf := _skel.global_transform * FinalPoses.of(_skel).pose(p.bone)
	var to_bone := bone_xf.affine_inverse()
	var in_b := to_bone * inside
	var out_b := (to_bone.basis * out).normalized()
	var e1 := out_b.cross(Vector3.UP if absf(out_b.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := out_b.cross(e1)
	var pos := p.small_pos
	var nrm := p.small_nrm
	var cand: Array = []   # [triangle index, centre (bone space), along]
	var max_along := -INF
	for t in p.small_mat.size():
		var a := pos[t * 3]
		var c := (a + pos[t * 3 + 1] + pos[t * 3 + 2]) / 3.0
		var rel := c - in_b
		var along := rel.dot(out_b)
		if along < -0.3:
			continue
		var flat := rel - out_b * along
		var fl := flat.length()
		if fl > radius * 1.17:
			continue
		var ang := atan2(flat.dot(e2), flat.dot(e1))
		if fl > radius * (1.0 + 0.11 * sin(5.0 * ang) + 0.06 * sin(11.0 * ang)):
			continue
		if (nrm[t * 3] + nrm[t * 3 + 1] + nrm[t * 3 + 2]).normalized().dot(out_b) < 0.15:
			continue
		cand.append([t, c, along])
		max_along = maxf(max_along, along)
	if cand.is_empty():
		return []
	var skin_at := max_along
	var centre := in_b + out_b * skin_at
	var seeds: Array[Vector3] = []
	for k in _rng.randi_range(2, 3):
		var ang := TAU * (k + _rng.randf() * 0.6) / 3.0
		seeds.append(centre + (e1 * cos(ang) + e2 * sin(ang)) * radius * _rng.randf_range(0.3, 0.7))
	# Plain arrays while filling (a packed array taken out of an Array is a copy).
	var groups: Array = []
	for k in seeds.size():
		groups.append([[], [], [], null])
	var nb := bone_xf.basis
	for cd in cand:
		if float(cd[2]) < skin_at - 0.9:
			continue   # an inner layer behind the outer skin
		var c: Vector3 = cd[1]
		var best := 0
		for k in seeds.size():
			if c.distance_to(seeds[k]) < c.distance_to(seeds[best]):
				best = k
		var g: Array = groups[best]
		var t: int = cd[0]
		for j in 3:
			(g[0] as Array).append(bone_xf * pos[t * 3 + j])
			(g[1] as Array).append((nb * nrm[t * 3 + j]).normalized())
			(g[2] as Array).append(p.small_uv[t * 3 + j])
		if g[3] == null:
			g[3] = p.small_mat[t]
	var out_list: Array = [skin_at]
	for g in groups:
		if (g[0] as Array).size() >= 9:
			out_list.append([PackedVector3Array(g[0]), PackedVector3Array(g[1]), PackedVector2Array(g[2]), g[3]])
	return out_list


## Splits the parts' skins into small triangles (bone space), within `budget_us` per tick.
func _prep_small(budget_us: int) -> void:
	var t0 := Time.get_ticks_usec()
	# The meshes that may fly off (parts, equipment): their data read once and their hulls made,
	# a few per tick, so the first hit doesn't wait for the render thread.
	while not _prep_meshes.is_empty():
		var mesh: Mesh = _prep_meshes.pop_back()
		if is_instance_valid(mesh):
			for si in mesh.get_surface_count():
				arrays_of(mesh, si)
			hull_of(mesh)
		if Time.get_ticks_usec() - t0 > budget_us:
			return
	for p in parts:
		if p.small_done or p.mesh == null or p.equipment != null:
			continue
		var tris := _skin_tris(p)
		while p.small_next < tris.size():
			var tri: Array = tris[p.small_next]
			p.small_next += 1
			for small in _split(tri[0], 0.45, 4):
				for v in small:
					p.small_pos.append(v[0])
					p.small_nrm.append(v[1])
					p.small_uv.append(v[2])
				p.small_mat.append(tri[1])
			if Time.get_ticks_usec() - t0 > budget_us:
				return
		p.small_done = true
		_skin_tri_cache.erase(p)


var _prep_meshes: Array = []   ## meshes still to read and hull (after build)
var _skin_tri_cache := {}   ## Part → [[[pos, normal, uv] × 3], material] in bone space


func _skin_tris(p: Part) -> Array:
	if _skin_tri_cache.has(p):
		return _skin_tri_cache[p]
	var out: Array = []
	var to_bone := FinalPoses.of(_skel).pose(p.bone).affine_inverse() \
			* (_skel.global_transform.affine_inverse() * p.mesh.global_transform)
	for si in p.mesh.mesh.get_surface_count():
		var arrays := arrays_of(p.mesh.mesh, si)
		var skinned := skin_surface(p.mesh, _skel, arrays)
		var verts: PackedVector3Array = to_bone * (skinned[0] as PackedVector3Array)
		var norms: PackedVector3Array = Transform3D(to_bone.basis, Vector3.ZERO) * (skinned[1] as PackedVector3Array)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n_idx := idx.size() if not idx.is_empty() else verts.size()
		var mat := p.mesh.mesh.surface_get_material(si)
		for t in range(0, n_idx, 3):
			var tri: Array = []
			for j in 3:
				var vi := idx[t + j] if not idx.is_empty() else t + j
				tri.append([verts[vi], norms[vi].normalized() if vi < norms.size() else Vector3.UP,
						uvs[vi] if vi < uvs.size() else Vector2.ZERO])
			out.append([tri, mat])
	_skin_tri_cache[p] = out
	return out


## Splits a triangle ([[pos, normal, uv] × 3]) until its edges are shorter than `edge`.
static func _split(tri: Array, edge: float, depth: int) -> Array:
	var a: Array = tri[0]
	var b: Array = tri[1]
	var c: Array = tri[2]
	var lab := (a[0] as Vector3).distance_to(b[0])
	var lbc := (b[0] as Vector3).distance_to(c[0])
	var lca := (c[0] as Vector3).distance_to(a[0])
	if depth <= 0 or maxf(lab, maxf(lbc, lca)) <= edge:
		return [tri]
	var mid := func(u: Array, v: Array) -> Array:
		return [((u[0] as Vector3) + (v[0] as Vector3)) * 0.5, ((u[1] as Vector3) + (v[1] as Vector3)).normalized(),
				((u[2] as Vector2) + (v[2] as Vector2)) * 0.5]
	var ab: Array = mid.call(a, b)
	var bc: Array = mid.call(b, c)
	var ca: Array = mid.call(c, a)
	var out: Array = []
	for t in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
		out.append_array(_split(t, edge, depth - 1))
	return out


## One torn plate: its outer skin with the part's material, an inner face and torn side
## walls glowing hot, flying off.
func _launch_plate(piece: Array, out: Vector3, speed: float) -> void:
	var pos: PackedVector3Array = piece[0]
	var nrm: PackedVector3Array = piece[1]
	var uv: PackedVector2Array = piece[2]
	var centre := Vector3.ZERO
	for v in pos:
		centre += v
	centre /= pos.size()
	var thick := 0.14
	var local := Transform3D(Basis.IDENTITY, -centre) * pos
	var outer := ArrayMesh.new()
	var a1 := []
	a1.resize(Mesh.ARRAY_MAX)
	a1[Mesh.ARRAY_VERTEX] = local
	a1[Mesh.ARRAY_NORMAL] = nrm
	a1[Mesh.ARRAY_TEX_UV] = uv
	outer.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a1)
	if piece[3] != null:
		outer.surface_set_material(0, piece[3])
	# Inner face (the outer one pushed in, wound back) and the torn edges (edges used by one
	# triangle only), as one surface.
	var count := {}
	for t in range(0, local.size(), 3):
		for k in 3:
			var a := local[t + k]
			var b := local[t + (k + 1) % 3]
			var key := [a, b] if a < b else [b, a]
			count[key] = int(count.get(key, 0)) + 1
	var v2 := PackedVector3Array()
	var n2 := PackedVector3Array()
	for t in range(0, local.size(), 3):
		for k in [0, 2, 1]:
			v2.append(local[t + k] - nrm[t + k] * thick)
			n2.append(-nrm[t + k])
	for t in range(0, local.size(), 3):
		for k in 3:
			var a := local[t + k]
			var b := local[t + (k + 1) % 3]
			if int(count[[a, b] if a < b else [b, a]]) != 1:
				continue
			var n := (b - a).cross(out).normalized()
			var a2 := a - out * thick
			var b2 := b - out * thick
			for v in [a, b, b2, a, b2, a2]:
				v2.append(v)
				n2.append(n)
	var area := 0.0
	for t in range(0, pos.size(), 3):
		area += (pos[t + 1] - pos[t]).cross(pos[t + 2] - pos[t]).length() * 0.5
	var a2s := []
	a2s.resize(Mesh.ARRAY_MAX)
	a2s[Mesh.ARRAY_VERTEX] = v2
	a2s[Mesh.ARRAY_NORMAL] = n2
	outer.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2s)
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.07, 0.06, 0.055)
	edge_mat.metallic = 0.8
	edge_mat.roughness = 0.5
	edge_mat.emission_enabled = true
	edge_mat.emission = Color(1.0, 0.32, 0.05)
	edge_mat.emission_energy_multiplier = 2.5
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	outer.surface_set_material(1, edge_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = outer
	var body := RigidBody3D.new()
	body.name = "DebrisPlate"
	body.gravity_scale = 0.0
	body.mass = maxf(area * 400.0, 20.0)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.inertia = Vector3.ONE * body.mass * 0.5
	body.add_child(mi)
	_vehicle.get_parent().add_child(body)
	body.global_position = centre
	body.linear_velocity = _velocity_at(centre) + (out + (centre - _body.global_position).normalized() * 0.2).normalized() * speed \
			* _rng.randf_range(0.6, 1.2)
	body.angular_velocity = Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 2.5
	var tw := body.create_tween()
	tw.tween_property(edge_mat, "emission_energy_multiplier", 0.0, 18.0)
	_solidify(body)
	_debris.append(body)


func _kill_pilot() -> void:
	if pilot_dead:
		return
	pilot_dead = true
	destroyed = true
	# The flight computer outlives the pilot: it stops taking input and holds the suit (a tank
	# venting or a thruster lost to the same hit would otherwise leave it tumbling).
	var fc := _flight()
	if fc != null:
		fc.pilot_lost = true
	var fcs := _comp(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			w.broken = true
	_event("PILOT KIA")
	pilot_killed.emit()


func _reactor_position() -> Vector3:
	for c in components:
		if c.kind == Kind.REACTOR:
			return component_position(c)
	return _body.global_transform * _body.center_of_mass


func _breach_reactor() -> void:
	var __t := Time.get_ticks_usec()
	_breach_reactor_body()
	_time(&"_breach_reactor", __t)


func _breach_reactor_body() -> void:
	if reactor_gone:
		return
	var at := _reactor_position()
	var vel := _body.linear_velocity
	reactor_gone = true
	destroyed = true
	_kill_pilot()
	var fx := DamageFx.of(self)
	if fx != null:
		fx.reactor_flash(at, vel)
	# Everything around takes the flash: fluence falls as 1/R².
	for node in get_tree().get_nodes_in_group(ProjectileManager.DAMAGEABLE):
		var target := node as Node3D
		if target == null or target == (_vehicle as Node):
			continue
		var dist := maxf(target.global_position.distance_to(at), 5.0)
		var fluence := REACTOR_YIELD / (4.0 * PI * dist * dist)
		if target.has_method(&"apply_radiation"):
			target.call(&"apply_radiation", fluence, at)
		elif fluence > 5e6 and target.has_method(&"apply_hit"):
			target.call(&"apply_hit", 1e9, target.global_position, (target.global_position - at).normalized(), _vehicle)
	# The suit itself comes apart: every part flies off glowing.
	_blow_apart(at)
	var fc := _flight()
	if fc != null:
		fc.fcs_enabled = false
	_set_all_thrusters(false)
	reactor_breached.emit()


## Radiant fluence `fluence` J/m² from a flash at `from` (another suit's reactor).
func apply_radiation(fluence: float, from: Vector3) -> void:
	if not _built or reactor_gone or not enabled:
		return
	var dir := (_body.global_position - from).normalized()
	_body.apply_central_impulse(dir * 3e-5 * fluence * 70.0)
	if fluence > 5e7:
		_kill_pilot()
	if fluence > 5e6:
		for c in components:
			if not c.alive:
				continue
			if c.kind in [Kind.EYES, Kind.BODY_CAMERA, Kind.THRUSTER]:
				var facing := (component_position(c) - _body.global_position).dot(-dir) > 0.0
				if facing and _rng.randf() < clampf(fluence / 2e7, 0.2, 1.0):
					_kill_component(c)
	_event("flash %.1f MJ/m²" % (fluence / 1e6))


# --- Bullets and bursts ---

## A bullet (burst_distance 0) or a missile burst `burst_distance` m away (ProjectileManager).
func apply_impact(spec: ProjectileSpec, at: Vector3, relative_velocity: Vector3, burst_distance: float, _source: Node) -> void:
	if not _built or reactor_gone or not enabled:
		return
	if burst_distance <= 0.0:
		var m := spec.mass if spec.mass > 0.0 else 2.5
		_body.apply_impulse(relative_velocity * m, at - _body.global_position)
		# It can't get through the main armour; thin things near the point break.
		for c in components:
			if not c.alive or not (c.kind in [Kind.EYES, Kind.BODY_CAMERA, Kind.THRUSTER, Kind.VULCAN]):
				continue
			if component_position(c).distance_to(at) < c.radius + 0.5 and _rng.randf() < 0.35:
				_kill_component(c)
		return
	# Missile: 1000 fragments of 10 g at ~1.5 km/s, and the detonation products close in.
	var burst_at := at
	var fragments := 1000.0
	# The strikes that land on the suit: sparks where they hit (the side facing the burst).
	var fx := DamageFx.of(self)
	var strikes := mini(roundi(fragments * 70.0 / (4.0 * PI * maxf(burst_distance, 2.0) ** 2)), 40)
	if fx != null and strikes > 0:
		var toward := (burst_at - _body.global_position).normalized()
		for k in strikes:
			var p := parts[_rng.randi() % parts.size()]
			if p.severed or p.mesh == null:
				continue
			var centre := _part_frame(p) * p.aabb.get_center()
			var hit_at := _surface_toward(p, centre, (toward + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 0.35).normalized())
			if hit_at != Vector3.INF:
				fx.fragment_strike(hit_at, (hit_at - burst_at).normalized(), _body.linear_velocity, _rng.randf() * 0.12)
	for c in components:
		if not c.alive or not (c.kind in [Kind.EYES, Kind.BODY_CAMERA, Kind.THRUSTER, Kind.VULCAN]):
			continue
		var dist := maxf(component_position(c).distance_to(burst_at), 1.0)
		var expected := fragments * c.radius * c.radius / (4.0 * dist * dist)
		if _rng.randf() < 1.0 - exp(-expected):
			_kill_component(c)
	var d := maxf(burst_distance, 1.0)
	var share := minf(70.0 / (4.0 * PI * d * d), 0.5)
	var dir := (_body.global_position - burst_at).normalized()
	_body.apply_impulse(dir * 25000.0 * share, burst_at - _body.global_position)
	if burst_distance < 3.0:
		var p := _nearest_part(burst_at)
		if p != null:
			_remove_section(p, 0.3)


# --- Severing ---

## `p` breaks off at its joint, with every part beyond it: a free body in the pose it had.
## `may_dangle`: shot off (it may stay hanging); false when torn off under load.
func sever(p: Part, may_dangle := true) -> void:
	var __t := Time.get_ticks_usec()
	sever_body(p, may_dangle)
	_time(&"sever", __t)


func sever_body(p: Part, may_dangle := true) -> void:
	# The torso (chest, spine, pelvis) never comes off: it is the suit (a breach takes it apart).
	if p.severed or reactor_gone or CORE_PARTS.has(p.name):
		return
	if p.equipment != null:
		_break_equipment(p.equipment)
		return
	if p.limb and p.has_hole and p.cut_y == INF:
		var y := p.last_hole.y
		if y > p.aabb.position.y + p.aabb.size.y * 0.18 and y < p.aabb.end.y - p.aabb.size.y * 0.08:
			_cut_part(p, y, may_dangle)
			return
	var group: Array[Part] = []
	for q in parts:
		if q.equipment == null and not q.severed and _bone_is_under(q.bone, p.bone):
			group.append(q)
	var bones := {}
	for q in group:
		bones[q.bone] = true
	var equip: Array[MsEquipment] = []
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			if eq.equipped and eq.is_visible_in_tree() and _equipment_on(eq, bones, null, INF):
				equip.append(eq)
	var joint := _part_frame(p)
	var axis := joint.basis.y.normalized()          # from the joint out along the severed part
	var radius := clampf(minf(p.aabb.size.x, p.aabb.size.z) * 0.36, 0.35, 1.1)
	var body := _make_debris(group, equip, 3.0, joint.origin)
	for q in group:
		_take_followers(q, body)
	for eq in equip:
		_lose_equipment(eq)
		loadout.set_equipped(eq, false)
		_unequipped.append(eq)
	_remove_parts(group)
	_event("%s SEVERED" % p.name)
	part_severed.emit(p.name)
	var fx := DamageFx.of(self)
	# The torn socket on what is left: a melted crater at the joint, a stub of frame.
	var parent := _parent_part(p)
	if parent != null and parent.mesh != null:
		var h := holes.add_hole(parent.mesh, _skel, parent.bone, joint.origin + axis * 0.35, -axis, radius, 1.6, 1750.0)
		h.s_drill = 0.7
		h.shell = _skin_shells(parent, joint.origin + axis * 0.35, -axis, 1.6)
		if fx != null and _jointed(p):
			_stubs.append(fx.stump(parent.area, joint.origin, axis, radius, _velocity_at(joint.origin)))
	# And the torn end of the piece that flew off.
	if body != null:
		for child in body.get_children():
			var mi := child as MeshInstance3D
			if mi != null and String(mi.name).begins_with("Baked_" + String(p.name)):
				var h := holes.add_hole(mi, null, -1, joint.origin - axis * 0.35, axis, radius, 1.6, 1750.0)
				h.s_drill = 0.7
				h.shell = _skin_shells(p, joint.origin - axis * 0.35, axis, 1.6)
		if fx != null:
			if _jointed(p):
				fx.stump(body, joint.origin, -axis, radius, Vector3.ZERO)
			fx.sever(joint.origin, _body.linear_velocity)
		if may_dangle and p.limb and parent != null:
			_maybe_dangle(p, body, parent, joint.origin, axis)


## `p` breaks across at `y` (bone space) where it was holed: the near side stays on with a
## hot cut face, the far side and every part beyond fly off as one piece.
func _cut_part(p: Part, y: float, may_dangle := true) -> void:
	var __t := Time.get_ticks_usec()
	_cut_part_body(p, y, may_dangle)
	_time(&"_cut_part", __t)


func _cut_part_body(p: Part, y: float, may_dangle := true) -> void:
	var frame := _part_frame(p)
	var c0 := p.aabb.get_center()
	var cut_local := Vector3(c0.x, y, c0.z)
	var cut_world := frame * cut_local
	var axis := frame.basis.y.normalized()
	var share := clampf((p.aabb.end.y - y) / maxf(p.aabb.size.y, 0.1), 0.05, 0.95)
	var group: Array[Part] = []
	for q in parts:
		if q != p and q.equipment == null and not q.severed and _bone_is_under(q.bone, p.bone):
			group.append(q)
	var bones := {}
	for q in group:
		bones[q.bone] = true
	var equip: Array[MsEquipment] = []
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			if eq.equipped and eq.is_visible_in_tree() and _equipment_on(eq, bones, p, y):
				equip.append(eq)
	var body := _make_debris(group, equip, 3.0, cut_world, 0.0, p, share)
	for q in group:
		_take_followers(q, body)
	_take_followers(p, body, y)
	for eq in equip:
		_lose_equipment(eq)
		loadout.set_equipped(eq, false)
		_unequipped.append(eq)
	_remove_parts(group)
	# The stub: cut on the mesh, its hull trimmed, its mass and what was beyond the cut gone.
	p.cut_y = y
	p.left = BREAK_LEFT + 0.1
	holes.cut(p.mesh, _skel, p.bone, cut_local, Vector3.UP, true, _section(p, p.cut_y, Transform3D.IDENTITY))
	var kept := PackedVector3Array()
	for v in p.hull_points:
		if v.y < y:
			kept.append(v)
	for corner in [Vector3(p.aabb.position.x, y, p.aabb.position.z), Vector3(p.aabb.end.x, y, p.aabb.position.z),
			Vector3(p.aabb.position.x, y, p.aabb.end.z), Vector3(p.aabb.end.x, y, p.aabb.end.z)]:
		kept.append(corner)
	((p.area.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points = kept
	var fill := _reaction.get_fill()
	var orig: Array = _mass_removed.get(p.name, [p.dry, p.tank, 0.0, 0.0])
	_mass_removed[p.name] = [orig[0], orig[1], float(orig[2]) + p.dry * share, float(orig[3]) + p.tank * share]
	_reaction.set_part_mass(p.name, p.dry * (1.0 - share))
	_reaction.set_part_tank(p.name, p.tank * (1.0 - share))
	var fc := _flight()
	if fc != null:
		fc.add_payload_mass(-p.dry * share)
		fc.propellant = maxf(fc.propellant - p.tank * share * fill, 0.0)
		fc.propellant_capacity = maxf(fc.propellant_capacity - p.tank * share, 1.0)
	var inv := frame.affine_inverse()
	for c in components:
		if c.part == p and c.alive and (inv * component_position(c)).y > y:
			_kill_component(c, true)
			if c.node != null and c.kind == Kind.THRUSTER:
				c.node.visible = false
				_hidden_nodes.append(c.node)
	_capability_changed()
	_event("%s CUT" % p.name)
	part_severed.emit(p.name)
	var radius := clampf(minf(p.aabb.size.x, p.aabb.size.z) * 0.36, 0.35, 1.1)
	var fx := DamageFx.of(self)
	if fx != null:
		_stubs.append(fx.stump(p.area, cut_world, axis, radius, _velocity_at(cut_world)))
		if body != null:
			fx.stump(body, cut_world, -axis, radius, Vector3.ZERO)
		fx.sever(cut_world, _body.linear_velocity)
	if may_dangle and body != null:
		_maybe_dangle(p, body, p, cut_world, axis)


## The piece `body` just cut from `p` may stay hanging from `holder` at `at` (world; `axis` from
## the stump out along the piece): a swinging joint there and a few cables.
func _maybe_dangle(p: Part, body: RigidBody3D, holder: Part, at: Vector3, axis: Vector3) -> void:
	if _rng.randf() > DANGLE_CHANCE * clampf(0.6 + p.left, 0.3, 1.0):
		return
	body.linear_velocity = _velocity_at(at)
	body.angular_velocity = _body.angular_velocity
	var joint := ConeTwistJoint3D.new()
	joint.name = "Dangle"
	_vehicle.get_parent().add_child(joint)
	var x := axis.normalized()
	var y := x.cross(Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT).normalized()
	joint.global_transform = Transform3D(Basis(x, y, x.cross(y)), at)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(75.0))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(40.0))
	joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.6)
	joint.node_a = joint.get_path_to(_body)
	joint.node_b = joint.get_path_to(body)
	var cables := MeshInstance3D.new()
	cables.name = "DangleCables"
	cables.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.04, 0.04, 0.045)
	cables.material_override = mat
	cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vehicle.get_parent().add_child(cables)
	_dangles.append([joint, body, holder, _body.global_transform.affine_inverse() * at,
			body.global_transform.affine_inverse() * at, cables, 0.0, body.linear_velocity])
	_event("%s hanging" % p.name)


## The load on each hanging piece: torn loose past what its strut and cables hold.
func _hold_dangles(delta: float) -> void:
	for i in range(_dangles.size() - 1, -1, -1):
		var dg: Array = _dangles[i]
		var body := dg[1] as RigidBody3D
		if not is_instance_valid(body) or not is_instance_valid(dg[0]):
			_drop_dangle(i, false)
			continue
		var v := body.linear_velocity
		var a := (v - (dg[7] as Vector3)).length() / maxf(delta, 1e-4)
		dg[7] = v
		dg[6] = lerpf(float(dg[6]), a, 1.0 - exp(-delta / 0.08))
		var gap := (_body.global_transform * (dg[3] as Vector3)).distance_to(body.global_transform * (dg[4] as Vector3))
		if float(dg[6]) > DANGLE_HOLD or gap > 2.5:
			_drop_dangle(i, true)


## Lets the hanging piece `i` go: `torn` makes it crack loose (sparks), else it just ends.
func _drop_dangle(i: int, torn: bool) -> void:
	var dg: Array = _dangles[i]
	_dangles.remove_at(i)
	if is_instance_valid(dg[0]):
		(dg[0] as Node).queue_free()
	if is_instance_valid(dg[5]):
		(dg[5] as Node).queue_free()
	var body := dg[1] as RigidBody3D
	if not is_instance_valid(body):
		return
	# Clear of the suit's hull for a moment, as when it was first cut.
	body.add_collision_exception_with(_body)
	var suit := _body
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(body) and is_instance_valid(suit):
			body.remove_collision_exception_with(suit))
	if torn:
		var at := body.global_transform * (dg[4] as Vector3)
		var fx := DamageFx.of(self)
		if fx != null:
			fx.creak(at, body.linear_velocity, 1.5)
		_event("hanging %s tore loose" % (dg[2] as Part).name)


func _process(_delta: float) -> void:
	# The cables between each stump and its hanging piece: a few strands, sagging a little.
	for dg in _dangles:
		if not is_instance_valid(dg[1]) or not is_instance_valid(dg[5]):
			continue
		var im := (dg[5] as MeshInstance3D).mesh as ImmediateMesh
		im.clear_surfaces()
		var a := _body.global_transform * (dg[3] as Vector3)
		var b := (dg[1] as Node3D).global_transform * (dg[4] as Vector3)
		var side := (b - a).cross(Vector3.UP).normalized() if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT
		var up := side.cross(b - a).normalized()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for k in 5:
			var off := side * (k - 2) * 0.12 + up * ((k % 2) * 0.1 - 0.05)
			var prev := a + off
			for j in range(1, 7):
				var t := j / 6.0
				var pt := a.lerp(b, t) + off * (1.0 - t * 0.6) - up * sin(t * PI) * 0.15
				im.surface_add_vertex(prev)
				im.surface_add_vertex(pt)
				prev = pt
		im.surface_end()


func _jointed(p: Part) -> bool:
	for prefix in JOINTED:
		if String(p.name).begins_with(prefix):
			return true
	return false


## A hit (on `_p`, along `dir` from `at` over `length`, a beam of `radius`) that passes through
## a frame stub's socket: nothing is left to hold the stub, it is knocked loose and flies off.
## Any part's hit counts: a socket often sits between parts (the hip, among the skirts).
func _knock_stubs(_p: Part, at: Vector3, dir: Vector3, length: float, radius: float) -> void:
	for i in range(_stubs.size() - 1, -1, -1):
		var st := _stubs[i] as Node3D
		if not is_instance_valid(st):
			continue
		var rel := st.global_position - at
		var s := clampf(rel.dot(dir), -1.5, length + 1.5)
		if (rel - dir * s).length() > radius + 0.8:
			continue
		_stubs.remove_at(i)
		var body := RigidBody3D.new()
		body.name = "Debris"
		body.gravity_scale = 0.0
		body.mass = 400.0
		_vehicle.get_parent().add_child(body)
		body.global_transform = st.global_transform
		st.reparent(body)
		body.linear_velocity = _velocity_at(body.global_position) + (dir + (st.global_basis.y * 0.6)).normalized() * _rng.randf_range(15.0, 40.0)
		body.angular_velocity = Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 3.0
		_solidify(body)
		_debris.append(body)
		var fx := DamageFx.of(self)
		if fx != null:
			fx.creak(body.global_position, body.linear_velocity, 1.2)


## A hole on a box far off, once: the first hole's material (the damage shader) would
## otherwise be set up on the first hit, a ~40 ms stall.
func _prewarm_holes() -> void:
	for ref in range(1, HoleSet.STENCIL_REFS + 1):
		HoleSet._stencil_shader("write", ref)
		HoleSet._stencil_shader("cap", ref)
	# Drawn, not just made: the GPU builds a material's pipelines the first time it draws it
	# (the cut face's stencil passes cost ~100 ms on the first real cut). A box too small to see,
	# just in front of the camera, holed and cut, for a few frames.
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	for k in HoleSet.STENCIL_REFS:
		var mi := MeshInstance3D.new()
		mi.name = "HolePrewarm"
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.002
		mi.mesh = box
		mi.layers = 0xFFFFF
		if cam != null:
			cam.add_child(mi)
			mi.position = Vector3(0.0, 0.0, -0.5)
		else:
			add_child(mi)
			mi.global_position = Vector3(0.0, -1.0e6, 0.0)
		var at := mi.global_position
		holes.add_hole(mi, null, -1, at + mi.global_basis.z * 0.001, -mi.global_basis.z, 0.0005, 0.002)
		holes.cut(mi, null, -1, Vector3.ZERO, Vector3.UP, k % 2 == 0,
				PackedVector3Array([Vector3(-0.001, 0, -0.001), Vector3(0.001, 0, -0.001), Vector3(0, 0, 0.001)]))
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			holes.forget(mi)
			mi.queue_free())


## The damage part a bone belongs to: itself or the nearest up its chain.
func _part_of_bone(b: int) -> Part:
	if _bone_part.has(b):
		return _bone_part[b]
	var start := b
	var found: Part = null
	while b >= 0 and found == null:
		for q in parts:
			if q.bone == b and q.equipment == null:
				found = q
				break
		b = _skel.get_bone_parent(b)
	_bone_part[start] = found
	return found


var _bone_part := {}   ## bone → its part (cache; the parts don't change after build)


func _bone_of_node(n: Node) -> int:
	while n != null and n != _vehicle:
		if n is BoneAttachment3D:
			return _skel.find_bone((n as BoneAttachment3D).bone_name)
		n = n.get_parent()
	return -1


## Everything that rides a part's bone and is not handled on its own (the part's mesh, its
## damage hull, equipment): thruster and camera mounts, stow arms, props, skinned meshes that
## are not parts. It goes (hidden, and copied onto the piece) when the part does.
func _build_followers() -> void:
	_followers.clear()
	var part_meshes := {}
	for p in parts:
		if p.mesh != null:
			part_meshes[p.mesh] = true
	for node in _vehicle.find_children("*", "BoneAttachment3D", true, false):
		var a := node as BoneAttachment3D
		if String(a.name).begins_with("DamageHull_"):
			continue
		if a.find_children("*", "MsEquipment", true, false).size() > 0 or a.get_parent() is BoneAttachment3D:
			continue
		var p := _part_of_bone(_skel.find_bone(a.bone_name))
		if p != null:
			_followers[p] = _followers.get(p, []) + [a]
	for node in _skel.get_children():
		var mi := node as MeshInstance3D
		if mi == null or part_meshes.has(mi) or mi.skin == null or mi.mesh == null:
			continue
		var b := _dominant_bone(mi)
		var p := _part_of_bone(b)
		if p != null:
			_followers[p] = _followers.get(p, []) + [mi]


func _dominant_bone(mi: MeshInstance3D) -> int:
	var arr := arrays_of(mi.mesh, 0)
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var count := {}
	for i in bones.size():
		if w[i] > 0.5:
			count[bones[i]] = int(count.get(bones[i], 0)) + 1
	var best := -1
	var most := -1
	for k in count:
		if count[k] > most:
			most = count[k]
			best = k
	if best < 0:
		return -1
	var b := mi.skin.get_bind_bone(best)
	return b if b >= 0 else _skel.find_bone(mi.skin.get_bind_name(best))


## Copies `p`'s followers that are showing onto the flying piece `body` (beyond `cut_y`, bone
## space, when the part was cut through), then hides them on the suit.
func _take_followers(p: Part, body: RigidBody3D, cut_y := -INF) -> void:
	var to_bone := (_skel.global_transform * FinalPoses.of(_skel).pose(p.bone)).affine_inverse()
	for f: Node3D in _followers.get(p, []):
		if not is_instance_valid(f) or not f.is_visible_in_tree():
			continue
		if cut_y > -INF and (to_bone * f.global_position).y < cut_y:
			continue
		if body != null:
			var meshes: Array = [f] if f is MeshInstance3D else f.find_children("*", "MeshInstance3D", true, false)
			for m in meshes:
				var mi := m as MeshInstance3D
				if mi.mesh == null or not mi.is_visible_in_tree() or _is_fx(mi):
					continue
				var copy: MeshInstance3D
				if mi.skin != null:
					copy = _bake(mi)
					body.add_child(copy)
					copy.transform = (body.global_transform.affine_inverse() * _skel.global_transform) * copy.transform
				else:
					copy = MeshInstance3D.new()
					copy.mesh = mi.mesh
					for i in mi.get_surface_override_material_count():
						copy.set_surface_override_material(i, mi.get_active_material(i))
					copy.layers = mi.layers
					body.add_child(copy)
					copy.global_transform = mi.global_transform
		f.visible = false
		_hidden_nodes.append(f)


## A thruster's plume or glow (not hardware).
static func _is_fx(n: Node) -> bool:
	var c: Node = n
	while c != null:
		if c.name == &"PlumePivot" or c.name == &"Glow":
			return true
		if c is Thruster:
			return false
		c = c.get_parent()
	return false


## Which parts can be moved: not severed, and no joint out on the way to the torso. A limp part's
## AMBAC joints are out, its weapons can't aim or fire, its equipment can't be used or raised.
func _update_control() -> void:
	limp.clear()
	for p in parts:
		if p.equipment != null:
			continue
		var b := p.bone
		while b >= 0:
			var q := _part_of_bone(b)
			if q == null:
				break
			if q.severed or _joint_out.has(q.name):
				limp[p] = true
				break
			b = _skel.get_bone_parent(q.bone)
	var ambac := _comp(AmbacController) as AmbacController
	if ambac != null:
		for j in ambac.joints:
			var jp := _part_of_bone(_skel.find_bone(j.bone_name))
			if jp != null and limp.has(jp) and j.priority > 0.0:
				_saved_priority[j] = j.priority
				j.priority = 0.0
	var fcs := _comp(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			var wb := _skel.find_bone(w.equipment.mount_bone if w.equipment != null else w.mount_bone)
			if w.equipment != null:
				wb = _equipment_bone(w.equipment)
			var wp := _part_of_bone(wb)
			w.limp = wp != null and limp.has(wp)
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			var ep := _part_of_bone(_equipment_bone(eq))
			eq.disabled = ep != null and limp.has(ep)
			if eq.disabled and eq.active:
				eq.set_active(false)


## The bone `eq` hangs from now (hand or stow point; its mount bone when not mounted).
func _equipment_bone(eq: MsEquipment) -> int:
	var b := _bone_of_node(eq)
	return b if b >= 0 else _skel.find_bone(eq.mount_bone)


## Whether the part (by name) can be controlled.
func is_controllable(part_name: StringName) -> bool:
	var p := find_part(part_name)
	return p != null and not p.severed and not limp.has(p)


## The nearest part up the skeleton from `p`.
func _parent_part(p: Part) -> Part:
	var b := _skel.get_bone_parent(p.bone)
	while b >= 0:
		for q in parts:
			if q.bone == b and q.equipment == null:
				return q
		b = _skel.get_bone_parent(b)
	return null


func _velocity_at(world: Vector3) -> Vector3:
	return _body.linear_velocity + _body.angular_velocity.cross(world - _body.global_transform * _body.center_of_mass)


func _bone_is_under(bone: int, ancestor: int) -> bool:
	var b := bone
	while b >= 0:
		if b == ancestor:
			return true
		b = _skel.get_bone_parent(b)
	return false


## Whether `eq` goes with a piece made of the parts on `bones`: it hangs from one of them, or
## from a bone under one (the shield's own mount bone under the forearm). `cut` cut through at
## `cut_y` (bone space): equipment on it beyond the cut goes too.
func _equipment_on(eq: MsEquipment, bones: Dictionary, cut: Part, cut_y: float) -> bool:
	var attach := eq.get_parent() as BoneAttachment3D
	var b := _skel.find_bone(attach.bone_name if attach != null else String(eq.mount_bone))
	while b >= 0:
		if bones.has(b):
			return true
		if cut != null and b == cut.bone:
			var local := (_skel.global_transform * FinalPoses.of(_skel).pose(cut.bone)).affine_inverse() * eq.global_position
			return local.y > cut_y
		for q in parts:
			if q.bone == b and q.equipment == null:
				return false   # it hangs from another part, which stays
		b = _skel.get_bone_parent(b)
	return false


## Takes `group` off the suit: hidden, out of the hull queries, the mass model, the flight
## computer's mass, thrust and balancing.
func _remove_parts(group: Array[Part]) -> void:
	var fc := _flight()
	var fill := _reaction.get_fill()
	var ambac := _comp(AmbacController) as AmbacController
	for i in range(_dangles.size() - 1, -1, -1):
		if group.has(_dangles[i][2]):
			_drop_dangle(i, true)
	for q in group:
		q.severed = true
		q.mesh.visible = false
		_hidden_nodes.append(q.mesh)
		q.area.collision_layer = 0
		var before: Array = _mass_removed.get(q.name, [q.dry, q.tank, 0.0, 0.0])
		var left_dry := q.dry - float(before[2])
		var left_tank := q.tank - float(before[3])
		_mass_removed[q.name] = [q.dry, q.tank, q.dry, q.tank]
		_reaction.set_part_mass(q.name, 0.0)
		_reaction.set_part_tank(q.name, 0.0)
		if fc != null:
			fc.add_payload_mass(-left_dry)
			fc.propellant = maxf(fc.propellant - left_tank * fill, 0.0)
			fc.propellant_capacity = maxf(fc.propellant_capacity - left_tank, 1.0)
		if ambac != null:
			for j in ambac.joints:
				if j.bone_name == q.name and j.priority > 0.0:
					_saved_priority[j] = j.priority
					j.priority = 0.0
		for c in components:
			if c.part == q and c.alive:
				c.alive = false
				if c.kind in [Kind.EYES, Kind.BODY_CAMERA, Kind.VULCAN, Kind.THRUSTER]:
					c.alive = true
					_kill_component(c, true)
				elif c.kind == Kind.PILOT:
					_kill_pilot.call_deferred()
		for root in ["Thrusters", "Cameras"]:
			var attach := _vehicle.get_node_or_null(NodePath(root + "/Attach_" + String(q.name).replace(".", "_")))
			if attach != null and attach is Node3D:
				(attach as Node3D).visible = false
				_hidden_nodes.append(attach)
		for f: Node3D in _followers.get(q, []):
			if is_instance_valid(f) and f.visible:
				f.visible = false
				_hidden_nodes.append(f)
		# Smoke leaking from it, sparks on it: they went with it.
		for fx in q.area.get_children():
			if fx is GPUParticles3D:
				fx.queue_free()
	_update_control()
	_capability_changed()


## Bakes `group` (and `equip`) in their current pose into one free rigid body flying off.
func _make_debris(group: Array[Part], equip: Array[MsEquipment], push: float, from: Vector3, heat := 0.0,
		cut: Part = null, cut_share := 0.0) -> RigidBody3D:
	var __t := Time.get_ticks_usec()
	var __r := _make_debris_body(group, equip, push, from, heat, cut, cut_share)
	_time(&"_make_debris", __t)
	return __r


func _make_debris_body(group: Array[Part], equip: Array[MsEquipment], push: float, from: Vector3, heat := 0.0,
		cut: Part = null, cut_share := 0.0) -> RigidBody3D:
	if group.is_empty() and equip.is_empty() and cut == null:
		return null
	var body := RigidBody3D.new()
	body.name = "Debris"
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	var scene := _vehicle.get_parent()
	scene.add_child(body)
	body.global_transform = _skel.global_transform
	var mass := 0.0
	var centre := Vector3.ZERO
	var fill := _reaction.get_fill()
	for q in group:
		var mi := _bake(q.mesh)
		mi.name = "Baked_" + String(q.name)
		body.add_child(mi)
		var holes_on := holes.get_holes(q.mesh)
		var bh := Vector2(heat, holes.now) if heat > 0.0 else Vector2.ZERO
		# The baked mesh's own space: the skeleton's, moved by where it sits on the piece.
		var to_mesh := mi.transform.affine_inverse()
		if not holes_on.is_empty() or heat > 0.0:
			holes.adopt(mi, holes_on, to_mesh * FinalPoses.of(_skel).pose(q.bone), bh)
		if q.cut_y != INF:
			var pose := to_mesh * FinalPoses.of(_skel).pose(q.bone)
			var c0 := q.aabb.get_center()
			holes.cut(mi, null, -1, pose * Vector3(c0.x, q.cut_y, c0.z), (pose.basis * Vector3.UP).normalized(), true, _section(q, q.cut_y, pose))
		var m := q.dry + q.tank * fill
		mass += m
		centre += (FinalPoses.of(_skel).pose(q.bone) * q.aabb.get_center()) * m
		# Frame stubs left where a limb came off this part go with it.
		for stub in _stubs:
			if is_instance_valid(stub) and stub.get_parent() == q.area:
				stub.reparent(body)
		# A stow manipulator mounted on this part (the rifle's, on the rear skirt) goes with it.
		for node in _vehicle.find_children("*", "StowArm", true, false):
			var arm := node as Node3D
			var attach := arm.get_parent() as BoneAttachment3D
			if attach == null or _skel.find_bone(attach.bone_name) != q.bone or not arm.visible:
				continue
			for child in arm.find_children("*", "MeshInstance3D", true, false):
				var src := child as MeshInstance3D
				if src.mesh == null or not src.is_visible_in_tree():
					continue
				var copy := MeshInstance3D.new()
				copy.mesh = src.mesh
				for si in src.get_surface_override_material_count():
					copy.set_surface_override_material(si, src.get_active_material(si))
				copy.material_override = src.material_override
				copy.layers = src.layers
				body.add_child(copy)
				copy.global_transform = src.global_transform
			arm.visible = false
			_hidden_nodes.append(arm)
			# What it held can't be stowed any more.
			var loadout := _comp(MsLoadout) as MsLoadout
			if loadout != null:
				for eq: MsEquipment in loadout.equipment:
					if arm.name == "StowArm_%s" % eq.name:
						loadout.set_stow_lost(eq, true)
						_event("%s can't be stowed" % eq.name)
	if cut != null:
		# The far side of a part cut through: the whole mesh, cut the other way.
		var mi := _bake(cut.mesh)
		mi.name = "Baked_" + String(cut.name)
		body.add_child(mi)
		var pose := mi.transform.affine_inverse() * FinalPoses.of(_skel).pose(cut.bone)
		holes.adopt(mi, holes.get_holes(cut.mesh), pose)
		var c0 := cut.aabb.get_center()
		holes.cut(mi, null, -1, pose * Vector3(c0.x, cut.cut_y if cut.cut_y != INF else cut.last_hole.y, c0.z),
				(pose.basis * Vector3.UP).normalized(), false, _section(cut, cut.cut_y if cut.cut_y != INF else cut.last_hole.y, pose))
		var m := (cut.dry + cut.tank * fill) * cut_share
		mass += m
		var far_y := cut.aabb.end.y - cut.aabb.size.y * cut_share * 0.5
		centre += (FinalPoses.of(_skel).pose(cut.bone) * Vector3(c0.x, far_y, c0.z)) * m
	for eq in equip:
		for node in eq.find_children("*", "MeshInstance3D", true, false):
			var src := node as MeshInstance3D
			if not src.is_visible_in_tree():
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			for s in src.get_surface_override_material_count():
				mi.set_surface_override_material(s, src.get_active_material(s))
			mi.layers = src.layers
			body.add_child(mi)
			mi.global_transform = src.global_transform
		mass += eq.mass
		centre += (_skel.global_transform.affine_inverse() * eq.global_position) * eq.mass
	centre /= maxf(mass, 1.0)
	body.mass = maxf(mass, 10.0)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = centre
	var size := 3.0
	body.inertia = Vector3.ONE * mass * size * size / 6.0
	var com_world := body.global_transform * centre
	var suit_com := _body.global_transform * _body.center_of_mass
	var out := (com_world - from).normalized() if com_world.distance_to(from) > 0.1 else (com_world - suit_com).normalized()
	# A frozen hull (after a breach) has no velocity of its own any more: the one it had.
	var v0 := _breach_v if reactor_gone else _body.linear_velocity
	var w0 := _breach_w if reactor_gone else _body.angular_velocity
	body.linear_velocity = v0 + w0.cross(com_world - suit_com) + out * push \
			+ Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * push * 0.2
	body.angular_velocity = w0 + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 0.6
	_solidify(body)
	_debris.append(body)
	return body


## Gives a piece knocked off a convex shape per mesh it carries, on the debris layer. It is born
## inside the suit's own collision shape and next to the other pieces of the same hit, so for
## its first second it ignores the suit and other debris.
func _solidify(body: RigidBody3D) -> void:
	for child in body.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var verts := 0
		var am := mi.mesh as ArrayMesh
		if am != null:
			for si in am.get_surface_count():
				verts += am.surface_get_array_len(si)
		# A hull of a dense mesh costs tens of ms: a box for those.
		var shape: Shape3D
		if verts > 2000 or body.name.begins_with("DebrisPlate"):
			var box := BoxShape3D.new()
			box.size = mi.mesh.get_aabb().size
			shape = box
		else:
			# Baked parts share their mesh with the suit: one hull per mesh, kept.
			shape = hull_of(mi.mesh)
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = mi.transform
		if shape is BoxShape3D:
			cs.transform = mi.transform * Transform3D(Basis.IDENTITY, mi.mesh.get_aabb().get_center())
		body.add_child(cs)
	body.collision_layer = Layers.PHYS_DEBRIS
	body.collision_mask = Layers.WORLD
	body.continuous_cd = true
	body.add_collision_exception_with(_body)
	var suit := _body
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if not is_instance_valid(body):
			return
		body.collision_mask |= Layers.PHYS_DEBRIS
		if is_instance_valid(suit):
			body.remove_collision_exception_with(suit))


## A copy of `mesh` in the skeleton's current pose (skeleton space), its own materials.
func _bake(mesh: MeshInstance3D) -> MeshInstance3D:
	var mesh_in_skel := _skel.global_transform.affine_inverse() * mesh.global_transform
	# Rigid on one bone: the same mesh, placed where the bone holds it (no copy).
	if mesh.skin != null and mesh.mesh.get_surface_count() > 0:
		var a0 := arrays_of(mesh.mesh, 0)
		var rb := -1
		if a0[Mesh.ARRAY_BONES] != null:
			rb = rigid_bind(a0[Mesh.ARRAY_BONES], a0[Mesh.ARRAY_WEIGHTS], (a0[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		for si in range(1, mesh.mesh.get_surface_count()):
			var ai := arrays_of(mesh.mesh, si)
			if ai[Mesh.ARRAY_BONES] == null or rigid_bind(ai[Mesh.ARRAY_BONES], ai[Mesh.ARRAY_WEIGHTS], (ai[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) != rb:
				rb = -1
		if rb >= 0:
			var fast := MeshInstance3D.new()
			fast.mesh = mesh.mesh
			fast.layers = mesh.layers
			fast.transform = mesh_in_skel * bind_transform(mesh, _skel, rb)
			return fast
	var am := ArrayMesh.new()
	for s in mesh.mesh.get_surface_count():
		var arrays := arrays_of(mesh.mesh, s)
		var skinned := skin_surface(mesh, _skel, arrays)
		var verts: PackedVector3Array = skinned[0]
		var normals: PackedVector3Array = skinned[1]
		for i in verts.size():
			verts[i] = mesh_in_skel * verts[i]
		for i in normals.size():
			normals[i] = (mesh_in_skel.basis * normals[i]).normalized()
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		if not normals.is_empty():
			out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
		out[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		am.surface_set_material(s, mesh.mesh.surface_get_material(s))
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.layers = mesh.layers
	return mi


## The reactor took the suit apart: every part and piece of equipment flies off, glowing.
func _blow_apart(at: Vector3) -> void:
	var loadout := _comp(MsLoadout) as MsLoadout
	var all: Array[Part] = []
	for p in parts:
		if p.equipment == null and not p.severed:
			all.append(p)
	# Torn off at the joints and scattered, not vaporized: a limb segment far from the blast
	# may stay on its parent (a whole arm, a leg in one piece); near it everything parts.
	var with := {}
	for q in all:
		with[q] = q
	for q in all:
		var parent := _parent_part(q)
		if parent == null or not all.has(parent) or not q.limb or not parent.limb:
			continue
		var d := (_part_frame(q) * q.aabb.get_center()).distance_to(at)
		if _rng.randf() < clampf((d - 4.0) / 8.0, 0.0, 0.7):
			with[q] = parent
	var pieces := {}
	for q in all:
		var top: Part = q
		while with[top] != top:
			top = with[top]
		if not pieces.has(top):
			pieces[top] = [] as Array[Part]
		(pieces[top] as Array[Part]).append(q)
	# Only what was close to the reactor glows; the rest is torn, not melted. The pieces are
	# made a few per tick under the flash (a breach used to stall one frame for 90 ms); they
	# keep the suit's velocity at the moment it went.
	_breach_v = _body.linear_velocity
	_breach_w = _body.angular_velocity
	var t0 := _clock
	var k := 0
	for top: Part in pieces:
		var group: Array[Part] = pieces[top]
		var centre := _part_frame(top) * top.aabb.get_center()
		var dist := centre.distance_to(at)
		var speed := clampf(900.0 / maxf(dist, 2.0), 40.0, 160.0)
		var heat := 1400.0 * clampf(1.0 - (dist - 2.0) / 5.0, 0.0, 1.0)
		_later(PIECE_TICK * float(k / PIECES_PER_TICK), func() -> void:
			var body := _make_debris(group, [], speed, at, heat)
			if body != null:
				body.global_position += _breach_v * (_clock - t0))
		k += 1
	if loadout != null:
		for eq in loadout.equipment:
			if eq.equipped and eq.is_visible_in_tree():
				var one: Array[MsEquipment] = [eq]
				_later(PIECE_TICK * float(k / PIECES_PER_TICK), func() -> void:
					var body := _make_debris([], one, 90.0, at)
					if body != null:
						body.global_position += _breach_v * (_clock - t0))
				k += 1
				loadout.set_equipped(eq, false)
				_unequipped.append(eq)
	_remove_parts(all)
	var shield := _shield()
	if shield != null and shield.equipped and loadout != null:
		_make_debris([], [shield], 90.0, at)
		loadout.set_equipped(shield, false)
		_unequipped.append(shield)
	_sweep_leftovers(at)
	# Nothing left of the hull to simulate: it stops being a body (repair brings it back).
	_reaction.enabled = false
	_hull_layers = [_body.collision_layer, _body.collision_mask]
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.freeze = true
	var fc := _flight()
	if fc != null:
		fc.process_mode = Node.PROCESS_MODE_DISABLED


## Whatever is still showing on the suit after it came apart (meshes that aren't parts: the
## rifle's stow arm, hatches, props) flies off as debris too, one piece per mesh.
func _sweep_leftovers(at: Vector3) -> void:
	# The cockpit goes with the pilot (its panoramic screen shows from outside too).
	var cockpit := _vehicle.get_cockpit() as Node3D
	if cockpit != null and cockpit.visible:
		cockpit.visible = false
		_hidden_nodes.append(cockpit)
	var left: Array[MeshInstance3D] = []
	for node in _vehicle.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and mi.layers & (Layers.VEHICLE_EXT | Layers.WORLD):
			left.append(mi)
	var scene := _vehicle.get_parent()
	for mi in left:
		var body := RigidBody3D.new()
		body.name = "Debris"
		body.gravity_scale = 0.0
		scene.add_child(body)
		var copy: MeshInstance3D
		if mi.skin != null:
			copy = _bake(mi)
			body.global_transform = _skel.global_transform
		else:
			copy = MeshInstance3D.new()
			copy.mesh = mi.mesh
			for i in mi.get_surface_override_material_count():
				copy.set_surface_override_material(i, mi.get_active_material(i))
			copy.layers = mi.layers
			body.global_transform = mi.global_transform
		body.add_child(copy)
		var centre := body.global_transform * copy.get_aabb().get_center()
		body.mass = clampf(copy.get_aabb().get_volume() * 150.0, 20.0, 3000.0)
		var speed := clampf(900.0 / maxf(centre.distance_to(at), 2.0), 40.0, 160.0)
		body.linear_velocity = _body.linear_velocity + (centre - at).normalized() * speed
		body.angular_velocity = Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 1.5
		holes.heat(copy, null, -1, 1400.0)
		_solidify(body)
		_debris.append(body)
		# A stow arm sets its parts' visibility every frame: hide the arm itself.
		var hide: Node3D = mi
		var up := mi.get_parent()
		while up != null and up != _vehicle:
			if up is StowArm:
				hide = up as Node3D
				break
			up = up.get_parent()
		if hide.visible:
			hide.visible = false
			_hidden_nodes.append(hide)


## The shield has too little plate left: it breaks off and drifts away.
func break_shield(shield: MsShield) -> void:
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout == null or not shield.equipped:
		return
	_make_debris([], [shield], 4.0, shield.global_position)
	_break_equipment(shield)
	loadout.set_equipped(shield, false)
	_unequipped.append(shield)
	_event("SHIELD BROKEN")


func _shield() -> MsShield:
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout == null:
		return null
	for eq in loadout.equipment:
		if eq is MsShield:
			return eq
	return null


# --- Repair ---

## Everything back as built: the range's rearm.
func repair() -> void:
	if not _built:
		return
	_drills.clear()
	_queue.clear()
	holes.clear()
	for body in _debris:
		if is_instance_valid(body):
			body.queue_free()
	_debris.clear()
	for stub in _stubs:
		if is_instance_valid(stub):
			stub.queue_free()
	_stubs.clear()
	_snapping.clear()
	var lo := _comp(MsLoadout) as MsLoadout
	if lo != null:
		lo.stow_lost.clear()
	for i in range(_dangles.size() - 1, -1, -1):
		_drop_dangle(i, false)
	_last_v = Vector3.INF
	_accel = Vector3.ZERO
	_alpha = Vector3.ZERO
	for node in _opaque:
		if is_instance_valid(node):
			set_opaque(node, false)
	_opaque.clear()
	for node in _hidden_nodes:
		if is_instance_valid(node):
			node.visible = true
	_hidden_nodes.clear()
	var fc := _flight()
	var fill := _reaction.get_fill()
	for pname in _mass_removed:
		var m: Array = _mass_removed[pname]
		_reaction.set_part_mass(pname, m[0])
		_reaction.set_part_tank(pname, m[1])
		if fc != null:
			fc.add_payload_mass(m[2])
	_mass_removed.clear()
	# The tanks as built (the parts' cells don't add up to it, and removing parts stops at
	# 1 kg), at the fill they had.
	if fc != null and _capacity_built > 0.0:
		fc.propellant_capacity = _capacity_built
		fc.propellant = _capacity_built * fill
	for j: AmbacJoint in _saved_priority:
		j.priority = _saved_priority[j]
	_saved_priority.clear()
	_joint_out.clear()
	limp.clear()
	for p in parts:
		if p.cut_y != INF and p.area != null:
			((p.area.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D).points = p.hull_points
		p.cut_y = INF
		p.has_hole = false
		p.left = 1.0
		p.severed = false
		if p.area != null:
			p.area.collision_layer = Layers.PHYS_DAMAGE
	for c in components:
		c.alive = true
		_light_camera(c, true)
		if c.kind == Kind.THRUSTER:
			(c.ref as Thruster).enabled = true
		elif c.kind == Kind.VULCAN:
			(c.ref as MsWeapon).broken = false
	_set_all_thrusters(true)
	for t: Thruster in _thruster_saved:
		var sv: Array = _thruster_saved[t]
		t.max_thrust = sv[0]
		t.gimbal_limit_deg = sv[1]
		t.gimbal_pitch_limit_deg = sv[2]
		t.gimbal_yaw_limit_deg = sv[3]
	_thruster_saved.clear()
	_leaks.clear()
	var sensors := _comp(SensorSuite) as SensorSuite
	if sensors != null:
		sensors.main_camera_alive = true
		sensors.body_camera_dead.clear()
	var loadout := _comp(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in _unequipped:
			loadout.set_equipped(eq, true)
	_unequipped.clear()
	var fcs := _comp(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			w.broken = false
			w.limp = false
	if loadout != null:
		for eq in loadout.equipment:
			eq.disabled = false
	var shield := _shield()
	if shield != null:
		shield.repair()
	if not _hull_layers.is_empty():
		_body.collision_layer = _hull_layers[0]
		_body.collision_mask = _hull_layers[1]
		_hull_layers.clear()
		_body.freeze = false
		_reaction.enabled = true
		if fc != null:
			fc.process_mode = Node.PROCESS_MODE_INHERIT
	pilot_dead = false
	reactor_gone = false
	destroyed = false
	last_event = ""
	if fc != null:
		fc.fcs_enabled = true
		fc.pilot_lost = false
	_capability_changed()
	repaired.emit()


# --- Helpers ---

func _set_all_thrusters(on: bool) -> void:
	var root := _vehicle.get_node_or_null(^"Thrusters")
	if root == null:
		return
	for node in root.find_children("*", "", true, false):
		if node is Thruster:
			if on:
				(node as Thruster).enabled = true
			else:
				(node as Thruster).shut_down()


func _capability_changed() -> void:
	if not _capability_dirty:
		_capability_due = _clock + 0.2
	_capability_dirty = true


func _later(seconds: float, call: Callable) -> void:
	_queue.append([_clock + seconds, call])


func _event(text: String) -> void:
	last_event = text


func _flight() -> FlightComputer:
	return _comp(FlightComputer) as FlightComputer


var _comps := {}   ## component class → the vehicle's instance (find_component walks the whole suit)


func _comp(cls: Variant) -> Node:
	var n: Node = _comps.get(cls)
	if n == null or not is_instance_valid(n):
		n = _vehicle.find_component(cls)
		_comps[cls] = n
	return n


## State of every part for a panel: [name, share of section left (0 = gone)].
func get_part_states() -> Array:
	var out: Array = []
	for p in parts:
		if p.equipment == null:
			out.append([p.name, 0.0 if p.severed else clampf(p.left, 0.0, 1.0)])
	return out


func count_dead(kind: int) -> int:
	var n := 0
	for c in components:
		if c.kind == kind and not c.alive:
			n += 1
	return n


static func _time(what: StringName, t0: int) -> void:
	var us := Time.get_ticks_usec() - t0
	var e: Array = timings.get(what, [0, 0, 0])
	e[0] += 1
	e[1] += us
	e[2] = maxi(e[2], us)
	timings[what] = e
