class_name ThrusterStatusWidget
extends HudWidget

## Engine page: one bar per thruster showing spooled throttle, with a dot showing
## where its gimbal is pointing. Lets you watch the allocator work.

@export var azimuth_deg: float = 0.0
@export var elevation_deg: float = -20.0
@export var spacing_deg: float = 2.2
@export var bar_height_deg: float = 2.6


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null or fc.thrusters.is_empty():
		return
	var n := fc.thrusters.size()
	begin_local(azimuth_deg, elevation_deg)
	var spacing := px(spacing_deg)
	var bar_h := px(bar_height_deg)
	var bar_w := px(0.5)
	var x0 := -spacing * (n - 1) * 0.5
	for i in n:
		var t := fc.thrusters[i]
		var x := x0 + spacing * i
		var color := hud.primary_color if t.enabled else hud.warning_color
		draw_rect(Rect2(x - bar_w * 0.5, -bar_h, bar_w, bar_h), hud.dim_color, false, 1.0)
		var fill := bar_h * t.throttle
		draw_rect(Rect2(x - bar_w * 0.5, -fill, bar_w, fill), color, true)
		var g := t.get_gimbal_deflection() * px(0.7)
		draw_circle(Vector2(x, -bar_h - px(1.0)) + Vector2(g.x, -g.y), 3.0, color, true, -1.0, true)
		draw_arc(Vector2(x, -bar_h - px(1.0)), px(0.7), 0.0, TAU, 16, hud.dim_color, 1.0, true)
		text(Vector2(x, 18.0), t.get_hud_label(), hud.dim_color, HORIZONTAL_ALIGNMENT_CENTER, 13)
	end_local()
