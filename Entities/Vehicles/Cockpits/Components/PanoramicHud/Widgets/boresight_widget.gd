class_name BoresightWidget
extends HudWidget

## Reticle on the suit's body axis (where the suit and its weapons point), drawn
## in the cockpit's frame. When the FCS turns the body for thrust vectoring, the
## reticle slides off the cockpit centre and rotates with the body's roll; a
## small fixed mark stays at the cockpit centre, joined to the reticle.

@export var ring_radius_deg: float = 1.4
@export var frame_half_deg := Vector2(7.0, 5.0)
@export var reference_half_deg: float = 1.6
## Show the cockpit reference and link once the offset exceeds this, degrees.
@export var offset_display_deg: float = 1.5


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
	var offset_deg := rad_to_deg(fwd.angle_to(Vector3.FORWARD))

	if offset_deg > offset_display_deg:
		_draw_reference(pos, offset_deg)

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


## Fixed cockpit-centre mark (where the pilot faces), a dashed link to the body
## reticle and the offset angle.
func _draw_reference(body_pos: Vector2, offset_deg: float) -> void:
	var centre := hud.projector.angles_deg_to_canvas(0.0, 0.0)
	var h := px(reference_half_deg)
	var c := hud.dim_color
	line(centre + Vector2(-h, 0), centre + Vector2(-h * 0.35, 0), c)
	line(centre + Vector2(h * 0.35, 0), centre + Vector2(h, 0), c)
	line(centre + Vector2(-h * 0.35, 0), centre + Vector2(0, h * 0.3), c)
	line(centre + Vector2(h * 0.35, 0), centre + Vector2(0, h * 0.3), c)
	var link := body_pos - centre
	var dashes := maxi(2, int(link.length() / 24.0))
	for i in range(0, dashes, 2):
		line(centre + link * (float(i) / dashes), centre + link * (float(i + 1) / dashes), c)
	text(body_pos + Vector2(px(ring_radius_deg) * 2.2, -px(ring_radius_deg) * 1.2),
			"VEC %d°" % roundi(offset_deg), c, HORIZONTAL_ALIGNMENT_LEFT, 15)
