class_name HatchCockpitParts
extends Node

## Cockpit parts of the suit's hatch (CockpitHatch):
##   - the guarded hatch switch: click the yellow guard to lift it (left) or lower it
##     (right); with the guard up, click the red button to open or close the hatch.
##     The button dips on each press.
##   - the centre display, which folds onto the pilot's lap on the hatch's timeline so
##     it doesn't block the way out.

@export var model_root: Node
@export var guard_name: StringName = &"HatchGuard"
@export var button_name: StringName = &"HatchButton"
@export var display_name: StringName = &"CentreDisplay"
@export var guard_open_deg: float = 110.0
@export var guard_rate_deg: float = 500.0
@export var button_travel: float = 0.004
@export var button_press_time: float = 0.25
@export var display_fold_deg: float = 70.0
@export var display_window := Vector2(0.0, 0.25)

var guard_open := false

var _hatch: CockpitHatch
var _guard: Node3D
var _button: Node3D
var _display: Node3D
var _rest := {}
var _press := 0.0
var _guard_angle := 0.0


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
	if _guard != null:
		var c := _clickable(_guard, Vector3(0, 0.02, -0.03), 0.03, "HATCH GUARD  lift / lower")
		c.clicked.connect(func(direction: int) -> void: guard_open = direction < 0)
	if _button != null:
		var b := _clickable(_button, Vector3(0, 0.006, 0), 0.016, "HATCH  open / close")
		b.clicked.connect(_on_button)


func _on_button(_direction: int) -> void:
	if not guard_open or _hatch == null:
		return
	_press = button_press_time
	_hatch.toggle()


func _process(delta: float) -> void:
	_press = maxf(_press - delta, 0.0)
	if _guard != null:
		var target := deg_to_rad(guard_open_deg) if guard_open else 0.0
		_guard_angle = move_toward(_guard_angle, target, deg_to_rad(guard_rate_deg) * delta)
		_guard.transform = _rest[_guard] * Transform3D(Basis(Vector3.RIGHT, _guard_angle), Vector3.ZERO)
	if _button != null:
		var dip := sin(PI * _press / maxf(button_press_time, 1e-3)) * button_travel
		_button.transform = (_rest[_button] as Transform3D).translated_local(Vector3.DOWN * dip)
	if _display != null and _hatch != null:
		var span := maxf(display_window.y - display_window.x, 1e-3)
		var t := smoothstep(0.0, 1.0, clampf((_hatch.amount - display_window.x) / span, 0.0, 1.0))
		_display.transform = _rest[_display] * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(display_fold_deg) * t), Vector3.ZERO)


## A click target riding on `part` (at `offset` in its frame), for click mode.
func _clickable(part: Node3D, offset: Vector3, radius: float, tip: String) -> CockpitClickable:
	var c := CockpitClickable.new()
	c.name = String(part.name) + "Click"
	c.position = offset
	c.pick_radius = radius
	c.tooltip = tip
	part.get_parent().add_child.call_deferred(c)
	# Ride the part's rest pose (not its swing), so the guard stays clickable when lifted.
	c.set_deferred("transform", (_rest[part] as Transform3D) * Transform3D(Basis.IDENTITY, offset))
	return c
