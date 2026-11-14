class_name TwinStickPilotInput
extends KeyboardPilotInput

## Keyboard plus two flight sticks flown tank style (found by name, see JoyDevices):
## Each pair of axes is mixed: the average translates, the difference turns.
##   fore/aft     average = forward / back, difference = yaw (right stick forward =
##                yaw left), or roll the same way while roll_button is held; on these
##                sticks forward reads positive, see invert_surge
##   twist        average = up / down (clockwise = up), difference = pitch
##                (right clockwise against left counter-clockwise = nose up)
##   left/right   average = strafe
## invert_heave / invert_pitch flip the twist mixes.
##
## Stick travel is the throttle (PilotCommand.analog_thrust), so there is no boost
## button, only full boost. The stick demand adds onto the keyboard's; with a stick
## missing this is plain keyboard input.

@export_group("Devices")
@export var left_stick_name: String = "EVO L"
@export var right_stick_name: String = "EVO R"

@export_group("Axes")
@export var surge_axis: int = 1    ## Both sticks
## Stick forward reads positive on this axis (the VKB default), not negative.
@export var invert_surge: bool = true
@export var strafe_axis: int = 0   ## Both sticks
@export var heave_axis: int = 2    ## Both sticks' twist
@export var invert_heave: bool = false
@export var invert_pitch: bool = false

@export_group("Buttons")
@export var full_boost_button: int = 4   ## Right stick, hold
@export var brake_button: int = 21       ## Left stick, hold
@export var full_brake_button: int = 20  ## Left stick, hold
@export var roll_button: int = 4         ## Left stick, hold: the yaw control rolls
@export var precision_button: int = 3    ## Left stick, toggles

@export_group("Response")
## Expo softens the centre: 0 = linear, 1 = fully cubic. Full travel is always full demand.
@export_range(0.0, 1.0) var translation_expo: float = 0.3
@export_range(0.0, 1.0) var rotation_expo: float = 0.4
@export_range(0.0, 0.5) var deadzone: float = 0.08
## Twist springs centre less precisely than the gimbal.
@export_range(0.0, 0.5) var twist_deadzone: float = 0.1
## On the differences, so moving both sticks unevenly doesn't turn the suit.
@export_range(0.0, 0.5) var yaw_deadzone: float = 0.1
@export_range(0.0, 0.5) var pitch_deadzone: float = 0.12
## Gain on the fore/aft difference while it rolls: at 2 one stick alone gives full roll.
@export_range(1.0, 4.0) var roll_sensitivity: float = 2.0
## Smoothing of the shaped demand, s. 0 = off.
@export var smoothing: float = 0.04
## Median over this many ticks of each raw axis, against sensor spikes. 1 = off.
@export_range(1, 7, 2) var spike_filter_ticks: int = 3

var _left := -1
var _right := -1
var _history := {}                 ## device * 16 + axis → last raw samples
var _stick_translation := Vector3.ZERO
var _stick_rotation := Vector3.ZERO
var _precision_held := false


func _ready() -> void:
	super._ready()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_find_sticks()


func has_sticks() -> bool:
	return _left >= 0 and _right >= 0


func poll_command() -> PilotCommand:
	var cmd := super.poll_command()
	if not has_sticks():
		return cmd
	var fore := -1.0 if invert_surge else 1.0
	var left_surge := _axis(_left, surge_axis) * fore
	var right_surge := _axis(_right, surge_axis) * fore
	var up := -1.0 if invert_heave else 1.0
	var nose_up := -1.0 if invert_pitch else 1.0
	var left_twist := _axis(_left, heave_axis)
	var right_twist := _axis(_right, heave_axis)
	var side := (_axis(_left, strafe_axis) + _axis(_right, strafe_axis)) * 0.5
	var rolling := _button(_left, roll_button)
	var target_t := Vector3(
		JoyDevices.shape(side, deadzone, translation_expo),
		JoyDevices.shape((left_twist + right_twist) * 0.5 * up, twist_deadzone, translation_expo),
		JoyDevices.shape((left_surge + right_surge) * 0.5, deadzone, translation_expo))
	var turn_gain := roll_sensitivity if rolling else 1.0
	var turn := JoyDevices.shape((left_surge - right_surge) * 0.5 * turn_gain, yaw_deadzone, rotation_expo)
	# PilotCommand signs: +x = pitch up, +y = yaw left, +z = roll left.
	var target_r := Vector3(
		JoyDevices.shape((right_twist - left_twist) * 0.5 * nose_up, pitch_deadzone, rotation_expo),
		0.0 if rolling else turn,
		turn if rolling else 0.0)
	var delta := get_physics_process_delta_time()
	var w := 1.0 if smoothing <= 0.0 else 1.0 - exp(-delta / smoothing)
	_stick_translation = _ease(_stick_translation, target_t, w)
	_stick_rotation = _ease(_stick_rotation, target_r, w)

	# The stick is the throttle only while the keys aren't pushing too.
	cmd.analog_thrust = _stick_translation != Vector3.ZERO and cmd.translation == Vector3.ZERO
	cmd.translation = (cmd.translation + _stick_translation).clamp(-Vector3.ONE, Vector3.ONE)
	cmd.rotation = (cmd.rotation + _stick_rotation).clamp(-Vector3.ONE, Vector3.ONE)
	cmd.boost_full = cmd.boost_full or _button(_right, full_boost_button)
	cmd.brake_full = cmd.brake_full or _button(_left, full_brake_button)
	cmd.brake = cmd.brake or cmd.brake_full or _button(_left, brake_button)
	var precision_held := _button(_left, precision_button)
	cmd.toggle_precision = precision_held and not _precision_held
	_precision_held = precision_held
	return cmd


## Raw axis value. Override to script the sticks (probes).
func _raw_axis(device: int, axis: int) -> float:
	return Input.get_joy_axis(device, axis as JoyAxis)


func _button(device: int, button: int) -> bool:
	return button >= 0 and Input.is_joy_button_pressed(device, button as JoyButton)


## Median of the axis' last few samples: a spike of a tick or two never gets through.
func _axis(device: int, axis: int) -> float:
	var raw := _raw_axis(device, axis)
	if spike_filter_ticks <= 1:
		return raw
	var key := device * 16 + axis
	var samples: Array = _history.get_or_add(key, [])
	samples.append(raw)
	if samples.size() > spike_filter_ticks:
		samples.pop_front()
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[sorted.size() >> 1]


## Eases toward the target, landing exactly on a released (zero) axis.
func _ease(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var out := from.lerp(to, weight)
	for k in 3:
		if to[k] == 0.0 and absf(out[k]) < 0.02:
			out[k] = 0.0
	return out


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_find_sticks()


func _find_sticks() -> void:
	_left = JoyDevices.find(left_stick_name)
	_right = JoyDevices.find(right_stick_name)
	_history.clear()
	if not has_sticks():
		_stick_translation = Vector3.ZERO
		_stick_rotation = Vector3.ZERO
