class_name StickLook
extends Resource

## A joystick's mini-stick as a look control: pans at a rate, eased in and out, plus
## one button that recentres the view on a tap and switches the view when held.
## Call update() every frame, also while the view it steers isn't current, so the
## button's press time stays right.

## Joystick carrying the mini-stick, by name (see JoyDevices). Empty = off.
@export var stick_name: String = "EVO L"
@export var yaw_axis: int = 3
@export var pitch_axis: int = 4
@export var invert_yaw: bool = false
@export var invert_pitch: bool = false
## Tap = recentre, hold = switch view. -1 = none.
@export var button: int = 19
@export var hold_time: float = 0.35
## Pan rate at full deflection, deg/s.
@export var rate: float = 110.0
@export_range(0.0, 0.5) var deadzone: float = 0.12
## 0 = linear, 1 = fully cubic: small deflections pan slowly.
@export_range(0.0, 1.0) var expo: float = 0.6
## The pan eases in and out with this time constant, s. 0 = instant.
@export var smoothing: float = 0.12
## Time constant of the eased recentre, s.
@export var recenter_time: float = 0.25

## Smoothed pan rate, deg/s: x = toward the right, y = upward.
var pan := Vector2.ZERO
## The stick is deflected this frame.
var moving := false
## True on the frame the button is released after a short press.
var tapped := false
## True on the frame the button has been held for hold_time.
var held := false

var _pressed_for := -1.0   ## < 0 = not pressed


func update(delta: float) -> void:
	var device := JoyDevices.find(stick_name)
	var demand := Vector2.ZERO
	var down := false
	if device >= 0:
		demand = Vector2(
			JoyDevices.shape(Input.get_joy_axis(device, yaw_axis as JoyAxis), deadzone, expo),
			JoyDevices.shape(Input.get_joy_axis(device, pitch_axis as JoyAxis), deadzone, expo))
		demand *= Vector2(-1.0 if invert_yaw else 1.0, -1.0 if invert_pitch else 1.0)
		down = button >= 0 and Input.is_joy_button_pressed(device, button as JoyButton)
	moving = demand != Vector2.ZERO
	var w := 1.0 if smoothing <= 0.0 else 1.0 - exp(-delta / smoothing)
	pan = pan.lerp(demand * rate, w)
	if not moving and pan.length() < 0.05:
		pan = Vector2.ZERO

	tapped = false
	held = false
	if down:
		var before := maxf(_pressed_for, 0.0)
		_pressed_for = before + delta
		held = before < hold_time and _pressed_for >= hold_time
	else:
		tapped = _pressed_for >= 0.0 and _pressed_for < hold_time
		_pressed_for = -1.0
