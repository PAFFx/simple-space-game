class_name BoresightWidget
extends HudWidget

## Fixed reticle on the suit's forward axis (where the body — and its weapons — point).

@export var ring_radius_deg: float = 1.4
@export var frame_half_deg := Vector2(7.0, 5.0)


func draw_widget() -> void:
	begin_local(0.0, 0.0)
	var r := px(ring_radius_deg)
	var c := hud.primary_color
	# Ring broken into four arcs with ticks in the gaps.
	for i in 4:
		var start := i * PI * 0.5 + 0.25
		draw_arc(Vector2.ZERO, r, start, start + PI * 0.5 - 0.5, 12, c, hud.line_width, true)
		var dir := Vector2.from_angle(i * PI * 0.5)
		line(dir * r * 0.75, dir * r * 1.35, c)
	draw_circle(Vector2.ZERO, 2.5, c, true, -1.0, true)
	brackets(Vector2(px(frame_half_deg.x), px(frame_half_deg.y)), px(1.2), hud.dim_color)
