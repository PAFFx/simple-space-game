class_name HatchCockpitParts
extends Node

## Cockpit parts of the suit's hatch (CockpitHatch), an airlock:
##   - two handbrake-style levers on the seat's side beside the cushion (when the model has
##     them, after a fighter's seat arming handles): the lock above pivots at its front and
##     pulls up at its tail, the override below pivots at its rear and pulls up at its
##     front, under the lock's tail. Click to pull (left) or push (right). The override comes
##     up only with the lock up; both up opens the hatch, the override pushed down closes
##     it; the lock goes down only once the override is.
##   - else the guarded hatch lever on the right console: click the striped guard to lift
##     (left) or lower (right) it; with it up, the lever pulls (left: open) or pushes
##     (right: close) the hatch. It sits pulled while the hatch is open.
##   - on the hatch timeline: the seat turns (with the pedals, footrest, right armrest
##     and the main and right monitors; the left armrest and monitor stay) to clear the
##     way, then the cockpit's inner door slides apart. The screen opening and the outer
##     door are the CockpitHatch's own.

@export var model_root: Node
@export var handle_name: StringName = &"HatchHandle"
@export var guard_name: StringName = &"HatchGuard"
@export var lock_name: StringName = &"HatchLock"
@export var override_name: StringName = &"HatchOverride"
## How far each lever turns about its pivot (local +X, across the seat; + lifts a lever
## lying forward of its pivot), deg, and how fast.
@export var lock_lift_deg: float = -40.0
@export var override_lift_deg: float = 30.0
@export var lift_rate_deg: float = 300.0
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
## Nodes outside the model that turn with the seat (the camera mount, the pilot, a switch
## panel on a turning console).
@export var seat_riders: Array[Node3D] = []

var guard_open := false
var lock_up := false
var override_up := false

var _hatch: CockpitHatch
var _handle: Node3D
var _guard: Node3D
var _seat: Node3D
var _doors: Array[Node3D] = []
var _rest := {}
var _rider_rest := {}   # rider → its transform in the seat's frame
var _handle_angle := 0.0
var _guard_angle := 0.0
var _lock: Node3D
var _override: Node3D
var _lock_angle := 0.0
var _override_angle := 0.0


func _ready() -> void:
	var root := model_root if model_root != null else get_parent()
	_handle = root.find_child(handle_name, true, false) as Node3D
	_guard = root.find_child(guard_name, true, false) as Node3D
	_seat = root.find_child(seat_name, true, false) as Node3D
	_lock = root.find_child(lock_name, true, false) as Node3D
	_override = root.find_child(override_name, true, false) as Node3D
	for door_name in inner_door_names:
		var d := root.find_child(door_name, true, false) as Node3D
		if d != null:
			_doors.append(d)
	for n in [_handle, _guard, _seat, _lock, _override] + _doors:
		if n != null:
			_rest[n] = n.transform
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	if _hatch != null and _hatch.is_open():
		lock_up = true
		override_up = true
	if _lock != null:
		_clickable(_lock, Vector3(0.013, 0.0, 0.07), 0.045, "HATCH LOCK  pull: unlock / push: lock", _on_lock)
	if _override != null:
		_clickable(_override, Vector3(0.013, 0.0, -0.1), 0.05, "HATCH OVERRIDE HANDLE  pull: open / push: close", _on_override)
	if _guard != null:
		_clickable(_guard, Vector3(0, 0.036, 0.047), 0.04, "HATCH GUARD  lift / lower",
				func(direction: int) -> void: guard_open = direction < 0)
	if _handle != null:
		_clickable(_handle, Vector3(0, 0.016, -0.05), 0.03, "HATCH  pull: open / push: close", _on_handle)


func _on_lock(direction: int) -> void:
	if direction < 0:
		lock_up = true
	elif not override_up:
		lock_up = false


func _on_override(direction: int) -> void:
	if direction < 0:
		if not lock_up:
			return
		override_up = true
		if _hatch != null:
			_hatch.open()
	else:
		override_up = false
		if _hatch != null:
			_hatch.close()


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
	var rate := deg_to_rad(lift_rate_deg) * delta
	if _lock != null:
		_lock_angle = move_toward(_lock_angle, deg_to_rad(lock_lift_deg) if lock_up else 0.0, rate)
		_lock.transform = _rest[_lock] * Transform3D(Basis(Vector3.RIGHT, _lock_angle), Vector3.ZERO)
	if _override != null:
		_override_angle = move_toward(_override_angle, deg_to_rad(override_lift_deg) if override_up else 0.0, rate)
		_override.transform = _rest[_override] * Transform3D(Basis(Vector3.RIGHT, _override_angle), Vector3.ZERO)
	if _hatch == null:
		return
	if _handle != null:
		var h := deg_to_rad(handle_pull_deg) if _hatch.is_open() else 0.0
		_handle_angle = move_toward(_handle_angle, h, deg_to_rad(handle_rate_deg) * delta)
		_handle.transform = _rest[_handle] * Transform3D(Basis(Vector3.RIGHT, _handle_angle), Vector3.ZERO)
	if _seat != null:
		var t := _progress(seat_window)
		_seat.transform = _rest[_seat] * Transform3D(Basis(Vector3.UP, deg_to_rad(seat_turn_deg) * t), Vector3.ZERO)
		_carry_riders()
	var d := _progress(inner_door_window)
	for door in _doors:
		var rest: Transform3D = _rest[door]
		var side := signf(rest.origin.x) if absf(rest.origin.x) > 1e-4 else 1.0
		# Each half slides outward by its own width (built half the opening wide).
		door.transform = rest.translated(Vector3(side * absf(rest.origin.x) * 2.05 * d, 0, 0))


## Riders keep their place in the seat's frame (taken on the first frame, once every
## rider has placed itself). Riders and the model share a parent frame.
func _carry_riders() -> void:
	var seat_xf := _seat.get_parent_node_3d().transform * _seat.transform
	for rider in seat_riders:
		if rider == null:
			continue
		if not _rider_rest.has(rider):
			_rider_rest[rider] = seat_xf.affine_inverse() * rider.transform
		else:
			rider.transform = seat_xf * _rider_rest[rider]


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
