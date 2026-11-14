class_name MouseLookController
extends Node

## Simple look component. Attach as a child of any Node3D (typically a Camera3D)
## and it will rotate that node from the mouse, or from a joystick's mini-stick: the
## stick pans at a rate and the view stays where it is left, until a tap of its button
## recentres it (see StickLook).
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

## Mini-stick look; empty = a StickLook with its defaults.
@export var stick: StickLook

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
	if stick == null:
		stick = StickLook.new()
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
	stick.update(delta)
	if target == null:
		return
	_stick_look(target, delta)
	var time := recenter_time if PilotInputActions.is_mouse_steering() \
			else (stick.recenter_time if _recentering else 0.0)
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


## Pans with the mini-stick; a tap of its button starts easing back to rest.
func _stick_look(target: Node3D, delta: float) -> void:
	if stick.tapped:
		_recentering = true
	if stick.moving:
		_recentering = false
	if stick.pan == Vector2.ZERO or _recentering:
		return
	_yaw -= stick.pan.x * delta
	_pitch = clampf(_pitch + stick.pan.y * delta, -pitch_limit, pitch_limit)
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
