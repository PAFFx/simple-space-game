class_name CockpitControlsAnimator
extends Node

## Moves the cockpit grips and pedals to match the pilot's current command.
##   SPLIT  Right grip: pitch / roll.  Left grip: translation (twist = up/down).  Pedals: yaw.
##   TWIN   Both controls flown tank style, as TwinStickPilotInput mixes them: fore/aft
##          together = forward / back, against each other = yaw; sideways together =
##          strafe, against each other = roll (right ball right = roll right); tops back
##          = nose up. With balls (the model's ball controllers) only
##          the balls turn, in their cradles; without, the grips tilt and twist against
##          each other for pitch.
##          Pedals: right = up, left = down; the pressed one tips and slides forward.
##   RAIL   Crossbar grips on rails (the RX-0's controller), each grip doing what its
##          stick does in TwinStickPilotInput (and its invert flags, if that is the input):
##          slide = stick fore/aft (together = forward / back, against = yaw: right forward
##          = left); bar twist = stick twist, knuckles up = clockwise, its difference only
##          (right up against left down = nose up); roll = stick left/right (together =
##          strafe, right right against left left = roll right). Up / down is on the pedals,
##          linked like a fighter's: right forward and left back by as much = up. Braking
##          tips both toes forward (brake part way, hard brake fully). The lamps on each rail
##          are lit from its rear end up to the carriage.
## The command is un-mixed back into stick travel, so the keyboard moves the controls too.
## The input source is discovered from the vehicle (first PilotInputSource).

enum Scheme { SPLIT, TWIN, RAIL }

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

@export_group("Rail grips")
## Carriages: slide along their local −Z.
@export var left_slide: Node3D
@export var right_slide: Node3D
## Roll hinges: roll about their local Z (fore-aft).
@export var left_roll: Node3D
@export var right_roll: Node3D
## Crossbars: twist about their local X (the bar's axis), by twist_travel_deg.
@export var left_bar: Node3D
@export var right_bar: Node3D
## How far a carriage slides either way from rest at full travel, m.
@export var slide_travel: float = 0.06
@export var roll_travel_deg: float = 20.0
## Each rail's lamps, one mesh in the carriage's frame, drawn with rail_lamp_material: its
## instance uniform lit_from (set to the carriage's z) lights the lamps behind the carriage.
@export var left_rail_lamps: GeometryInstance3D
@export var right_rail_lamps: GeometryInstance3D
@export var rail_lamp_material: Material
## Toe brake: both pedals tip forward by this at hard brake (a plain brake, 70% of it).
@export var brake_travel_deg: float = 16.0
## Rise of the pedal rails per metre forward (the pedals slide along them).
@export var pedal_rail_rise: float = 0.0

var _rest := {}
var _rest_origin := {}
var _pose_now := {}
var _slide_now := {}
var _heave := 0.0


func _ready() -> void:
	for n: Node3D in [left_grip, right_grip, left_pedal, right_pedal, left_ball, right_ball,
			left_slide, right_slide, left_roll, right_roll, left_bar, right_bar]:
		if n != null:
			_rest[n] = n.basis
			_rest_origin[n] = n.position
			_pose_now[n] = Vector3.ZERO
			_slide_now[n] = 0.0
	for lamps: GeometryInstance3D in [left_rail_lamps, right_rail_lamps]:
		if lamps != null:
			lamps.material_override = rail_lamp_material
			lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var turn := cmd.rotation.y                                       # + = left: right stick forward
	var roll_right := -cmd.rotation.z
	if scheme == Scheme.RAIL:
		_rail(cmd, forward, turn, roll_right, w)
		return
	var twist := cmd.rotation.x * deg_to_rad(twist_travel_deg)        # + = nose up
	var left_side := -clampf(cmd.translation.x - roll_right, -1.0, 1.0) * g
	var right_side := -clampf(cmd.translation.x + roll_right, -1.0, 1.0) * g
	var left_tilt := -clampf(forward - turn, -1.0, 1.0) * g
	var right_tilt := -clampf(forward + turn, -1.0, 1.0) * g
	if left_ball != null and right_ball != null:
		# Only the balls move, in their cradles; the units stay put on the armrests.
		_pose(left_ball, Vector3(left_tilt + twist, 0.0, left_side), w)
		_pose(right_ball, Vector3(right_tilt + twist, 0.0, right_side), w)
	else:
		_pose(left_grip, Vector3(left_tilt, twist, left_side), w)
		_pose(right_grip, Vector3(right_tilt, -twist, right_side), w)
	_pedals(cmd, p, w)


