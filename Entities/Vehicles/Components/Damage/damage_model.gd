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
	var aabb := AABB()        ## bone space
	var left := 1.0           ## share of its cross-section still there
	var severed := false
	var equipment: MsEquipment   ## equipment as a part: a box, not a hull
	var box := AABB()

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
var _opaque: Array[Node] = []


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
		parts.append(p)
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			if eq is MsShield:
				continue   # solid on its own: it drills itself (MsShield.beam_contact)
			var p := Part.new()
			p.name = eq.name
			p.equipment = eq
			p.box = MsLoadout.local_box(eq)
			p.dry = eq.mass
			p.volume = maxf(p.box.get_volume() * 0.35, 0.1)
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
	_built = true


## The mesh's vertices, skinned in the skeleton's current pose, in `bone`'s space.
static func bone_space_points(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var to_bone := skeleton.get_bone_global_pose(bone).affine_inverse()
	var mesh_in_skel := skeleton.global_transform.affine_inverse() * mesh.global_transform
	for s in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(s)
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
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		mats.append(skeleton.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(b))
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
		var to_bone := (_skel.global_transform * _skel.get_bone_global_pose(p.bone)).affine_inverse().basis * _body.global_basis
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
	var sensors := _vehicle.find_component(SensorSuite) as SensorSuite
	if head != null:
		var eye := head.aabb.get_center() + Vector3(0.0, 0.0, -head.aabb.size.z * 0.3)
		var eyes := _bone_component(Kind.EYES, &"main camera", head, eye, 0.6)
		eyes.facing = Vector3.FORWARD
		eyes.half_deg = 105.0   # the head turns
		eyes.grade = 0
		_panoramic_camera(&"rear head camera", head, Vector3(0.0, 0.5, 1.0), 75.0)
	var fcs := _vehicle.find_component(FireControl) as FireControl
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
		out.append([(basis * c.facing).normalized(), cos(deg_to_rad(c.half_deg)), c.grade])
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
		var c := _skel.global_transform * _skel.get_bone_global_pose(p.bone) * p.aabb.get_center()
		var d := c.distance_to(world)
		if d < best_d:
			best_d = d
			best = p
	return best


# --- Frames ---

func _part_frame(p: Part) -> Transform3D:
	if p.equipment != null:
		return p.equipment.global_transform
	return _skel.global_transform * _skel.get_bone_global_pose(p.bone)


func _component_frame(c: Component) -> Transform3D:
	if c.node != null:
		return c.node.global_transform
	if c.bone >= 0:
		return _skel.global_transform * _skel.get_bone_global_pose(c.bone)
	return _body.global_transform


func component_position(c: Component) -> Vector3:
	return _component_frame(c) * (c.box.get_center() if c.is_box else c.local)


# --- Beams ---

## One tick of a beam on the suit (ProjectileManager.BeamContact).
func beam_contact(contact: ProjectileManager.BeamContact) -> void:
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
		var t := _ray_box(p.equipment.global_transform, p.box, from, dir)
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
	var n := ceili((d.t_end - d.t0) / STEP)
	d.kg.resize(n)
	d.cells.resize(n)
	for i in n:
		var tc := d.t0 + (i + 0.5) * STEP
		var kg := 0.0
		for s in spans:
			if tc >= s[1] and tc <= s[2]:
				kg += (s[0] as Part).density * STEP * area
		for cell in cells:
			if tc >= cell[1] and tc <= cell[2]:
				kg += WATER_DENSITY * fill * STEP * area
				d.cells[i] = cell[0]
		d.kg[i] = kg
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
		if seg[3] == null and p.mesh != null:
			var entry: Vector3 = xf * (d.from_body + d.dir_body * float(seg[1]))
			seg[3] = holes.add_hole(p.mesh, _skel, p.bone, entry, xf.basis * d.dir_body, d.radius, chord)
			part_damaged.emit(p.name)
			var fx := DamageFx.of(self)
			if fx != null:
				fx.drill_in(entry, xf.basis * d.dir_body, _body.linear_velocity, d.radius, p.area)
		var drilled := clampf(t - float(seg[1]), 0.0, chord)
		if seg[3] != null:
			(seg[3] as HoleSet.Hole).s_drill = chord if drilled >= chord - 1e-3 else drilled
		if drilled >= chord - 1e-3 and not seg[4]:
			seg[4] = true
			_through_part(p, d, chord)
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
func _through_part(p: Part, d: Drill, chord: float) -> void:
	_remove_section(p, _hole_share(p, d.radius, chord))
	if p.equipment == null:
		_hit_joints(p, 0.6)
		if _rng.randf() < 0.45:
			# Wiring and capacitor banks on the line: arcs, then a small burst.
			var at: Vector3 = _part_frame(p) * p.aabb.get_center()
			_later(0.05 + _rng.randf() * 0.15, func() -> void: _burst(at, _rng.randf_range(1e6, 1e7), &"electronics"))


## A drill that ended (no contact for a while): partial holes cost their share too.
func _finish(d: Drill) -> void:
	for seg in d.segs:
		if seg[4] or seg[3] == null:
			continue
		var p: Part = seg[0]
		var chord: float = seg[2] - seg[1]
		var frac := (seg[3] as HoleSet.Hole).s_drill / maxf(chord, 0.01)
		_remove_section(p, _hole_share(p, d.radius, chord) * frac)
		if frac > 0.5 and p.equipment == null:
			_hit_joints(p, 0.3)


func _remove_section(p: Part, share: float) -> void:
	if p.severed:
		return
	p.left -= share
	if p.equipment != null:
		if p.left < BREAK_LEFT:
			_break_equipment(p.equipment)
	elif not CORE_PARTS.has(p.name) and p.left < (BREAK_LEFT if p.limb else 0.0):
		_later(0.03, func() -> void: sever(p))


func _hit_joints(p: Part, chance: float) -> void:
	var ambac := _vehicle.find_component(AmbacController) as AmbacController
	if ambac == null:
		return
	for j in ambac.joints:
		if j.bone_name == p.name and j.priority > 0.0 and _rng.randf() < chance:
			_saved_priority[j] = j.priority
			j.priority = 0.0
			_event("%s actuator out" % p.name)


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


func _kill_component(c: Component) -> void:
	if not c.alive:
		return
	c.alive = false
	match c.kind:
		Kind.THRUSTER:
			(c.ref as Thruster).enabled = false
			_capability_changed()
		Kind.EYES:
			var sensors := _vehicle.find_component(SensorSuite) as SensorSuite
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
func _lose_equipment(eq: MsEquipment) -> void:
	for c in components:
		if c.kind == Kind.EQUIPMENT and c.ref == eq:
			c.alive = false
	for p in parts:
		if p.equipment == eq:
			p.severed = true
	var fcs := _vehicle.find_component(FireControl) as FireControl
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
	var fcs := _vehicle.find_component(FireControl) as FireControl
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
		_burst(component_position(cell), maxf(e, 5e7), &"steam"))


