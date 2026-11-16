class_name CockpitControlsAnimator
extends Node

## Moves the cockpit grips and pedals to match the pilot's current command.
##   SPLIT  Right grip: pitch / roll.  Left grip: translation (twist = up/down).  Pedals: yaw.
##   TWIN   Both controls flown tank style, as TwinStickPilotInput mixes them: fore/aft
##          together = forward / back, against each other = yaw (or roll), sideways =
##          strafe, tops back = nose up. With balls (the model's ball controllers) only
##          the balls turn, in their cradles; without, the grips tilt and twist against
##          each other for pitch.
##          Pedals: right = up, left = down; the pressed one tips and slides forward.
## The command is un-mixed back into stick travel, so the keyboard moves the controls too.
## The input source is discovered from the vehicle (first PilotInputSource).

enum Scheme { SPLIT, TWIN }

@export var scheme := Scheme.SPLIT
@export var left_grip: Node3D
@export var right_grip: Node3D
## TWIN: the balls inside the grips, if the model has them.
@export var left_ball: Node3D
@export var right_ball: Node3D
@export var left_pedal: Node3D
@export var right_pedal: Node3D
@export var grip_travel_deg: float = 16.0
@export var twist_travel_deg: float = 22.0
@export var pedal_travel_deg: float = 14.0
## TWIN: how far the pressed pedal slides forward at full travel, m.
@export var pedal_stroke: float = 0.0
## Smoothing of the controls' motion, s. 0 = off.
@export var smoothing: float = 0.0
@export var input_source: PilotInputSource

var _rest := {}
var _rest_origin := {}
var _pose_now := {}
var _heave := 0.0


func _ready() -> void:
	for n: Node3D in [left_grip, right_grip, left_pedal, right_pedal, left_ball, right_ball]:
		if n != null:
			_rest[n] = n.basis
			_rest_origin[n] = n.position
			_pose_now[n] = Vector3.ZERO
	if input_source == null:
		var vehicle := VehicleBase.find_vehicle(self)
		if vehicle != null:
			input_source = vehicle.find_component(PilotInputSource) as PilotInputSource


func _physics_process(delta: float) -> void:
	if input_source == null:
		return
	var cmd := input_source.last_command
	var g := deg_to_rad(grip_travel_deg)
	var p := deg_to_rad(pedal_travel_deg)
	var w := 1.0 if smoothing <= 0.0 else 1.0 - exp(-delta / smoothing)
	# Rotations follow the stick: tilting the top back = pitch up, right = roll right.
	if scheme == Scheme.SPLIT:
		_pose(right_grip, Vector3(cmd.rotation.x * g, 0.0, cmd.rotation.z * g), w)
		_pose(left_grip, Vector3(cmd.translation.z * g, -cmd.translation.y * g, -cmd.translation.x * g), w)
		_pose(left_pedal, Vector3(-maxf(cmd.rotation.y, 0.0) * p, 0.0, 0.0), w)
		_pose(right_pedal, Vector3(-maxf(-cmd.rotation.y, 0.0) * p, 0.0, 0.0), w)
		return
	var forward := -cmd.translation.z
	var turn := clampf(cmd.rotation.y + cmd.rotation.z, -1.0, 1.0)   # + = left: right stick forward
	var twist := cmd.rotation.x * deg_to_rad(twist_travel_deg)        # + = nose up
	var side := -cmd.translation.x * g
	var left_tilt := -clampf(forward - turn, -1.0, 1.0) * g
	var right_tilt := -clampf(forward + turn, -1.0, 1.0) * g
	if left_ball != null and right_ball != null:
		# Only the balls move, in their cradles; the units stay put on the armrests.
		_pose(left_ball, Vector3(left_tilt + twist, 0.0, side), w)
		_pose(right_ball, Vector3(right_tilt + twist, 0.0, side), w)
	else:
		_pose(left_grip, Vector3(left_tilt, twist, side), w)
		_pose(right_grip, Vector3(right_tilt, -twist, side), w)
	_pose(right_pedal, Vector3(-maxf(cmd.translation.y, 0.0) * p, 0.0, 0.0), w)
	_pose(left_pedal, Vector3(-maxf(-cmd.translation.y, 0.0) * p, 0.0, 0.0), w)
	_heave = lerpf(_heave, cmd.translation.y, w)
	_slide(right_pedal, maxf(_heave, 0.0) * pedal_stroke)
	_slide(left_pedal, maxf(-_heave, 0.0) * pedal_stroke)


## Moves a pedal along its own forward axis from where it rests.
func _slide(node: Node3D, amount: float) -> void:
	if node != null and pedal_stroke != 0.0:
		node.position = (_rest_origin[node] as Vector3) + (_rest[node] as Basis) * Vector3(0.0, 0.0, -amount)


func _pose(node: Node3D, euler: Vector3, weight: float) -> void:
	if node == null:
		return
	var now: Vector3 = (_pose_now[node] as Vector3).lerp(euler, weight)
	_pose_now[node] = now
	node.basis = (_rest[node] as Basis) * Basis.from_euler(now)
