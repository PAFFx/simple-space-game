class_name ViewSwitcher
extends Node

## Toggles between the cockpit camera and an external camera
## (PilotInputActions.TOGGLE_VIEW, or holding the look stick's button, see StickLook).
## The cockpit camera is discovered from the vehicle. When the pilot dies or the suit is
## destroyed (DamageModel), the view goes outside, pulled back, until the suit is repaired.

@export var external_camera: Camera3D
## Optional override — defaults to the vehicle cockpit's player camera.
@export var cockpit_camera: Camera3D
@export var start_external: bool = false
## Only its button is used here; empty = a StickLook with its defaults.
@export var stick: StickLook

## How far the external camera pulls back when the suit is destroyed, m.
@export var destroyed_distance: float = 500.0

var _external := false
var _dead := false
var _distance_before := -1.0


func _ready() -> void:
	PilotInputActions.ensure_defaults()
	if stick == null:
		stick = StickLook.new()
	if cockpit_camera == null:
		var vehicle := VehicleBase.find_vehicle(self)
		if vehicle != null and vehicle.get_cockpit() != null:
			cockpit_camera = vehicle.get_cockpit().get_player_camera()
	_set_external.call_deferred(start_external)
	# The DamageModel is made after the vehicle's components are ready.
	_hook_damage.call_deferred()


func _process(delta: float) -> void:
	stick.update(delta)
	if stick.held and not _dead:
		_set_external(not _external)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PilotInputActions.TOGGLE_VIEW) and not _dead:
		_set_external(not _external)


func is_external() -> bool:
	return _external


func _set_external(value: bool) -> void:
	_external = value
	var cam := external_camera if value else cockpit_camera
	if cam != null:
		cam.make_current()


func _hook_damage() -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	var damage := vehicle.find_component(DamageModel) as DamageModel if vehicle != null else null
	if damage == null:
		return
	damage.pilot_killed.connect(_on_destroyed)
	damage.reactor_breached.connect(_on_destroyed)
	damage.repaired.connect(_on_repaired)


func _on_destroyed() -> void:
	if _dead:
		return
	_dead = true
	var orbit := external_camera as OrbitCamera
	if orbit != null:
		_distance_before = orbit.distance
		orbit.distance = maxf(orbit.distance, destroyed_distance)
	_set_external(true)


func _on_repaired() -> void:
	if not _dead:
		return
	_dead = false
	var orbit := external_camera as OrbitCamera
	if orbit != null and _distance_before > 0.0:
		orbit.distance = _distance_before
	_set_external(start_external)
