class_name MouseLookController
extends Node

## Simple look component. Attach as a child of any Node3D (typically a Camera3D)
## and it will rotate that node from the mouse, or from a joystick's mini-stick: the
## stick pans at a rate and the view stays where it is left, until a button recentres it.
## Yaw and pitch are tracked separately and reconstructed each frame to prevent
## roll accumulation from compounding floating-point rotations.

## Mouse sensitivity in degrees per pixel.
@export var sensitivity: float = 0.1

## Maximum pitch angle in degrees (applied symmetrically up and down).
@export var pitch_limit: float = 85.0

## Capture the mouse automatically when this node enters the scene tree.
## Disable if you want to manage mouse capture yourself.
@export var capture_on_ready: bool = true
## While the mouse steers the suit (PilotInputActions.MOUSE_STEER held), the look
## eases back to its rest direction with this time constant, s. 0 = stay put.
@export var recenter_time: float = 0.15

@export_group("Stick look")
## Joystick carrying the look mini-stick, by name (see JoyDevices). Empty = mouse only.
@export var stick_name: String = "EVO R"
@export var stick_yaw_axis: int = 3
@export var stick_pitch_axis: int = 4
## Recentres the view (eased by stick_recenter_time). -1 = none.
@export var stick_recenter_button: int = 19
## Pan rate at full deflection, deg/s.
@export var stick_rate: float = 110.0
@export_range(0.0, 0.5) var stick_deadzone: float = 0.12
## 0 = linear, 1 = fully cubic: small deflections pan slowly.
@export_range(0.0, 1.0) var stick_expo: float = 0.6
## The pan eases in and out with this time constant, s. 0 = instant.
@export var stick_smoothing: float = 0.12
@export var stick_recenter_time: float = 0.25

var _stick_rate := Vector2.ZERO   ## Smoothed (yaw, pitch) pan rate, deg/s
var _recentering := false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _rest_yaw: float = 0.0
var _rest_pitch: float = 0.0


func _ready() -> void:
	var target := get_parent() as Node3D
	if target != null:
		# Initialise from the node's current rotation so it doesn't snap on start.
		_yaw   = rad_to_deg(target.rotation.y)
		_pitch = rad_to_deg(target.rotation.x)
	_rest_yaw = _yaw
	_rest_pitch = _pitch
	if capture_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or PilotInputActions.is_mouse_steering():
		return
	var target := _active_target()
	if target == null:
		return
	_recentering = false
	_yaw   -= event.relative.x * sensitivity
	_pitch  = clamp(_pitch - event.relative.y * sensitivity, -pitch_limit, pitch_limit)
	_apply(target)


func _process(delta: float) -> void:
	var target := _active_target()
	if target == null:
		_stick_rate = Vector2.ZERO
		return
	_stick_look(target, delta)
	var time := recenter_time if PilotInputActions.is_mouse_steering() \
			else (stick_recenter_time if _recentering else 0.0)
	if time <= 0.0:
		return
	if is_equal_approx(_yaw, _rest_yaw) and is_equal_approx(_pitch, _rest_pitch):
		_recentering = false
		return
	var w := 1.0 - exp(-delta / time)
	# Shortest way round in yaw, so a look over the shoulder doesn't unwind 360°.
	_yaw = _rest_yaw + wrapf(_yaw - _rest_yaw, -180.0, 180.0)
	_yaw = lerpf(_yaw, _rest_yaw, w)
	_pitch = lerpf(_pitch, _rest_pitch, w)
	if absf(_yaw - _rest_yaw) < 0.01 and absf(_pitch - _rest_pitch) < 0.01:
		_yaw = _rest_yaw
		_pitch = _rest_pitch
	_apply(target)


## Pans with the mini-stick; the recentre button starts easing back to rest.
func _stick_look(target: Node3D, delta: float) -> void:
	var device := JoyDevices.find(stick_name)
	var demand := Vector2.ZERO
	if device >= 0:
		demand = Vector2(
			JoyDevices.shape(Input.get_joy_axis(device, stick_yaw_axis as JoyAxis), stick_deadzone, stick_expo),
			JoyDevices.shape(Input.get_joy_axis(device, stick_pitch_axis as JoyAxis), stick_deadzone, stick_expo))
		if stick_recenter_button >= 0 \
				and Input.is_joy_button_pressed(device, stick_recenter_button as JoyButton):
			_recentering = true
	if demand != Vector2.ZERO:
		_recentering = false
	var w := 1.0 if stick_smoothing <= 0.0 else 1.0 - exp(-delta / stick_smoothing)
	_stick_rate = _stick_rate.lerp(demand * stick_rate, w)
	if demand == Vector2.ZERO and _stick_rate.length() < 0.05:
		_stick_rate = Vector2.ZERO
	if _stick_rate == Vector2.ZERO or _recentering:
		return
	# Same directions as the mouse: stick right looks right, stick down looks down.
	_yaw -= _stick_rate.x * delta
	_pitch = clampf(_pitch - _stick_rate.y * delta, -pitch_limit, pitch_limit)
	_apply(target)


## The camera to steer, or null (e.g. while an external view is current).
func _active_target() -> Node3D:
	var target := get_parent() as Node3D
	if target is Camera3D and not (target as Camera3D).current:
		return null
	return target


func _apply(target: Node3D) -> void:
	var look := Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)
	if target.has_method(&"set_look_rotation"):
		target.call(&"set_look_rotation", Basis.from_euler(look))
	else:
		target.rotation = look
