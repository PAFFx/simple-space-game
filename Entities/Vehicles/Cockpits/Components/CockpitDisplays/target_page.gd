class_name TargetPage
extends MfdPage

## Target and stores: the locked target (range, closure, time of flight of the selected
## weapon) over the list of weapons with their rounds. When the weapon select hat is
## pressed the weapon ring (WeaponRing) comes up over the page for a moment, then goes.
## (A stores page that shows the ring all the time would not need the pop-up.)

## Seconds the weapon ring stays up after a hat press.
@export var ring_time: float = 2.5

var _fcs: FireControl
var _ring_left := 0.0
var _pressed := -1
var _last_draw := 0.0
var _last_range := 0.0
var _closure := 0.0


func _init() -> void:
	refresh_hz = 8.0


func setup(p_vehicle: VehicleBase) -> void:
	super.setup(p_vehicle)
	_fcs = vehicle.find_component(FireControl) as FireControl if vehicle != null else null
	if _fcs != null:
		_fcs.hat_pressed.connect(_on_hat_pressed)


func _on_hat_pressed(direction: int) -> void:
	_ring_left = ring_time
	_pressed = direction
	refresh_hz = 30.0


func draw_page() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dt := clampf(now - _last_draw, 0.0, 0.5)
	_last_draw = now
	label(Vector2(20, 34), "TGT", INFO, 22)
	if _fcs == null:
		label(size * 0.5, "NO FIRE CONTROL", DIM, 24, HORIZONTAL_ALIGNMENT_CENTER)
		return
	_draw_state()
	_draw_target(dt)
	_draw_stores()
	if _ring_left > 0.0:
		_ring_left -= dt
		draw_rect(Rect2(Vector2.ZERO, size), Color(BACKGROUND, 0.9), true)
		var palette := {frame = FRAME, text = TEXT, dim = DIM, accent = INFO, caution = CAUTION,
				warning = WARNING, background = BACKGROUND}
		var flash := clampf((_ring_left - (ring_time - 0.5)) / 0.5, 0.0, 1.0)
		WeaponRing.draw(self, font, size * 0.5, size.y * 0.42, _fcs, palette, _pressed, flash)
		if _ring_left <= 0.0:
			refresh_hz = 8.0


func _draw_state() -> void:
	var mode: String = ["NAV", "DGFT", "BVR"][_fcs.mode]
	label(Vector2(size.x * 0.5, 34), mode, TEXT, 20, HORIZONTAL_ALIGNMENT_CENTER)
	var armed := _fcs.master_arm
	var w := 86.0
	var r := Rect2(size.x - 20.0 - w, 14.0, w, 28.0)
	draw_rect(r, Color(WARNING if armed else DIM, 0.18 if armed else 0.0), true)
	draw_rect(r, WARNING if armed else DIM, false, 1.5)
	label(r.get_center() + Vector2(0, 7), "ARM" if armed else "SAFE", WARNING if armed else DIM, 18, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_target(dt: float) -> void:
	var r := Rect2(20, 64, size.x - 40, 190)
	window(r, "TARGET")
	var target := _fcs.locked
	if target == null or not is_instance_valid(target):
		label(r.get_center() + Vector2(0, 8), "NO TARGET", DIM, 30, HORIZONTAL_ALIGNMENT_CENTER)
		_last_range = 0.0
		return
	var dist := _fcs.get_target_position().distance_to(_fcs.get_view_origin())
	if _last_range > 0.0 and dt > 0.0:
		_closure = lerpf(_closure, (_last_range - dist) / dt, 0.3)
	_last_range = dist
	var hostile: bool = target.get_meta(&"hud_hostile", false)
	var name := String(target.get_meta(&"hud_label", target.name)).to_upper()
	label(r.position + Vector2(20, 46), name, WARNING if hostile else TEXT, 30)
	label(Vector2(r.end.x - 20, r.position.y + 46), "HOSTILE" if hostile else "UNKNOWN", WARNING if hostile else DIM, 16,
			HORIZONTAL_ALIGNMENT_RIGHT)
	var weapon := _fcs.selected
	var tof := "---"
	var cue := ""
	var cue_color := DIM
	if weapon != null and weapon.solution_valid:
		tof = "%.2f s" % weapon.time_of_flight
		if not weapon.target_in_envelope:
			cue = "OUT OF ENVELOPE"
			cue_color = CAUTION
		elif weapon.on_target and weapon.state == MsWeapon.State.READY:
			cue = "SHOOT"
			cue_color = GOOD
		else:
			cue = "TRACKING"
	elif weapon != null:
		cue = "NO SOLUTION"
		cue_color = CAUTION
	var values := [SaPage._fmt_range(dist), "%+.0f m/s" % _closure, tof]
	for i in 3:
		var x := r.position.x + 20.0 + i * (r.size.x - 40.0) / 3.0
		label(Vector2(x, r.position.y + 96), ["RNG", "Vc", "TOF"][i], DIM, 14)
		label(Vector2(x, r.position.y + 126), values[i], TEXT, 22)
	label(Vector2(r.position.x + 20, r.end.y - 18), cue, cue_color, 18)


func _draw_stores() -> void:
	var r := Rect2(20, 280, size.x - 40, size.y - 310)
	window(r, "STORES")
	var y := r.position.y + 38.0
	for weapon: MsWeapon in _fcs.weapons.values():
		if not weapon.is_gun():
			continue
		var is_selected := weapon == _fcs.selected or weapon.always_on
		var color := TEXT if is_selected else DIM
		if weapon == _fcs.selected:
			draw_rect(Rect2(r.position.x + 8, y - 22, r.size.x - 16, 32), Color(INFO, 0.14), true)
			color = INFO
		label(Vector2(r.position.x + 20, y), weapon.display_name, color, 18)
		var fraction := float(weapon.ammo) / maxf(weapon.max_ammo, 1.0)
		hbar(Rect2(r.end.x - 250, y - 14, 130, 14), fraction, WARNING if weapon.ammo == 0 else color)
		label(Vector2(r.end.x - 60, y), "%d" % weapon.ammo, WARNING if weapon.ammo == 0 else color, 18, HORIZONTAL_ALIGNMENT_RIGHT)
		var state := "RDY" if weapon.state == MsWeapon.State.READY else ""
		label(Vector2(r.end.x - 20, y), state, GOOD, 14, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 40.0
