class_name EnginePage
extends MfdPage

## Engines and fuel. Thrusters in three tiers by rating, biggest on top and drawn
## biggest: the mains (what you watch in a fight), the other big thrusters, then the
## small verniers (for troubleshooting). Each bar fills with its spooled throttle; the
## mains also show where their gimbal points. Fuel on the right: remaining, flow, and
## time left at the current burn, with the kick tank as a thin bar beside the main one.

## Rating (share of the largest thruster) a thruster needs for the top / middle tier.
@export var main_fraction: float = 0.5
@export var big_fraction: float = 0.2
@export var bingo_fraction: float = 0.2


func draw_page() -> void:
	var largest := 0.0
	var thrust := 0.0
	var total := 0.0
	for t in fc.thrusters:
		largest = maxf(largest, t.max_thrust)
		thrust += t.get_thrust()
		total += t.max_thrust
	var tiers: Array = [[], [], []]
	for t in fc.thrusters:
		var share := t.max_thrust / maxf(largest, 1.0)
		tiers[0 if share >= main_fraction else (1 if share >= big_fraction else 2)].append(t)

	label(Vector2(20, 34), "ENG", INFO, 22)
	var thr_frac := thrust / maxf(total, 1.0)
	label(Vector2(470, 34), "THR %3d%%   %.2f MN" % [roundi(thr_frac * 100.0), thrust / 1e6], TEXT, 18,
			HORIZONTAL_ALIGNMENT_RIGHT)
	var tw := total / maxf(fc.get_total_mass() * FlightComputer.G0, 1.0)
	label(Vector2(470, 56), "T/W MAX %.1f" % tw, DIM, 14, HORIZONTAL_ALIGNMENT_RIGHT)

	_tier(tiers[0], Rect2(20, 84, 450, 190), "MAIN", 1.0, true)
	_tier(tiers[1], Rect2(20, 300, 450, 104), "BIG", 0.5, false)
	_tier(tiers[2], Rect2(20, 428, 450, 64), "SMALL", 0.28, false)
	_fuel(Rect2(492, 84, 192, 408))


## Kick tank fill, red (empty) through amber to green (full); a tick marks the least a
## kick needs.
func _kick_tank(rect: Rect2) -> void:
	var frac := fc.get_burst_reserve_fraction()
	vbar(rect, frac, Color.from_hsv(0.33 * frac, 0.75, 1.0))
	var ready := rect.end.y - rect.size.y * fc.burst_min_reserve / fc.burst_reserve_capacity
	draw_line(Vector2(rect.position.x - 3, ready), Vector2(rect.end.x + 3, ready), TEXT, 1.5)


## One tier: bars spread across the window, sized by `scale`.
func _tier(list: Array, rect: Rect2, title: String, scale: float, gimbal: bool) -> void:
	window(rect, title)
	if list.is_empty():
		return
	var n := list.size()
	var slot := (rect.size.x - 20.0) / n
	var bar_w := minf(slot * 0.62, 70.0 * scale + 10.0)
	var top := rect.position.y + (64.0 if gimbal else 18.0)
	var bottom := rect.end.y - (30.0 if scale >= 0.5 else 18.0)
	for i in n:
		var t: Thruster = list[i]
		var cx := rect.position.x + 10.0 + slot * (i + 0.5)
		var color := GOOD if t.enabled else WARNING
		vbar(Rect2(cx - bar_w * 0.5, top, bar_w, bottom - top), t.throttle, color)
		var size_px := roundi(lerpf(11.0, 16.0, scale))
		label(Vector2(cx, rect.end.y - 8.0), t.get_hud_label(), DIM if t.enabled else WARNING,
				size_px, HORIZONTAL_ALIGNMENT_CENTER)
		if gimbal:
			var c := Vector2(cx, rect.position.y + 34.0)
			var r := 18.0
			draw_arc(c, r, 0.0, TAU, 24, FRAME, 1.5, true)
			draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(FRAME, 0.5), 1.0)
			draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(FRAME, 0.5), 1.0)
			var g := t.get_gimbal_deflection().limit_length(1.0) * r
			draw_circle(c + Vector2(g.x, -g.y), 4.5, color, true, -1.0, true)
			label(Vector2(cx, top + (bottom - top) * 0.5 + 8.0), "%d" % roundi(t.throttle * 100.0),
					TEXT, 18, HORIZONTAL_ALIGNMENT_CENTER)


func _fuel(rect: Rect2) -> void:
	window(rect, "FUEL")
	var frac := fc.get_propellant_fraction()
	var color := GOOD
	var status := ""
	if fc.propellant <= 0.0:
		color = WARNING
		status = "EMPTY"
	elif frac < bingo_fraction:
		color = CAUTION
		status = "BINGO"
	var x := rect.position.x
	var bar := Rect2(x + 28, rect.position.y + 30, 36, rect.size.y - 60)
	vbar(bar, frac, color)
	if fc.burst_reserve_capacity > 0.0:
		_kick_tank(Rect2(x + 14, bar.position.y, 8, bar.size.y))
	for k in 5:
		var y := rect.position.y + 30 + (rect.size.y - 60) * k / 4.0
		draw_line(Vector2(x + 64, y), Vector2(x + 74, y), FRAME, 1.5)
	var tx := rect.end.x - 14.0
	label(Vector2(tx, rect.position.y + 58), "%.1f t" % (fc.propellant / 1000.0), TEXT, 30, HORIZONTAL_ALIGNMENT_RIGHT)
	label(Vector2(tx, rect.position.y + 84), "%d%%" % roundi(frac * 100.0), color, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	var flow := fc.mass_flow
	label(Vector2(tx, rect.position.y + 150), "FLOW", DIM, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	label(Vector2(tx, rect.position.y + 176), "%.0f kg/s" % flow, TEXT, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	label(Vector2(tx, rect.position.y + 226), "TIME", DIM, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	var time := "--:--"
	if flow > 0.5:
		var sec := roundi(fc.propellant / flow)
		time = "%d:%02d" % [sec / 60, sec % 60] if sec < 6000 else "99:59"
	label(Vector2(tx, rect.position.y + 252), time, TEXT, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	label(Vector2(tx, rect.position.y + 302), "ISP", DIM, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	var isp_color := CAUTION if fc.get_effective_isp() < fc.specific_impulse * 0.99 else TEXT
	label(Vector2(tx, rect.position.y + 328), "%d s" % roundi(fc.get_effective_isp()), isp_color, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	if status != "":
		label(Vector2(rect.get_center().x + 20, rect.end.y - 14), status, color, 22, HORIZONTAL_ALIGNMENT_CENTER)
