class_name AttitudeWidget
extends HudWidget

## Reference-plane attitude: a horizon ring with heading marks that wraps the
## whole 360° screen, plus a pitch ladder ahead of the suit, against the HUD's attitude
## frame (the horizon the flight computer holds level to; see PanoramicHud).

@export var ladder_step_deg: int = 10
@export var ladder_half_span_deg: float = 6.0
@export var ladder_gap_deg: float = 2.0
@export var sample_step_deg: float = 2.0


func draw_widget() -> void:
	var ref := hud.get_attitude_basis()
	var up := ref.y
	var display := hud.get_display_basis()
	var forward := -display.z
	var flat := forward - up * forward.dot(up)
	if flat.length_squared() < 1e-6:
		flat = -display.y  # looking straight up/down: use cockpit down as heading
	flat = flat.normalized()
	var right := flat.cross(up).normalized()

	_draw_horizon_ring(ref)
	for e in range(-90 + ladder_step_deg, 90, ladder_step_deg):
		if e != 0:
			_draw_ladder_rung(flat, right, up, e)


func _draw_horizon_ring(ref: Basis) -> void:
	var north := -ref.z
	var east := ref.x
	var points := PackedVector2Array()
	var heading := 0.0
	while heading <= 360.0:
		var h := deg_to_rad(heading)
		points.append(hud.world_dir_to_canvas(north * cos(h) + east * sin(h)))
		heading += sample_step_deg
	seam_safe_polyline(points, hud.dim_color)

	for deg in range(0, 360, 10):
		var h := deg_to_rad(float(deg))
		var dir := north * cos(h) + east * sin(h)
		var base := hud.world_dir_to_canvas(dir)
		var tick := px(0.9 if deg % 30 == 0 else 0.45)
		line(base, base - Vector2(0, tick), hud.dim_color)
		if deg % 30 == 0:
			text_at(base - Vector2(0, tick + 6.0), "%03d" % deg, hud.dim_color, HORIZONTAL_ALIGNMENT_CENTER, 16)


func _draw_ladder_rung(flat: Vector3, right: Vector3, up: Vector3, pitch_deg: int) -> void:
	var e := deg_to_rad(float(pitch_deg))
	var color := hud.primary_color if absi(pitch_deg) <= 30 else hud.dim_color
	# Rungs run along a great circle through the rung's centre, so they keep their
	# angular length up to the zenith instead of shrinking with the latitude circle.
	var centre := flat * cos(e) + up * sin(e)
	for side in [-1.0, 1.0]:
		var points := PackedVector2Array()
		var a := ladder_gap_deg
		while a <= ladder_half_span_deg + 0.001:
			var s := deg_to_rad(a * side)
			points.append(hud.world_dir_to_canvas(centre * cos(s) + right * sin(s)))
			a += 1.0
		if pitch_deg < 0:
			# Dashed below the reference plane, as on aircraft ladders.
			for i in range(1, points.size(), 2):
				line(points[i - 1], points[i], color)
		else:
			seam_safe_polyline(points, color)
		var tip := points[points.size() - 1]
		var drop := px(0.6) * (1.0 if pitch_deg > 0 else -1.0)
		line(tip, tip + Vector2(0, drop), color)
		var label_pos := tip + Vector2(px(0.5) * side, 6.0)
		var align := HORIZONTAL_ALIGNMENT_LEFT if side > 0 else HORIZONTAL_ALIGNMENT_RIGHT
		text_at(label_pos, str(absi(pitch_deg)), color, align, 15)
