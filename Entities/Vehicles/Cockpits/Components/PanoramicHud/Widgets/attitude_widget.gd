class_name AttitudeWidget
extends HudWidget

## The cockpit's attitude against the HUD's attitude frame (the horizon the flight
## computer holds level to; see PanoramicHud):
##   - a pitch ladder: two tick columns far either side of the heading, along meridians of
##     the attitude frame (so they lean together toward the zenith): ticks every 1/5/10°
##     and a pointer riding at the cockpit's pitch, labelled with it; marks
##     fade away from it. Climbing or descending, a highlight runs up or down the ticks,
##     faster the faster the climb (as on the flight path bars)
##   - a small attitude indicator straight overhead (cockpit +90°), marking the zenith
##   - a course ring around it at course_elevation_deg: heading marks and numbers
##     turning with the heading, read against a fixed mark at the cockpit's forward,
##     carrying a HDG box
##   - optionally the 360° horizon ring with heading marks (off: reserved for other use)

## Pitch ladder: column bearing either side of the heading; ticks every 1°, longer every
## ladder_step_deg, longest every ladder_label_step_deg.
@export var ladder_column_az_deg: float = 30.0
@export var ladder_step_deg: int = 5
@export var ladder_label_step_deg: int = 10
## Tick lengths, deg: 1°, step, numbered, horizon.
@export var ladder_tick_deg := Vector4(0.35, 0.8, 1.4, 2.4)
@export var ladder_max_deg: int = 85
## Marks this far (deg) from the cockpit's pitch stay full strength, then fade over
## ladder_fade_deg down to ladder_fade_floor.
@export var ladder_focus_deg: float = 25.0
@export var ladder_fade_deg: float = 30.0
@export var ladder_fade_floor: float = 0.3
## Climb highlight: shown above climb_show_speed (m/s along the attitude frame's up), gone
## below climb_hide_speed; runs through the band within climb_span_deg of the cockpit's
## pitch at the flight path's rate (sweeps/s, base + per decade of climb speed).
@export var climb_show_speed: float = 2.0
@export var climb_hide_speed: float = 1.0
@export var climb_reveal_time: float = 0.45
@export var climb_span_deg: float = 35.0
@export var climb_width_deg: float = 5.0
@export var climb_sweep_base: float = 0.2
@export var climb_sweep_per_decade: float = 1.2
@export var climb_sweep_max: float = 4.0
@export var sample_step_deg: float = 2.0
@export var show_horizon_ring := false
## Overhead attitude indicator radius, deg.
@export var aux_radius_deg: float = 4.5
## Course ring elevation in the cockpit frame: inside the default view (75° vertical FOV)
## with room for the HDG box above it, clear of the data blocks below.
@export var course_elevation_deg: float = 28.0
## Opacity of the ring, its marks and numbers (the HDG box and pointer stay full).
@export var course_alpha: float = 0.55
@export var course_label_offset_deg: float = 1.6

var _climb_on := false
var _climb_sign := 1.0
var _climb_reveal := 0.0
var _climb_phase := 0.0
var _last_ms := -1


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

	if show_horizon_ring:
		_draw_horizon_ring(ref)

	# Cockpit attitude in the reference frame: heading, pitch, bank (+ = right wing down).
	var local := ref.inverse() * forward
	var heading := wrapf(rad_to_deg(atan2(local.x, -local.z)), 0.0, 360.0)
	var pitch := rad_to_deg(asin(clampf(local.y, -1.0, 1.0)))
	_update_climb(up)
	for side in [-1.0, 1.0]:
		_draw_ladder_column(flat, right, up, side, pitch)
	var up_d := hud.world_to_display(up)
	var bank := rad_to_deg(atan2(up_d.x, up_d.y))
	_draw_readout(heading)
	# Up is behind you when you look straight up.
	_draw_aux_horizon(patch(Vector3.UP, Vector3.BACK, true), pitch, bank)
	_draw_course_ring(heading)


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


