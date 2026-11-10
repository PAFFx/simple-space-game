class_name PilotCamera
extends Camera3D

## The pilot's eye. With physics interpolation on, the suit is drawn between
## physics ticks, but a camera steered by the mouse must update every frame.
## So the camera is top-level, not interpolated itself, and each frame follows
## its parent's *interpolated* transform plus the look rotation. That keeps the
## view smooth at any refresh rate without lagging the mouse.


var look_rotation := Basis.IDENTITY

var _mount: Node3D


func _ready() -> void:
	_mount = get_parent() as Node3D
	look_rotation = basis
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Before the sensor head and HUD read the camera this frame.
	process_priority = -10
	_follow()


## Called by MouseLookController instead of setting the rotation directly.
func set_look_rotation(value: Basis) -> void:
	look_rotation = value
	_follow()


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	if _mount != null:
		global_transform = _mount.get_global_transform_interpolated() * Transform3D(look_rotation)