func _rail(cmd: PilotCommand, forward: float, turn: float, roll_right: float, w: float) -> void:
	var nose_up := 1.0
	var roll_sign := 1.0
	var sticks := input_source as TwinStickPilotInput
	if sticks != null:
		nose_up = -1.0 if sticks.invert_pitch else 1.0
		roll_sign = -1.0 if sticks.invert_roll else 1.0
	# Average and half difference back into each stick: R = avg + diff, L = avg - diff.
	var twist_diff := cmd.rotation.x * nose_up                       # + = clockwise = knuckles up
	var side_diff := roll_right * roll_sign
	var t := deg_to_rad(twist_travel_deg)
	var r := deg_to_rad(roll_travel_deg)
	_pose(left_bar, Vector3(clampf(-twist_diff, -1.0, 1.0) * t, 0.0, 0.0), w)
	_pose(right_bar, Vector3(clampf(twist_diff, -1.0, 1.0) * t, 0.0, 0.0), w)
	# Top to the right = a negative turn about +Z.
	_pose(left_roll, Vector3(0.0, 0.0, -clampf(cmd.translation.x - side_diff, -1.0, 1.0) * r), w)
	_pose(right_roll, Vector3(0.0, 0.0, -clampf(cmd.translation.x + side_diff, -1.0, 1.0) * r), w)
	_track(left_slide, clampf(forward - turn, -1.0, 1.0) * slide_travel, w)
	_track(right_slide, clampf(forward + turn, -1.0, 1.0) * slide_travel, w)
	_light_rail(left_rail_lamps, left_slide)
	_light_rail(right_rail_lamps, right_slide)
	var heave := clampf(cmd.translation.y, -1.0, 1.0)
	_track(right_pedal, heave * pedal_stroke, w, pedal_rail_rise)
	_track(left_pedal, -heave * pedal_stroke, w, pedal_rail_rise)
	var toes := 1.0 if cmd.brake_full else 0.7 if cmd.brake else 0.0
	_pose(left_pedal, Vector3(-toes * deg_to_rad(brake_travel_deg), 0.0, 0.0), w)
	_pose(right_pedal, Vector3(-toes * deg_to_rad(brake_travel_deg), 0.0, 0.0), w)


## Lights the lamps between the rail's rear end and its carriage.
func _light_rail(lamps: GeometryInstance3D, slide: Node3D) -> void:
	if lamps != null and slide != null:
		lamps.set_instance_shader_parameter(&"lit_from", slide.position.z)


func _pedals(cmd: PilotCommand, p: float, w: float) -> void:
	_pose(right_pedal, Vector3(-maxf(cmd.translation.y, 0.0) * p, 0.0, 0.0), w)
	_pose(left_pedal, Vector3(-maxf(-cmd.translation.y, 0.0) * p, 0.0, 0.0), w)
	_heave = lerpf(_heave, cmd.translation.y, w)
	if pedal_stroke != 0.0:
		_slide(right_pedal, maxf(_heave, 0.0) * pedal_stroke)
		_slide(left_pedal, maxf(-_heave, 0.0) * pedal_stroke)


## Slides a node toward `amount` along its own forward axis (rising `rise` per metre),
## smoothed like the turns.
func _track(node: Node3D, amount: float, weight: float, rise: float = 0.0) -> void:
	if node == null:
		return
	var now := lerpf(_slide_now[node], amount, weight)
	_slide_now[node] = now
	_slide(node, now, rise)


## Moves a node along its own forward axis from where it rests.
func _slide(node: Node3D, amount: float, rise: float = 0.0) -> void:
	if node != null:
		node.position = (_rest_origin[node] as Vector3) + (_rest[node] as Basis) * Vector3(0.0, amount * rise, -amount)


func _pose(node: Node3D, euler: Vector3, weight: float) -> void:
	if node == null:
		return
	var now: Vector3 = (_pose_now[node] as Vector3).lerp(euler, weight)
	_pose_now[node] = now
	node.basis = (_rest[node] as Basis) * Basis.from_euler(now)