## One column of the ladder. side: -1 left, +1 right. Ticks reach outward from the column
## line, the pitch pointer and its value sit inward. Below the horizon the step and numbered ticks
## are split in two, as on aircraft ladders.
func _draw_ladder_column(flat: Vector3, right: Vector3, up: Vector3, side: float,
		pitch: float) -> void:
	var c := hud.ladder_color
	var a := deg_to_rad(ladder_column_az_deg) * side
	var bearing := flat * cos(a) + right * sin(a)
	var outward := (-flat * sin(a) + right * cos(a)) * side

	for pitch_deg in range(-ladder_max_deg, ladder_max_deg + 1):
		var base := _ladder_point(bearing, up, pitch_deg)
		var fade := _ladder_fade(pitch_deg, pitch)
		var glow := _climb_glow(pitch_deg, pitch)
		var labelled := pitch_deg % ladder_label_step_deg == 0
		var stepped := pitch_deg % ladder_step_deg == 0
		if pitch_deg == 0:
			_ladder_tick(base, outward, 0.0, ladder_tick_deg.w, _lit(c, fade, glow), 2.0)
		elif labelled or stepped:
			var length := ladder_tick_deg.z if labelled else ladder_tick_deg.y
			var color := _lit(c, fade * (1.0 if labelled else 0.75), glow)
			var w := 2.0 if labelled else 1.5
			if pitch_deg < 0:
				_ladder_tick(base, outward, 0.0, length * 0.4, color, w)
				_ladder_tick(base, outward, length * 0.6, length, color, w)
			else:
				_ladder_tick(base, outward, 0.0, length, color, w)
		else:
			_ladder_tick(base, outward, 0.0, ladder_tick_deg.x, _lit(c, fade * 0.6, glow), 1.2, false)

	# Pointer at the cockpit's pitch, aimed at the ticks from inside.
	var at := _ladder_point(bearing, up, pitch)
	var p := patch(hud.world_to_display(at), hud.world_to_display(up))
	var s := side
	var dim := PanoramicHud.dimmed(hud.primary_color)
	patch_polygon(p, PackedVector2Array([Vector2(-0.2 * s, 0), Vector2(-0.95 * s, 0.4),
			Vector2(-0.95 * s, -0.4)]), dim)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if side > 0 else HORIZONTAL_ALIGNMENT_LEFT
	patch_text(p, Vector2(-1.25 * s, 0.45), "%+d" % roundi(pitch), dim, align, 16)


## Climb rate along the attitude frame's up: shows / hides the highlight (holding its
## direction while it fades) and runs it at a rate that rises with the climb speed.
func _update_climb(up: Vector3) -> void:
	var now := Time.get_ticks_msec()
	var dt := 0.0 if _last_ms < 0 else (now - _last_ms) / 1000.0
	_last_ms = now
	var fc := hud.flight_computer
	var climb := fc.state.linear_velocity.dot(up) if fc != null else 0.0
	var speed := absf(climb)
	if speed > climb_show_speed:
		_climb_on = true
	elif speed < climb_hide_speed:
		_climb_on = false
	if _climb_on:
		_climb_sign = signf(climb)
	_climb_reveal = move_toward(_climb_reveal, 1.0 if _climb_on else 0.0,
			dt / maxf(climb_reveal_time, 0.01))
	var sweep := minf(climb_sweep_base + climb_sweep_per_decade * log(speed + 1.0) / log(10.0),
			climb_sweep_max)
	_climb_phase = fposmod(_climb_phase + dt * sweep, 1.0)


## 0..1 highlight on the tick at pitch_deg: a soft spot running through the band around
## the cockpit's pitch, upward while climbing, downward while descending, wrapping round.
func _climb_glow(pitch_deg: float, pitch: float) -> float:
	if _climb_reveal <= 0.0:
		return 0.0
	var off := pitch_deg - pitch
	if absf(off) > climb_span_deg:
		return 0.0
	var band := climb_span_deg * 2.0
	var head := (_climb_phase * band - climb_span_deg) * _climb_sign
	var d := absf(off - head)
	d = minf(d, band - d)
	return exp(-pow(d / climb_width_deg, 2.0)) * ease(_climb_reveal, -2.0)


## Ladder colour at `strength`, brightened toward the HUD's primary colour by `glow`.
func _lit(c: Color, strength: float, glow: float) -> Color:
	var lit := c.lerp(hud.primary_color, glow)
	lit.a = lerpf(c.a * strength, hud.primary_color.a, glow)
	return lit


