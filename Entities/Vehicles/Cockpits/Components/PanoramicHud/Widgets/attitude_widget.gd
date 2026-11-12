class_name AttitudeWidget
extends HudWidget

## The cockpit's attitude against the HUD's attitude frame (the horizon the flight
## computer holds level to; see PanoramicHud):
##   - a horizon ring with heading marks that wraps the whole 360° screen, carrying a
##     PITCH | HEADING | ROLL box at the current heading (kept on screen at the edge
##     when the horizon is out of view)
##   - a pitch ladder ahead
##   - a fighter-style bank scale under the reticle (dashes at 10/20/30/45/60°)
##   - small attitude indicators overhead and at the feet, for when you look there

@export var ladder_step_deg: int = 10
@export var ladder_half_span_deg: float = 6.0
@export var ladder_gap_deg: float = 2.0
@export var sample_step_deg: float = 2.0
## The readout box stays within this many degrees above or below the cockpit's forward.
@export var readout_clamp_deg: float = 24.0
@export var bank_radius_deg: float = 9.0
## Overhead / feet indicators: elevations and radius, deg.
@export var aux_top_elevation_deg: float = 62.0
@export var aux_bottom_elevation_deg: float = -45.0
@export var aux_radius_deg: float = 4.5


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

	# Cockpit attitude in the reference frame: heading, pitch, bank (+ = right wing down).
	var local := ref.inverse() * forward
	var heading := wrapf(rad_to_deg(atan2(local.x, -local.z)), 0.0, 360.0)
	var pitch := rad_to_deg(asin(clampf(local.y, -1.0, 1.0)))
	var up_d := hud.world_to_display(up)
	var bank := rad_to_deg(atan2(up_d.x, up_d.y))
	_draw_readout(flat, heading, pitch, bank)
	_draw_bank_scale(bank)
	for s in [1.0, -1.0]:
		_draw_aux_horizon(s, pitch, bank)


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


## PITCH | HEADING | ROLL box riding just under the horizon at the current heading.
func _draw_readout(flat: Vector3, heading: float, pitch: float, bank: float) -> void:
	var d := hud.world_to_display(flat)
	var angles := HudProjector.direction_to_angles(d)
	var limit := deg_to_rad(readout_clamp_deg)
	angles.y = clampf(angles.y, -limit, limit)
	var at := Vector3(sin(angles.x) * cos(angles.y), sin(angles.y), -cos(angles.x) * cos(angles.y))
	var p := patch(at, Vector3.UP)
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	var w := 2.2
	var h := 0.75
	var y := -2.6  # under the horizon line, clear of the flight path and boresight
	patch_line(p, Vector2(0, 0), Vector2(0, y + h), dim, 1.5, 1)
	patch_line(p, Vector2(-w, y + h), Vector2(w, y + h), c, 0.0, 4)
	patch_line(p, Vector2(-w, y - h), Vector2(w, y - h), c, 0.0, 4)
	patch_line(p, Vector2(-w, y + h), Vector2(-w, y - h), c, 0.0, 1)
	patch_line(p, Vector2(w, y + h), Vector2(w, y - h), c, 0.0, 1)
	patch_text(p, Vector2(0, y - 0.45), "%03d" % (roundi(heading) % 360), c, HORIZONTAL_ALIGNMENT_CENTER, 24)
	patch_text(p, Vector2(-w - 0.5, y - 0.4), "%+d" % roundi(pitch), c, HORIZONTAL_ALIGNMENT_RIGHT, 20)
	patch_text(p, Vector2(w + 0.5, y - 0.4), "R%+d" % roundi(bank), c, HORIZONTAL_ALIGNMENT_LEFT, 20)
	patch_text(p, Vector2(-w - 0.5, y - 1.9), "PIT", dim, HORIZONTAL_ALIGNMENT_RIGHT, 13)
	patch_text(p, Vector2(0, y - 1.9), "HDG", dim, HORIZONTAL_ALIGNMENT_CENTER, 13)
	patch_text(p, Vector2(w + 0.5, y - 1.9), "ROLL", dim, HORIZONTAL_ALIGNMENT_LEFT, 13)


## Arc of dashes below the reticle (fixed to the cockpit) and a pointer at the bank.
func _draw_bank_scale(bank: float) -> void:
	var p := patch(Vector3.FORWARD, Vector3.UP)
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	var r := bank_radius_deg
	for deg in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(-90.0 + deg)
		var dir := Vector2(cos(a), sin(a))
		var long: bool = deg % 30 == 0
		patch_line(p, dir * r, dir * (r + (1.2 if long else 0.6)), c if long else dim, 0.0, 1)
	# Dashes between the marks, like a fighter's bank scale.
	for k in range(-58, 60, 4):
		var a := deg_to_rad(-90.0 + k)
		patch_line(p, Vector2(cos(a), sin(a)) * r, Vector2(cos(a), sin(a)) * (r + 0.25), dim, 1.5, 1)
	var b := deg_to_rad(-90.0 + clampf(bank, -70.0, 70.0))
	var dir := Vector2(cos(b), sin(b))
	var across := Vector2(-dir.y, dir.x)
	patch_polygon(p, PackedVector2Array([dir * (r - 0.15), dir * (r - 1.1) + across * 0.5,
			dir * (r - 1.1) - across * 0.5]), c)


## A small attitude indicator: the horizon line inside a ring, shifted by pitch and
## turned by bank, as on an aircraft's attitude instrument. side: +1 overhead, -1 at the feet.
func _draw_aux_horizon(side: float, pitch: float, bank: float) -> void:
	var e := deg_to_rad(aux_top_elevation_deg if side > 0.0 else aux_bottom_elevation_deg)
	var p := patch(Vector3(0, sin(e), -cos(e)), Vector3.UP)
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	var r := aux_radius_deg
	patch_arc(p, Vector2.ZERO, r, 0.0, TAU, dim, 1.5, 40)
	var a := deg_to_rad(-bank)
	var along := Vector2(cos(a), sin(a))
	var shift := Vector2(-along.y, along.x) * (-clampf(pitch, -90.0, 90.0) / 90.0 * r)
	var half := sqrt(maxf(r * r - shift.length_squared(), 0.0))
	patch_line(p, shift - along * half, shift + along * half, c, 0.0, 6)
	# Fixed suit symbol: wings and a centre dot.
	patch_line(p, Vector2(-r * 0.55, 0), Vector2(-r * 0.2, 0), dim, 2.0, 1)
	patch_line(p, Vector2(r * 0.2, 0), Vector2(r * 0.55, 0), dim, 2.0, 1)
	patch_arc(p, Vector2.ZERO, 0.25, 0.0, TAU, dim, 2.0, 8)
