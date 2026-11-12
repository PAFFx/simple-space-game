class_name CockpitSwitch
extends CockpitClickable

## A two-way toggle switch built from simple meshes: a base, a lever thrown forward
## (position 0) or back toward the pilot (position 1), and its name and position labels.
## Left click throws it forward, right click back (as in DCS). The owner sets `index`
## from the state it controls, so the lever always shows the truth.

signal switched(index: int)

@export var title: String = ""
@export var positions := PackedStringArray(["ON", "OFF"])
@export var throw_deg: float = 28.0
@export var lever_rate_deg: float = 600.0

var index: int = 0

var _lever: Node3D
var _angle := 0.0
var _lever_mat: StandardMaterial3D

const LEVER_COLOR := Color(0.72, 0.74, 0.76)
const HOVER_COLOR := Color(0.4, 0.9, 1.0)


func _ready() -> void:
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.008, 0.022)
	base.mesh = box
	base.material_override = _material(Color(0.06, 0.065, 0.07))
	add_child(base)

	_lever = Node3D.new()
	_lever.position = Vector3(0, 0.004, 0)
	add_child(_lever)
	_lever_mat = _material(LEVER_COLOR)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0022
	cyl.bottom_radius = 0.003
	cyl.height = 0.024
	stem.mesh = cyl
	stem.position = Vector3(0, 0.012, 0)
	stem.material_override = _lever_mat
	_lever.add_child(stem)
	var tip := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.0045
	ball.height = 0.009
	tip.mesh = ball
	tip.position = Vector3(0, 0.025, 0)
	tip.material_override = _lever_mat
	_lever.add_child(tip)

	_label(title, Vector3(0, 0.001, 0.02), 30, Color(0.86, 0.9, 0.92))
	if positions.size() >= 2:
		_label(positions[0], Vector3(0, 0.001, -0.019), 24, Color(0.55, 0.62, 0.66))
		_label(positions[1], Vector3(0, 0.001, 0.031), 24, Color(0.55, 0.62, 0.66))
	_angle = _target_angle()
	_apply()


func click(direction: int) -> void:
	var to := 0 if direction < 0 else 1
	if to != index:
		index = to
		switched.emit(index)
	super.click(direction)


func set_index(value: int) -> void:
	index = clampi(value, 0, maxi(positions.size() - 1, 0))


func _process(delta: float) -> void:
	_angle = move_toward(_angle, _target_angle(), deg_to_rad(lever_rate_deg) * delta)
	_apply()


func _on_hover_changed() -> void:
	_lever_mat.albedo_color = HOVER_COLOR if hovered else LEVER_COLOR
	_lever_mat.emission_enabled = hovered
	_lever_mat.emission = HOVER_COLOR * 0.6


func get_pick_position() -> Vector3:
	return _lever.get_global_transform_interpolated() * Vector3(0, 0.02, 0)


func _target_angle() -> float:
	# Forward (−Z) for position 0, back toward the pilot for position 1.
	return deg_to_rad(-throw_deg if index == 0 else throw_deg)


func _apply() -> void:
	if _lever != null:
		_lever.basis = Basis(Vector3.RIGHT, _angle)


## Text lying on the panel, readable from the pilot's side.
func _label(value: String, at: Vector3, size: int, color: Color) -> void:
	if value == "":
		return
	var l := Label3D.new()
	l.text = value
	l.font_size = size
	l.pixel_size = 0.00018
	l.modulate = color
	l.outline_size = 0
	l.position = at
	l.basis = Basis(Vector3.RIGHT, -PI * 0.5)  # lie flat, top edge pointing forward
	l.double_sided = false
	add_child(l)


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.5
	m.metallic = 0.4
	return m
