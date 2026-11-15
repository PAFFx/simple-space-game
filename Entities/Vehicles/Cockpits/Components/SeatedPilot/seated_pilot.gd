class_name SeatedPilot
extends Node3D

## Seats a character model in the cockpit and makes it fly the suit: the hands hold the
## grips and the feet rest on the pedals (IK onto the cockpit model's Hand*/Foot* markers,
## which ride on the animated controls), the head and torso follow the pilot's look (the
## torso twists and leans as PilotCamera does), and the torso leans a little against the
## suit's acceleration.
##
## This node is the seat frame (−Z forward, +Y up); put the character scene under it.
## The pose itself is applied by a SeatedPilotPose modifier added to the skeleton.

@export var cockpit_model: Node
## Where the character's hip centre sits, in this node's frame, and the same point in the
## character's own (unscaled scene) frame.
@export var hip_position := Vector3(0.0, -0.525, -0.07)
@export var character_hip := Vector3(0.0, 0.72, -0.024)
## The character scene faces +Z (glTF front).
@export var character_faces_back: bool = true
@export var recline_deg: float = 8.0

@export_group("Meshes")
## Mesh names (substring match) never drawn in the seat.
@export var hidden_meshes: PackedStringArray = ["beanie", "Icosphere"]
## Mesh names hidden from the pilot's own eye (it sits inside the head).
@export var head_meshes: PackedStringArray = ["eyebrows", "eyelashes", "eyes", "face", "hair", "scalp"]

@export_group("Hatch")
## A hand whose control stays behind when the seat turns for the hatch comes to rest
## here instead (in this node's frame, x for the right side), by this point of the
## hatch's timeline.
@export var lap_hand_position := Vector3(0.1, -0.44, -0.27)
@export var let_go_by: float = 0.06

@export_group("G response")
## Lean at very high G, deg (approached smoothly; half of it is reached near `g_reference`).
@export var max_lean_deg: float = 12.0
@export var g_reference: float = 3.0
## Leaning back into the seat is mostly blocked by it.
@export_range(0.0, 1.0) var backward_share: float = 0.35
## Natural frequency of the body's sway, rad/s (critically damped).
@export var sway_rate: float = 7.0

## Lean in degrees: x = to the right, y = forward.
var lean := Vector2.ZERO
var look := Basis.IDENTITY
## The torso's turn for that look (PilotCamera.torso), in this node's frame.
var torso := Basis.IDENTITY
## 0 seated at the controls → 1 once the hatch sequence has begun: the pilot lets go of
## any control that doesn't turn with the seat.
var let_go := 0.0
## The character scene's root (its +Y is the character's up).
var character: Node3D

var _pose: SeatedPilotPose
var _body: RigidBody3D
var _hatch: CockpitHatch
var _camera: PilotCamera
var _prev_velocity := Vector3.ZERO
var _lean_velocity := Vector2.ZERO
var _outside_visible := false
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			character = child
			break
	if character == null:
		push_warning("SeatedPilot: no character under " + name)
		return
	_seatcharacter()
	_collect_meshes()
	_apply_layers()
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null:
		_pose = SeatedPilotPose.new()
		_pose.name = "SeatedPilotPose"
		_pose.pilot = self
		_pose.find_targets(cockpit_model if cockpit_model != null else get_parent())
		skeleton.add_child(_pose)
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_body = vehicle as Node as RigidBody3D
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
		if vehicle.get_cockpit() != null:
			_camera = vehicle.get_cockpit().get_player_camera() as PilotCamera
	if _body != null:
		_prev_velocity = _body.linear_velocity


func _process(_delta: float) -> void:
	var outside := _hatch != null and _hatch.is_unsealed()
	let_go = smoothstep(0.0, let_go_by, _hatch.amount) if _hatch != null else 0.0
	if outside != _outside_visible:
		_outside_visible = outside
		_apply_layers()
	if _camera != null:
		look = _camera.look_rotation
		torso = _camera.torso
		_camera.body_sway = lean


func _physics_process(delta: float) -> void:
	if _body == null or delta <= 0.0:
		return
	var accel := (_body.linear_velocity - _prev_velocity) / delta
	_prev_velocity = _body.linear_velocity
	# The body is thrown against the acceleration, in the seat's frame.
	var g := (global_basis.orthonormalized().inverse() * -accel) / 9.80665
	var target := Vector2(_soft(g.x), _soft(-g.z))
	if target.y < 0.0:
		target.y *= backward_share
	# Critically damped spring, so the lean trails the G and never rings.
	var k := sway_rate * sway_rate
	_lean_velocity += ((target - lean) * k - _lean_velocity * 2.0 * sway_rate) * delta
	lean += _lean_velocity * delta


func _soft(g: float) -> float:
	return max_lean_deg * tanh(g / maxf(g_reference, 0.01))


func _seatcharacter() -> void:
	var turn := Basis(Vector3.UP, PI) if character_faces_back else Basis.IDENTITY
	# Keep the character scene's own scale, drop its own turn.
	var basis_seated := Basis(Vector3.RIGHT, deg_to_rad(recline_deg)) * turn * Basis.from_scale(character.basis.get_scale())
	character.transform = Transform3D(basis_seated, hip_position - basis_seated * character_hip)


func _collect_meshes() -> void:
	for mesh: MeshInstance3D in character.find_children("*", "MeshInstance3D", true, false):
		if _matches(mesh, hidden_meshes):
			mesh.visible = false
		else:
			_meshes.append(mesh)


## Drawn for the pilot's eye (without the head) always, for outside cameras only while
## the hatch is unsealed, like the cockpit around it.
func _apply_layers() -> void:
	var outside := Layers.VEHICLE_EXT if _outside_visible else 0
	for mesh in _meshes:
		mesh.layers = outside if _matches(mesh, head_meshes) else Layers.PILOT | outside
		mesh.visible = mesh.layers != 0


static func _matches(mesh: MeshInstance3D, names: PackedStringArray) -> bool:
	var label := String(mesh.name) + " " + (mesh.mesh.resource_name if mesh.mesh != null else "")
	for n in names:
		if label.containsn(n):
			return true
	return false