## Column point at a pitch (deg) along the column's meridian.
func _ladder_point(bearing: Vector3, up: Vector3, pitch_deg: float) -> Vector3:
	var e := deg_to_rad(pitch_deg)
	return bearing * cos(e) + up * sin(e)


## Strength of a mark by its distance from the cockpit's pitch.
func _ladder_fade(pitch_deg: float, pitch: float) -> float:
	var off := absf(pitch_deg - pitch) - ladder_focus_deg
	return lerpf(1.0, ladder_fade_floor, clampf(off / ladder_fade_deg, 0.0, 1.0))


## Tick from `from` to `to` deg outward of `base`, along a great circle so it keeps its
## length toward the zenith.
func _ladder_tick(base: Vector3, outward: Vector3, from: float, to: float, color: Color,
		width: float, halo := true) -> void:
	var pts := PackedVector2Array()
	var steps := 3
	for k in steps + 1:
		var t := deg_to_rad(lerpf(from, to, float(k) / steps))
		pts.append(hud.world_dir_to_canvas(base * cos(t) + outward * sin(t)))
	seam_safe_polyline(pts, color, width, halo)


## HDG box on the course ring's pointer, inside the ring.
func _draw_readout(heading: float) -> void:
	var p := patch(_ring_dir(0.0, deg_to_rad(course_elevation_deg)), Vector3.UP)
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	var w := 2.2
	var h := 1.0
	var y := 1.4 + h  # above the pointer (0.15..1.0)
	patch_line(p, Vector2(0, 1.0), Vector2(0, y - h), dim, 1.5, 1)
	patch_line(p, Vector2(-w, y + h), Vector2(w, y + h), c, 0.0, 4)
	patch_line(p, Vector2(-w, y - h), Vector2(w, y - h), c, 0.0, 4)
	patch_line(p, Vector2(-w, y + h), Vector2(-w, y - h), c, 0.0, 1)
	patch_line(p, Vector2(w, y + h), Vector2(w, y - h), c, 0.0, 1)
	patch_text(p, Vector2(0, y - 0.7), "%03d" % (roundi(heading) % 360), c, HORIZONTAL_ALIGNMENT_CENTER, 24)
	patch_text(p, Vector2(0, y + h + 0.45), "HDG", dim, HORIZONTAL_ALIGNMENT_CENTER, 13)


## Ring of heading marks on a circle of constant elevation, turning with the heading
## (azimuth = bearing from the current heading), numbered every 30°, against a fixed
## pointer at the cockpit's forward. Marks hang below the ring, away from the zenith.
func _draw_course_ring(heading: float) -> void:
	var full := hud.primary_color
	var c := Color(full, full.a * course_alpha)
	var dim := PanoramicHud.dimmed(c)
	var el := deg_to_rad(course_elevation_deg)
	var ring := PackedVector2Array()
	var az := -180.0
	while az <= 180.0:
		ring.append(hud.projector.angles_to_canvas(deg_to_rad(az), el))
		az += sample_step_deg * 0.5
	seam_safe_polyline(ring, dim, 1.5, false)
	for deg in range(0, 360, 10):
		var p := patch(_ring_dir(deg_to_rad(deg - heading), el), Vector3.UP)
		var major := deg % 30 == 0
		var tick := 0.9 if major else 0.45
		patch_line(p, Vector2.ZERO, Vector2(0, -tick), c if major else dim, 0.0, 1)
		if major:
			patch_text(p, Vector2(0, -tick - course_label_offset_deg), "%03d" % deg, c,
					HORIZONTAL_ALIGNMENT_CENTER, 18)
	var mark := patch(_ring_dir(0.0, el), Vector3.UP)
	patch_polygon(mark, PackedVector2Array([Vector2(0, 0.15), Vector2(-0.5, 1.0),
			Vector2(0.5, 1.0)]), full)


## Display-frame direction at azimuth (rad, + = right) and elevation (rad).
func _ring_dir(azimuth: float, elevation: float) -> Vector3:
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))


## A small attitude indicator: the horizon line inside a ring, shifted by pitch and
## turned by bank, as on an aircraft's attitude instrument.
func _draw_aux_horizon(p: Patch, pitch: float, bank: float) -> void:
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
