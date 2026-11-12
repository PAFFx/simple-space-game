class_name HatchCockpitParts
extends Node

## Cockpit parts of the suit's hatch (CockpitHatch), an airlock:
##   - the guarded hatch lever on the right console: click the striped guard to lift
##     (left) or lower (right) it; with it up, the lever pulls (left: open) or pushes
##     (right: close) the hatch. It sits pulled while the hatch is open.
##   - on the hatch timeline: the seat turns (with the pedals, footrest, right armrest
##     and the main and right monitors; the left armrest and monitor stay) to clear the
##     way, then the cockpit's inner door slides apart. The screen opening and the outer
##     door are the CockpitHatch's own.

@export var model_root: Node
@export var handle_name: StringName = &"HatchHandle"
@export var guard_name: StringName = &"HatchGuard"
@export var seat_name: StringName = &"SeatSwing"
@export var inner_door_names: Array[StringName] = [&"InnerDoorL", &"InnerDoorR"]
@export var handle_pull_deg: float = 60.0
@export var handle_rate_deg: float = 360.0
@export var guard_open_deg: float = -115.0  # flips forward, away from the pilot
@export var guard_rate_deg: float = 500.0
## Seat turn about the vertical axis (− = its front goes right).
@export var seat_turn_deg: float = -40.0
@export var seat_window := Vector2(0.0, 0.25)
@export var inner_door_window := Vector2(0.35, 0.6)

var guard_open := false

var _hatch: CockpitHatch
var _handle: Node3D
var _guard: Node3D
var _seat: Node3D
var _doors: Array[Node3D] = []
var _rest := {}
var _handle_angle := 0.0
var _guard_angle := 0.0


func _ready() -> void:
	var root := model_root if model_root != null else get_parent()
	_handle = root.find_child(handle_name, true, false) as Node3D
	_guard = root.find_child(guard_name, true, false) as Node3D
	_seat = root.find_child(seat_name, true, false) as Node3D
	for door_name in inner_door_names:
		var d := root.find_child(door_name, true, false) as Node3D
		if d != null:
			_doors.append(d)
	for n in [_handle, _guard, _seat] + _doors:
		if n != null:
			_rest[n] = n.transform
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	if _guard != null:
		_clickable(_guard, Vector3(0, 0.036, 0.047), 0.04, "HATCH GUARD  lift / lower",
				func(direction: int) -> void: guard_open = direction < 0)
	if _handle != null:
		_clickable(_handle, Vector3(0, 0.016, -0.05), 0.03, "HATCH  pull: open / push: close", _on_handle)


func _on_handle(direction: int) -> void:
	if _hatch == null or not guard_open:
		return
	if direction < 0:
		_hatch.open()
	else:
		_hatch.close()


func _process(delta: float) -> void:
	if _guard != null:
		var g := deg_to_rad(guard_open_deg) if guard_open else 0.0
		_guard_angle = move_toward(_guard_angle, g, deg_to_rad(guard_rate_deg) * delta)
		_guard.transform = _rest[_guard] * Transform3D(Basis(Vector3.RIGHT, _guard_angle), Vector3.ZERO)
	if _hatch == null:
		return
	if _handle != null:
		var h := deg_to_rad(handle_pull_deg) if _hatch.is_open() else 0.0
		_handle_angle = move_toward(_handle_angle, h, deg_to_rad(handle_rate_deg) * delta)
		_handle.transform = _rest[_handle] * Transform3D(Basis(Vector3.RIGHT, _handle_angle), Vector3.ZERO)
	if _seat != null:
		var t := _progress(seat_window)
		_seat.transform = _rest[_seat] * Transform3D(Basis(Vector3.UP, deg_to_rad(seat_turn_deg) * t), Vector3.ZERO)
	var d := _progress(inner_door_window)
	for door in _doors:
		var rest: Transform3D = _rest[door]
		var side := signf(rest.origin.x) if absf(rest.origin.x) > 1e-4 else 1.0
		# Each half slides outward by its own width (built half the opening wide).
		door.transform = rest.translated(Vector3(side * absf(rest.origin.x) * 2.05 * d, 0, 0))


func _progress(window: Vector2) -> float:
	var span := maxf(window.y - window.x, 1e-3)
	return smoothstep(0.0, 1.0, clampf((_hatch.amount - window.x) / span, 0.0, 1.0))


## A click target riding on `part` (at `offset` in its frame), for click mode.
func _clickable(part: Node3D, offset: Vector3, radius: float, tip: String, on_click: Callable) -> void:
	var c := CockpitClickable.new()
	c.name = String(part.name) + "Click"
	c.position = offset
	c.pick_radius = radius
	c.tooltip = tip
	c.clicked.connect(on_click)
	part.add_child.call_deferred(c)
