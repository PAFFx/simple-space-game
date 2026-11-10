class_name ViewSwitcher
extends Node

## Toggles between the cockpit camera and an external camera
## (PilotInputActions.TOGGLE_VIEW). The cockpit camera is discovered from the vehicle.

@export var external_camera: Camera3D
## Optional override — defaults to the vehicle cockpit's player camera.
@export var cockpit_camera: Camera3D
@export var start_external: bool = false

var _external := false


func _ready() -> void:
	PilotInputActions.ensure_defaults()
	if cockpit_camera == null:
		var vehicle := VehicleBase.find_vehicle(self)
		if vehicle != null and vehicle.get_cockpit() != null:
			cockpit_camera = vehicle.get_cockpit().get_player_camera()
	_set_external.call_deferred(start_external)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PilotInputActions.TOGGLE_VIEW):
		_set_external(not _external)


func is_external() -> bool:
	return _external


func _set_external(value: bool) -> void:
	_external = value
	var cam := external_camera if value else cockpit_camera
	if cam != null:
		cam.make_current()