# --- Bursts, reactor, pilot ---

## Something went off inside the suit at `at` (world) with `energy` J: what is within its
## blow-off radius is torn (parts lose section, thin components are destroyed). Steam from a
## tank cell, an E-pac, electronics.
func _burst(at: Vector3, energy: float, kind: StringName) -> void:
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
	# Panels blown off carry momentum out: the suit gets the opposite, small.
	var push := sqrt(2.0 * 150.0 * energy) * 0.15
	var away := (_body.global_transform * _body.center_of_mass - at)
	if away.length() > 0.01:
		_body.apply_impulse(away.normalized() * push, at - _body.global_position)


func _kill_pilot() -> void:
	if pilot_dead:
		return
	pilot_dead = true
	destroyed = true
	var fc := _flight()
	if fc != null:
		fc.fcs_enabled = false
	var fcs := _vehicle.find_component(FireControl) as FireControl
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
func sever(p: Part) -> void:
	if p.severed or reactor_gone:
		return
	if p.equipment != null:
		_break_equipment(p.equipment)
		return
	var group: Array[Part] = []
	for q in parts:
		if q.equipment == null and not q.severed and _bone_is_under(q.bone, p.bone):
			group.append(q)
	var bones := {}
	for q in group:
		bones[q.bone] = true
	var equip: Array[MsEquipment] = []
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			if eq.equipped and eq.is_visible_in_tree() and _equipment_on(eq, bones):
				equip.append(eq)
	var joint := _part_frame(p)
	var axis := joint.basis.y.normalized()          # from the joint out along the severed part
	var radius := clampf(minf(p.aabb.size.x, p.aabb.size.z) * 0.36, 0.35, 1.1)
	var body := _make_debris(group, equip, 3.0, joint.origin)
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
		if fx != null:
			_stubs.append(fx.stump(parent.area, joint.origin, axis, radius, _velocity_at(joint.origin)))
	# And the torn end of the piece that flew off.
	if body != null:
		for child in body.get_children():
			var mi := child as MeshInstance3D
			if mi != null and String(mi.name).begins_with("Baked_" + String(p.name)):
				var h := holes.add_hole(mi, null, -1, joint.origin - axis * 0.35, axis, radius, 1.6, 1750.0)
				h.s_drill = 0.7
		if fx != null:
			fx.stump(body, joint.origin, -axis, radius, Vector3.ZERO)
			fx.sever(joint.origin, _body.linear_velocity)


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


