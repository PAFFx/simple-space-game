class_name StowArm
extends Node3D

## A manipulator kept in a bay inside the suit's armour (behind a hatch door, a bone of
## the model that EquipmentDrawModifier swings open) that carries stowed equipment to the
## hand and back (MsDrawMotion.present_keys): a turret, a short first link that swings out
## through the opening, an elbow and a telescoping boom ending in a rotary wrist and a
## two-finger gripper closed over the equipment. Stowed, only the gripper (and the boom's
## tip) shows. MsLoadout drives it (set_pose); its frame is the stow bone's.

## How far the wrist sits off the gripped face (the palm's depth), m.
const PALM := 0.45
## Telescoping sections of the boom, and how much each overlaps the next, m.
const SECTIONS := 4
const OVERLAP := 0.25

var _shoulder := Vector3.ZERO
var _normal := Vector3.BACK
var _link := 0.8
var _section := 1.0
var _turret: MeshInstance3D
var _link_a: MeshInstance3D
var _elbow: MeshInstance3D
var _boom: Array[MeshInstance3D] = []
var _wrist: MeshInstance3D
var _palm: MeshInstance3D
var _fingers: Array[MeshInstance3D] = []
var _finger_at := PackedVector3Array()


## Builds it in the bay behind a hatch centred at `hatch_centre` (this node's frame) on a
## plate facing `normal`: a first link of `link` m, a boom reaching `reach` m, a gripper for
## an edge-to-edge span of `grip_span` m.
func build(hatch_centre: Vector3, normal: Vector3, link: float, reach: float, grip_span: float, layers: int) -> void:
	_normal = normal.normalized()
	_shoulder = hatch_centre - _normal * 0.3
	_link = link
	_section = (reach + OVERLAP * (SECTIONS - 1)) / SECTIONS
	var dark := _material(Color(0.2, 0.21, 0.23), 0.7, 0.45)
	var joint := _material(Color(0.5, 0.51, 0.53), 0.8, 0.3)
	var light := _material(Color(0.62, 0.63, 0.65), 0.85, 0.25)
	_turret = _part(_cylinder(0.22, 0.3), joint, layers)
	_link_a = _part(_box(Vector3(0.24, 0.28, 1.0)), dark, layers)
	_elbow = _part(_cylinder(0.16, 0.4), joint, layers)
	for i in SECTIONS:
		var w := 0.26 - i * 0.04
		_boom.append(_part(_box(Vector3(w, w, 1.0)), dark if i % 2 == 0 else light, layers))
	_wrist = _part(_cylinder(0.12, 0.26), joint, layers)
	# Palm across the gripped edge; two fingers down the faces either side (gripper frame:
	# x out of the gripped edge, y across it, z along the equipment).
	_palm = _part(_box(Vector3(0.16, grip_span + 0.2, 0.5)), dark, layers)
	for sgn in [1.0, -1.0]:
		_fingers.append(_part(_box(Vector3(0.7, 0.1, 0.36)), dark, layers))
		_finger_at.append(Vector3(-0.28, sgn * (grip_span * 0.5 + 0.05), 0.0))


## The gripper on the equipment (`grip`: the gripped point, its basis x out of the gripped
## edge and y across it, this node's frame); `deploy` 0 (folded in) … 1 (out), the first
## link swinging from `in_dir` to `out_dir`; `hatch` 0 (shut) … 1 (open). `empty`: nothing
## to hold, folded right in (all of it hidden once the hatch is shut).
func set_pose(grip: Transform3D, deploy: float, in_dir: Vector3, out_dir: Vector3, hatch: float,
		empty := false) -> void:
	var g := grip.basis.orthonormalized()
	var wrist := grip.origin + g.x * PALM
	var dir_a := in_dir.normalized().slerp(out_dir.normalized(), deploy)
	var elbow := _shoulder + dir_a * _link
	var boom := wrist - elbow
	var length := boom.length()
	var bdir := boom / maxf(length, 1e-4)
	var hinge := dir_a.cross(bdir)
	hinge = hinge.normalized() if hinge.length() > 1e-3 else _normal.cross(bdir).normalized()
	_turret.transform = Transform3D(_axis_basis(_normal), _shoulder)
	_stretch(_link_a, _shoulder, elbow, hinge)
	_elbow.transform = Transform3D(_axis_basis(hinge), elbow)
	# Sections spread evenly from the elbow to the wrist, each overlapping the next.
	var sec := minf(_section, length)
	for i in SECTIONS:
		var start := elbow + bdir * ((length - sec) * float(i) / (SECTIONS - 1))
		_stretch(_boom[i], start, start + bdir * sec, hinge)
	_wrist.transform = Transform3D(_axis_basis(bdir), wrist)
	_palm.transform = Transform3D(g, grip.origin + g.x * 0.12)
	for i in _fingers.size():
		_fingers[i].transform = Transform3D(g, grip.origin + g * _finger_at[i])
	# Folded away behind the shut hatch: only the gripper and the boom's tip show.
	var inside := deploy <= 0.001 and hatch <= 0.001
	_turret.visible = not inside
	_link_a.visible = not inside
	_elbow.visible = not inside
	for i in SECTIONS:
		_boom[i].visible = not inside or (i == SECTIONS - 1 and not empty)
	for part in [_wrist, _palm] + _fingers:
		(part as Node3D).visible = not (inside and empty)


## A unit-long part (along −Z) stretched from `from` to `to`, its width across `hinge`.
static func _stretch(part: MeshInstance3D, from: Vector3, to: Vector3, hinge: Vector3) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / maxf(length, 1e-4)
	var up := hinge if absf(hinge.dot(dir)) < 0.95 else Vector3.UP
	part.transform = Transform3D(Basis.looking_at(dir, up).scaled_local(Vector3(1.0, 1.0, maxf(length, 0.01))),
			(from + to) * 0.5)


## A basis whose +Y runs along `axis` (cylinders stand on +Y).
static func _axis_basis(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 16
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _part(mesh: Mesh, mat: Material, layers: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = layers
	add_child(mi)
	return mi
