class_name HatchCockpitParts
extends Node

## Cockpit parts of the suit's hatch (CockpitHatch):
##   - the yellow/black striped hatch handle on the right console: left click pulls it
##     up (open), right click pushes it down (close). It sits pulled while the hatch is
##     open.
##   - the right armrest, carrying the main and right monitors, which swings out on the
##     hatch's timeline (before the screen and door open) to clear the way out.

@export var model_root: Node
@export var handle_name: StringName = &"HatchHandle"
@export var armrest_name: StringName = &"RightArmrest"
@export var handle_pull_deg: float = 60.0
@export var handle_rate_deg: float = 360.0
## Swing outward about the armrest's vertical axis (− = its front goes right).
@export var armrest_swing_deg: float = -60.0
@export var armrest_window := Vector2(0.0, 0.3)

var _hatch: CockpitHatch
var _handle: Node3D
var _armrest: Node3D
var _rest := {}
var _handle_angle := 0.0


func _ready() -> void:
	var root := model_root if model_root != null else get_parent()
	_handle = root.find_child(handle_name, true, false) as Node3D
	_armrest = root.find_child(armrest_name, true, false) as Node3D
	for n in [_handle, _armrest]:
		if n != null:
			_rest[n] = n.transform
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	if _handle != null:
		var c := CockpitClickable.new()
		c.name = "HatchHandleClick"
		c.position = Vector3(0, 0.016, -0.05)  # the striped grip, in the handle's frame
		c.pick_radius = 0.035
		c.tooltip = "HATCH  pull: open / push: close"
		c.clicked.connect(_on_handle)
		_handle.add_child.call_deferred(c)


func _on_handle(direction: int) -> void:
	if _hatch == null:
		return
	if direction < 0:
		_hatch.open()
	else:
		_hatch.close()


func _process(delta: float) -> void:
	if _hatch == null:
		return
	if _handle != null:
		var target := deg_to_rad(handle_pull_deg) if _hatch.is_open() else 0.0
		_handle_angle = move_toward(_handle_angle, target, deg_to_rad(handle_rate_deg) * delta)
		_handle.transform = _rest[_handle] * Transform3D(Basis(Vector3.RIGHT, _handle_angle), Vector3.ZERO)
	if _armrest != null:
		var span := maxf(armrest_window.y - armrest_window.x, 1e-3)
		var t := smoothstep(0.0, 1.0, clampf((_hatch.amount - armrest_window.x) / span, 0.0, 1.0))
		_armrest.transform = _rest[_armrest] * Transform3D(Basis(Vector3.UP, deg_to_rad(armrest_swing_deg) * t), Vector3.ZERO)