func _equipment_on(eq: MsEquipment, bones: Dictionary) -> bool:
	var attach := eq.get_parent() as BoneAttachment3D
	if attach != null:
		return bones.has(_skel.find_bone(attach.bone_name))
	return bones.has(_skel.find_bone(eq.mount_bone))


## Takes `group` off the suit: hidden, out of the hull queries, the mass model, the flight
## computer's mass, thrust and balancing.
func _remove_parts(group: Array[Part]) -> void:
	var fc := _flight()
	var fill := _reaction.get_fill()
	var ambac := _vehicle.find_component(AmbacController) as AmbacController
	for q in group:
		q.severed = true
		q.mesh.visible = false
		_hidden_nodes.append(q.mesh)
		q.area.collision_layer = 0
		_mass_removed[q.name] = [q.dry, q.tank]
		_reaction.set_part_mass(q.name, 0.0)
		_reaction.set_part_tank(q.name, 0.0)
		if fc != null:
			fc.add_payload_mass(-q.dry)
			fc.propellant = maxf(fc.propellant - q.tank * fill, 0.0)
			fc.propellant_capacity = maxf(fc.propellant_capacity - q.tank, 1.0)
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
					_kill_component(c)
		var attach := _vehicle.get_node_or_null(NodePath("Thrusters/Attach_" + String(q.name).replace(".", "_")))
		if attach != null and attach is Node3D:
			(attach as Node3D).visible = false
			_hidden_nodes.append(attach)
	_capability_changed()


## Bakes `group` (and `equip`) in their current pose into one free rigid body flying off.
func _make_debris(group: Array[Part], equip: Array[MsEquipment], push: float, from: Vector3, heat := 0.0) -> RigidBody3D:
	if group.is_empty() and equip.is_empty():
		return null
	var body := RigidBody3D.new()
	body.name = "Debris"
	body.collision_layer = 0
	body.collision_mask = 0
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
		if not holes_on.is_empty() or heat > 0.0:
			holes.adopt(mi, holes_on, _skel.get_bone_global_pose(q.bone), bh)
		var m := q.dry + q.tank * fill
		mass += m
		centre += (_skel.get_bone_global_pose(q.bone) * q.aabb.get_center()) * m
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
	body.linear_velocity = _body.linear_velocity + _body.angular_velocity.cross(com_world - suit_com) + out * push \
			+ Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * push * 0.2
	body.angular_velocity = _body.angular_velocity + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 0.6
	_debris.append(body)
	return body


