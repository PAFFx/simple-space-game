class_name ThrusterStatusWidget
extends HudWidget

## Engine page: one bar per thruster showing spooled throttle, with a dot showing
## where its gimbal is pointing. Lets you watch the allocator work.
## Main engines get the top row; verniers wrap below. Bar height scales with the
## thruster's rated output, so mains read bigger than verniers.

@export var azimuth_deg: float = 0.0
@export var elevation_deg: float = -19.0
@export var spacing_deg: float = 3.6
@export var row_spacing_deg: float = 5.2
@export var bar_height_deg: float = 2.6
@export var per_row: int = 10
## Thrusters at or above this fraction of the largest one count as mains.
@export var main_fraction: float = 0.5


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null or fc.thrusters.is_empty():
		return
	var largest := 0.0
	for t in fc.thrusters:
		largest = maxf(largest, t.max_thrust)
	var mains: Array[Thruster] = []
	var verniers: Array[Thruster] = []
	for t in fc.thrusters:
		(mains if t.max_thrust >= largest * main_fraction else verniers).append(t)

	var rows: Array = [mains]
	for i in range(0, verniers.size(), per_row):
		rows.append(verniers.slice(i, i + per_row))
	begin_local(azimuth_deg, elevation_deg)
	for r in rows.size():
		_draw_row(rows[r], px(row_spacing_deg) * r, largest)
	end_local()


func _draw_row(row: Array, y: float, largest: float) -> void:
	var spacing := px(spacing_deg)
	var bar_w := px(0.55)
	var x0 := -spacing * (row.size() - 1) * 0.5
	for i in row.size():
		var t: Thruster = row[i]
		var x := x0 + spacing * i
		var bar_h := px(bar_height_deg) * sqrt(t.max_thrust / maxf(largest, 1.0))
		var color := hud.primary_color if t.enabled else hud.warning_color
		draw_rect(Rect2(x - bar_w * 0.5, y - bar_h, bar_w, bar_h), hud.dim_color, false, 1.0)
		var fill := bar_h * t.throttle
		draw_rect(Rect2(x - bar_w * 0.5, y - fill, bar_w, fill), color, true)
		var centre := Vector2(x, y - bar_h - px(0.9))
		var g := t.get_gimbal_deflection() * px(0.6)
		draw_arc(centre, px(0.6), 0.0, TAU, 16, hud.dim_color, 1.0, true)
		draw_circle(centre + Vector2(g.x, -g.y), 3.0, color, true, -1.0, true)
		text(Vector2(x, y + 17.0), t.get_hud_label(), hud.dim_color, HORIZONTAL_ALIGNMENT_CENTER, 13)
