class_name BoresightWidget
extends HudWidget

## Reticle on the suit's body axis (where the suit and its weapons point), drawn
## in the cockpit's frame, so it slides off the centre when auto-rotation turns
## the body. Rolls with the body; the long top tick is the suit's up.
## The suit's lean and roll themselves are read on SuitAttitudeWidget.

@export var ring_radius_deg: float = 1.4
@export var frame_half_deg := Vector2(7.0, 5.0)


func draw_widget() -> void:
	var body := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized() \
			if hud.vehicle != null \
			else hud.get_display_basis()
	var fwd := hud.world_to_display(-body.z)
	var angles := HudProjector.direction_to_angles(fwd)
	var pos := hud.projector.angles_to_canvas(angles.x, angles.y)
	var up_dir := (fwd + hud.world_to_display(body.y) * 0.02).normalized()
	var up_pos := hud.projector.direction_to_canvas(up_dir)
	var roll := (up_pos - pos).angle() + PI * 0.5

	draw_set_transform(pos, roll, Vector2(HudProjector.stretch_at(angles.y), 1.0))
	var r := px(ring_radius_deg)
	var c := hud.primary_color
	# Ring broken into four arcs with ticks in the gaps; the top tick is longer (body up).
	for i in 4:
		var start := i * PI * 0.5 + 0.25
		draw_arc(Vector2.ZERO, r, start, start + PI * 0.5 - 0.5, 12, c, hud.line_width, true)
		var dir := Vector2.from_angle(i * PI * 0.5)
		line(dir * r * 0.75, dir * r * (1.9 if i == 3 else 1.35), c)
	draw_circle(Vector2.ZERO, 2.5, c, true, -1.0, true)
	brackets(Vector2(px(frame_half_deg.x), px(frame_half_deg.y)), px(1.2), hud.dim_color)
