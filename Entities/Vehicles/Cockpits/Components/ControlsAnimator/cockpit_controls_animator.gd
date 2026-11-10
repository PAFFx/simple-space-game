class_name CockpitControlsAnimator
extends Node

## Moves the cockpit grips and pedals to match the pilot's current command.
##   Right grip: pitch / roll.  Left grip: translation (twist = up/down).  Pedals: yaw.
## The input source is discovered from the vehicle (first PilotInputSource).

@export var left_grip: Node3D
@export var right_grip: Node3D
@export var left_pedal: Node3D
@export var right_pedal: Node3D
@export var grip_travel_deg: float = 16.0
@export var pedal_travel_deg: float = 14.0
@export var input_source: PilotInputSource

var _rest := {}


func _ready() -> void:
	for n: Node3D in [left_grip, right_grip, left_pedal, right_pedal]:
		if n != null:
			_rest[n] = n.basis
	if input_source == null:
		var vehicle := VehicleBase.find_vehicle(self)
		if vehicle != null:
			input_source = vehicle.find_component(PilotInputSource) as PilotInputSource


func _process(_delta: float) -> void:
	if input_source == null:
		return
	var cmd := input_source.last_command
	var g := deg_to_rad(grip_travel_deg)
	var p := deg_to_rad(pedal_travel_deg)
	# Rotations follow the stick: tilting the top back = pitch up, right = roll right.
	_pose(right_grip, Vector3(cmd.rotation.x * g, 0.0, cmd.rotation.z * g))
	_pose(left_grip, Vector3(cmd.translation.z * g, -cmd.translation.y * g, -cmd.translation.x * g))
	_pose(left_pedal, Vector3(-maxf(cmd.rotation.y, 0.0) * p, 0.0, 0.0))
	_pose(right_pedal, Vector3(-maxf(-cmd.rotation.y, 0.0) * p, 0.0, 0.0))


func _pose(node: Node3D, euler: Vector3) -> void:
	if node != null:
		node.basis = (_rest[node] as Basis) * Basis.from_euler(euler)
