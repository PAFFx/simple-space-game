class_name MouseLookController
extends Node

## Simple mouse-look component. Attach as a child of any Node3D (typically a
## Camera3D) and it will rotate that node based on mouse input.
## Yaw and pitch are tracked separately and reconstructed each frame to prevent
## roll accumulation from compounding floating-point rotations.

## Mouse sensitivity in degrees per pixel.
@export var sensitivity: float = 0.1

## Maximum pitch angle in degrees (applied symmetrically up and down).
@export var pitch_limit: float = 85.0

## Capture the mouse automatically when this node enters the scene tree.
## Disable if you want to manage mouse capture yourself.
@export var capture_on_ready: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	var target := get_parent() as Node3D
	if target != null:
		# Initialise from the node's current rotation so it doesn't snap on start.
		_yaw   = rad_to_deg(target.rotation.y)
		_pitch = rad_to_deg(target.rotation.x)
	if capture_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var target := get_parent() as Node3D
	if target == null:
		return
	# Don't steer an inactive camera (e.g. while an external view is current).
	if target is Camera3D and not (target as Camera3D).current:
		return

	_yaw   -= event.relative.x * sensitivity
	_pitch  = clamp(_pitch - event.relative.y * sensitivity, -pitch_limit, pitch_limit)
	target.rotation = Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)