## A copy of `mesh` in the skeleton's current pose (skeleton space), its own materials.
func _bake(mesh: MeshInstance3D) -> MeshInstance3D:
	var am := ArrayMesh.new()
	var mesh_in_skel := _skel.global_transform.affine_inverse() * mesh.global_transform
	for s in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(s)
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
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	var all: Array[Part] = []
	for p in parts:
		if p.equipment == null and not p.severed:
			all.append(p)
	for q in all:
		var group: Array[Part] = [q]
		var centre := _part_frame(q) * q.aabb.get_center()
		var speed := clampf(900.0 / maxf(centre.distance_to(at), 2.0), 40.0, 160.0)
		_make_debris(group, [], speed, at, 1400.0)
	if loadout != null:
		for eq in loadout.equipment:
			if eq.equipped and eq.is_visible_in_tree():
				_make_debris([], [eq], 90.0, at)
				loadout.set_equipped(eq, false)
				_unequipped.append(eq)
	_remove_parts(all)
	var shield := _shield()
	if shield != null and shield.equipped and loadout != null:
		_make_debris([], [shield], 90.0, at)
		loadout.set_equipped(shield, false)
		_unequipped.append(shield)
	# Nothing left of the hull to simulate: it stops being a body (repair brings it back).
	_reaction.enabled = false
	_hull_layers = [_body.collision_layer, _body.collision_mask]
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.freeze = true
	var fc := _flight()
	if fc != null:
		fc.process_mode = Node.PROCESS_MODE_DISABLED


## The shield has too little plate left: it breaks off and drifts away.
func break_shield(shield: MsShield) -> void:
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	if loadout == null or not shield.equipped:
		return
	_make_debris([], [shield], 4.0, shield.global_position)
	_break_equipment(shield)
	loadout.set_equipped(shield, false)
	_unequipped.append(shield)
	_event("SHIELD BROKEN")


func _shield() -> MsShield:
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
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
			fc.add_payload_mass(m[0])
			fc.propellant_capacity += m[1]
			fc.propellant += m[1] * fill
	_mass_removed.clear()
	for j: AmbacJoint in _saved_priority:
		j.priority = _saved_priority[j]
	_saved_priority.clear()
	for p in parts:
		p.left = 1.0
		p.severed = false
		if p.area != null:
			p.area.collision_layer = Layers.PHYS_DAMAGE
	for c in components:
		c.alive = true
		if c.kind == Kind.THRUSTER:
			(c.ref as Thruster).enabled = true
		elif c.kind == Kind.VULCAN:
			(c.ref as MsWeapon).broken = false
	_set_all_thrusters(true)
	var sensors := _vehicle.find_component(SensorSuite) as SensorSuite
	if sensors != null:
		sensors.main_camera_alive = true
		sensors.body_camera_dead.clear()
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in _unequipped:
			loadout.set_equipped(eq, true)
	_unequipped.clear()
	var fcs := _vehicle.find_component(FireControl) as FireControl
	if fcs != null:
		for w: MsWeapon in fcs.weapons.values():
			w.broken = false
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
	_capability_changed()
	repaired.emit()


# --- Helpers ---

func _set_all_thrusters(on: bool) -> void:
	var root := _vehicle.get_node_or_null(^"Thrusters")
	if root == null:
		return
	for node in root.find_children("*", "", true, false):
		if node is Thruster:
			(node as Thruster).enabled = on


func _capability_changed() -> void:
	if not _capability_dirty:
		_capability_due = _clock + 0.2
	_capability_dirty = true


func _later(seconds: float, call: Callable) -> void:
	_queue.append([_clock + seconds, call])


func _event(text: String) -> void:
	last_event = text


func _flight() -> FlightComputer:
	return _vehicle.find_component(FlightComputer) as FlightComputer


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
