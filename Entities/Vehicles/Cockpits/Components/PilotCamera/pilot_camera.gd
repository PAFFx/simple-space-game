class_name PilotCamera
extends Camera3D

## The pilot's eye. With physics interpolation on, the suit is drawn between
## physics ticks, but a camera steered by the mouse must update every frame.
## So the camera is top-level, not interpolated itself, and each frame follows
## its parent's *interpolated* transform plus the look rotation. That keeps the
## view smooth at any refresh rate without lagging the mouse.
##
## The hull's inner parts (chest cavity, hatch flaps) are only drawn while the hatch
## is unsealed. Sealed, the pilot sees the panoramic screen, and the cockpit gimbal
## turns inside the hull, so the cavity walls would cut through the screen.


var look_rotation := Basis.IDENTITY

var _mount: Node3D
var _hatch: CockpitHatch


func _ready() -> void:
	_mount = get_parent() as Node3D
	look_rotation = basis
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Before the sensor head and HUD read the camera this frame.
	process_priority = -10
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	_update_hull_layer()
	_follow()


## Called by MouseLookController instead of setting the rotation directly.
func set_look_rotation(value: Basis) -> void:
	look_rotation = value
	_follow()


func _process(_delta: float) -> void:
	_update_hull_layer()
	_follow()


func _update_hull_layer() -> void:
	if _hatch != null:
		set_cull_mask_value(3, _hatch.is_unsealed())  # Layers.VEHICLE_FP (bit 2)


func _follow() -> void:
	if _mount != null:
		global_transform = _mount.get_global_transform_interpolated() * Transform3D(look_rotation)
