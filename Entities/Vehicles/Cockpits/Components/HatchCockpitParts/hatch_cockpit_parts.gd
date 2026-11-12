class_name HatchCockpitParts
extends Node

## Cockpit parts that move with the suit's hatch (CockpitHatch), on its timeline:
## the guarded hatch switch (the guard flips up as the hatch starts opening and drops
## once it's sealed; the button dips on each press) and the centre display, which folds
## down onto the pilot's lap so it doesn't block the way out.

@export var model_root: Node
@export var guard_name: StringName = &"HatchGuard"
@export var button_name: StringName = &"HatchButton"
@export var display_name: StringName = &"CentreDisplay"
@export var guard_open_deg: float = 110.0
## Share of the hatch timeline the guard takes to flip up.
@export var guard_window: float = 0.08
@export var button_travel: float = 0.004
@export var button_press_time: float = 0.25
@export var display_fold_deg: float = 70.0
@export var display_window := Vector2(0.0, 0.25)

var _hatch: CockpitHatch
var _guard: Node3D
var _button: Node3D
var _display: Node3D
var _rest := {}
var _press := 0.0


func _ready() -> void:
	var root := model_root if model_root != null else get_parent()
	_guard = root.find_child(guard_name, true, false) as Node3D
	_button = root.find_child(button_name, true, false) as Node3D
	_display = root.find_child(display_name, true, false) as Node3D
	for n in [_guard, _button, _display]:
		if n != null:
			_rest[n] = n.transform
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	if _hatch != null:
		_hatch.state_changed.connect(func(_open: bool) -> void: _press = button_press_time)


func _process(delta: float) -> void:
	if _hatch == null:
		return
	var a := _hatch.amount
	_press = maxf(_press - delta, 0.0)
	if _guard != null:
		var t := smoothstep(0.0, 1.0, clampf(a / maxf(guard_window, 1e-3), 0.0, 1.0))
		_guard.transform = _rest[_guard] * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(guard_open_deg) * t), Vector3.ZERO)
	if _button != null:
		var dip := sin(PI * _press / maxf(button_press_time, 1e-3)) * button_travel
		_button.transform = (_rest[_button] as Transform3D).translated_local(Vector3.DOWN * dip)
	if _display != null:
		var span := maxf(display_window.y - display_window.x, 1e-3)
		var t := smoothstep(0.0, 1.0, clampf((a - display_window.x) / span, 0.0, 1.0))
		_display.transform = _rest[_display] * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(display_fold_deg) * t), Vector3.ZERO)
