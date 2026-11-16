class_name AttitudeWidget
extends HudWidget

## The cockpit's attitude against the HUD's attitude frame (the horizon the flight
## computer holds level to; see PanoramicHud):
##   - a pitch ladder: two tick columns either side of the nose, upright in the cockpit,
##     each on a small circle around the cockpit's right axis (so they never meet
##     overhead), scrolling with the cockpit's pitch: ticks every 1/5/10°
##     and a pointer riding at the cockpit's pitch, labelled with it; marks
##     fade away from it. Climbing or descending, a highlight runs up or down the ticks,
##     faster the faster the climb (as on the flight path bars)
##   - a small attitude indicator straight overhead (cockpit +90°), marking the zenith
##   - a course ring around it at course_elevation_deg: heading marks and numbers
##     turning with the heading, read against a fixed mark at the cockpit's forward,
##     carrying a HDG box
##   - optionally the 360° horizon ring with heading marks (off: reserved for other use)
##
## The ladder and the course marks only turn with pitch / heading, so they are drawn once
## into HUD layers and turned by the screen shader; the ladder's fade and climb highlight
## follow the pitch there too (hud_layers.gdshaderinc). Fixed outlines go into the static
## layer. Per frame only the numbers, the overhead horizon line and the uniforms change.

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
## Course ring elevation in the cockpit frame: above the default view (75° vertical FOV),
## read with a glance up, so it stays clear of the forward view and the data blocks.
@export var course_elevation_deg: float = 45.0
## Opacity of the ring, its marks and numbers (the HDG box and pointer stay full).
@export var course_alpha: float = 0.55
@export var course_label_offset_deg: float = 1.6

# HDG box layout, patch degrees.
const _BOX_HALF := Vector2(2.2, 1.0)
const _BOX_Y := 1.4 + 1.0  # above the pointer (0.15..1.0)
# Heading the course marks are drawn for: it keeps every mark and number off the
# layer's back seam (marks every 10°, numbers every 30°), where text would be cut.
const _MARKS_HEADING := 15.0

var _climb_on := false
var _climb_sign := 1.0
var _climb_reveal := 0.0
var _climb_phase := 0.0
var _last_ms := -1


func setup_layers() -> void:
	hud.add_layer_drawer(&"static", _draw_fixed)
	hud.add_layer_drawer(&"heading", _draw_course_marks)
	hud.add_layer_drawer(&"ladder", _draw_ladder, true)
	hud.set_hud_parameter(&"hud_ladder_color", hud.ladder_color)
	hud.set_hud_parameter(&"hud_ladder_lit_color", hud.primary_color)
	hud.set_hud_parameter(&"hud_ladder_halo_color", hud.halo_color)
	hud.set_hud_parameter(&"hud_ladder_fade",
			Vector3(ladder_focus_deg, ladder_fade_deg, ladder_fade_floor))


func draw_widget() -> void:
	var ref := hud.get_attitude_basis()
	var up := ref.y
	var display := hud.get_display_basis()
	var forward := -display.z

	if show_horizon_ring:
		_draw_horizon_ring(ref)

	# Cockpit attitude in the reference frame: heading, pitch, bank (+ = right wing down).
	var local := ref.inverse() * forward
	var heading := wrapf(rad_to_deg(atan2(local.x, -local.z)), 0.0, 360.0)
	var pitch := rad_to_deg(asin(clampf(local.y, -1.0, 1.0)))
	_update_climb(up)
	_push_layer_state(heading, pitch)

	var dim := PanoramicHud.dimmed(hud.primary_color)
	for side in [-1.0, 1.0]:
		var align := HORIZONTAL_ALIGNMENT_RIGHT if side > 0 else HORIZONTAL_ALIGNMENT_LEFT
		patch_text(_pointer_patch(self, side), Vector2(-1.25 * side, 0.45), "%+d" % roundi(pitch),
				dim, align, 16)
	patch_text(_readout_patch(self), Vector2(0, _BOX_Y - 0.7), "%03d" % (roundi(heading) % 360),
			hud.primary_color, HORIZONTAL_ALIGNMENT_CENTER, 24)

	var up_d := hud.world_to_display(up)
	var bank := rad_to_deg(atan2(up_d.x, up_d.y))
	_draw_aux_horizon_line(pitch, bank)


## Turns the ladder and course layers into place and hands the shader the ladder state.
## The ladder is drawn level (pitch 0): at pitch p it is that picture pitched down by p
## about the cockpit's right axis. The course marks are drawn for _MARKS_HEADING.
func _push_layer_state(heading: float, pitch: float) -> void:
	hud.set_hud_parameter(&"hud_ladder_frame", Basis(Vector3.RIGHT, deg_to_rad(pitch)))
	hud.set_hud_parameter(&"hud_heading_frame",
			Basis(Vector3.UP, deg_to_rad(heading - _MARKS_HEADING)).inverse())
	hud.set_hud_parameter(&"hud_pitch_deg", pitch)
	var reveal := ease(_climb_reveal, -2.0) if _climb_reveal > 0.0 else 0.0
	var head := (_climb_phase * climb_span_deg * 2.0 - climb_span_deg) * _climb_sign
	hud.set_hud_parameter(&"hud_climb", Vector4(reveal, head, climb_span_deg, climb_width_deg))


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


# --- Fixed parts (static layer, display frame) ---

func _draw_fixed(w: HudWidget) -> void:
	var dim := PanoramicHud.dimmed(hud.primary_color)
	for side in [-1.0, 1.0]:
		var s: float = side
		w.patch_polygon(_pointer_patch(w, side), PackedVector2Array([Vector2(-0.2 * s, 0),
				Vector2(-0.95 * s, 0.4), Vector2(-0.95 * s, -0.4)]), dim)
	_draw_readout_frame(w)
	_draw_aux_frame(w)
	_draw_course_ring_line(w)


## The pitch pointer sits level with the nose on each ladder column, so it stays put in
## the display frame while the ladder scrolls past it.
func _pointer_patch(w: HudWidget, side: float) -> Patch:
	var a := deg_to_rad(ladder_column_az_deg)
	return w.patch(Vector3(side * sin(a), 0.0, -cos(a)), Vector3.UP)


func _readout_patch(w: HudWidget) -> Patch:
	return w.patch(_ring_dir(0.0, deg_to_rad(course_elevation_deg)), Vector3.UP)


## HDG box on the course ring's pointer, inside the ring (its number is drawn per frame).
func _draw_readout_frame(w: HudWidget) -> void:
	var p := _readout_patch(w)
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	var bw := _BOX_HALF.x
	var h := _BOX_HALF.y
	var y := _BOX_Y
	w.patch_line(p, Vector2(0, 1.0), Vector2(0, y - h), dim, 1.5, 1)
	w.patch_line(p, Vector2(-bw, y + h), Vector2(bw, y + h), c, 0.0, 4)
	w.patch_line(p, Vector2(-bw, y - h), Vector2(bw, y - h), c, 0.0, 4)
	w.patch_line(p, Vector2(-bw, y + h), Vector2(-bw, y - h), c, 0.0, 1)
	w.patch_line(p, Vector2(bw, y + h), Vector2(bw, y - h), c, 0.0, 1)
	w.patch_text(p, Vector2(0, y + h + 0.45), "HDG", dim, HORIZONTAL_ALIGNMENT_CENTER, 13)


## The course ring itself and the fixed pointer at the cockpit's forward.
func _draw_course_ring_line(w: HudWidget) -> void:
	var full := hud.primary_color
	var c := Color(full, full.a * course_alpha)
	var dim := PanoramicHud.dimmed(c)
	var el := deg_to_rad(course_elevation_deg)
	var ring := PackedVector2Array()
	var az := -180.0
	while az <= 180.0:
		ring.append(hud.projector.angles_to_canvas(deg_to_rad(az), el))
		az += sample_step_deg * 0.5
	w.seam_safe_polyline(ring, dim, 1.5, false)
	var mark := w.patch(_ring_dir(0.0, el), Vector3.UP)
	w.patch_polygon(mark, PackedVector2Array([Vector2(0, 0.15), Vector2(-0.5, 1.0),
			Vector2(0.5, 1.0)]), full)


## Overhead attitude indicator's ring and fixed suit symbol (wings and a centre dot).
## Up is behind you when you look straight up.
func _draw_aux_frame(w: HudWidget) -> void:
	var p := w.patch(Vector3.UP, Vector3.BACK, true)
	var dim := PanoramicHud.dimmed(hud.primary_color)
	var r := aux_radius_deg
	w.patch_arc(p, Vector2.ZERO, r, 0.0, TAU, dim, 1.5, 40)
	w.patch_line(p, Vector2(-r * 0.55, 0), Vector2(-r * 0.2, 0), dim, 2.0, 1)
	w.patch_line(p, Vector2(r * 0.2, 0), Vector2(r * 0.55, 0), dim, 2.0, 1)
	w.patch_arc(p, Vector2.ZERO, 0.25, 0.0, TAU, dim, 2.0, 8)


## The indicator's horizon line, shifted by pitch and turned by bank.
func _draw_aux_horizon_line(pitch: float, bank: float) -> void:
	var p := patch(Vector3.UP, Vector3.BACK, true)
	var r := aux_radius_deg
	var a := deg_to_rad(-bank)
	var along := Vector2(cos(a), sin(a))
	var shift := Vector2(-along.y, along.x) * (-clampf(pitch, -90.0, 90.0) / 90.0 * r)
	var half := sqrt(maxf(r * r - shift.length_squared(), 0.0))
	patch_line(p, shift - along * half, shift + along * half, hud.primary_color, 0.0, 6)


# --- Course marks (heading layer, drawn for _MARKS_HEADING) ---

## Heading marks on the course ring (azimuth = bearing from the heading), numbered every
## 30°. Marks hang below the ring, away from the zenith.
func _draw_course_marks(w: HudWidget) -> void:
	var full := hud.primary_color
	var c := Color(full, full.a * course_alpha)
	var dim := PanoramicHud.dimmed(c)
	var el := deg_to_rad(course_elevation_deg)
	for deg in range(0, 360, 10):
		var p := w.patch(_ring_dir(deg_to_rad(deg - _MARKS_HEADING), el), Vector3.UP)
		var major := deg % 30 == 0
		var tick := 0.9 if major else 0.45
		w.patch_line(p, Vector2.ZERO, Vector2(0, -tick), c if major else dim, 0.0, 1)
		if major:
			w.patch_text(p, Vector2(0, -tick - course_label_offset_deg), "%03d" % deg, c,
					HORIZONTAL_ALIGNMENT_CENTER, 18)


## Display-frame direction at azimuth (rad, + = right) and elevation (rad).
func _ring_dir(azimuth: float, elevation: float) -> Vector3:
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))


# --- Pitch ladder (ladder layer, drawn level) ---

## Both columns as coverage for the shader (hud_layers.gdshaderinc): halos into G, then
## strokes into R with the tick's strength in B. Drawn additively, so the channels
## don't erase each other.
func _draw_ladder(w: HudWidget) -> void:
	var ticks: Array = []
	for side in [-1.0, 1.0]:
		_ladder_column_ticks(ticks, side)
	for t: Array in ticks:
		if t[3] and hud.halo_color.a > 0.0:
			w.draw_polyline(t[0], Color(0, 1, 0), t[1] + hud.halo_width, true)
	for t: Array in ticks:
		w.draw_polyline(t[0], Color(1, 0, t[2]), t[1], true)


## One column's ticks as [points, width, strength, halo]. side: -1 left, +1 right. Ticks
## reach outward from the column line. Below the horizon the step and numbered ticks are
## split in two, as on aircraft ladders. Strength: numbered 1, step 0.75, 1° ticks 0.6.
func _ladder_column_ticks(ticks: Array, side: float) -> void:
	var a := deg_to_rad(ladder_column_az_deg)
	var right := Vector3.RIGHT
	var offset := right * side * sin(a)
	var radius := cos(a)
	for pitch_deg in range(-ladder_max_deg, ladder_max_deg + 1):
		var base := _ladder_point(offset, radius, pitch_deg)
		var outward := (right * side - base * base.dot(right * side)).normalized()
		var labelled := pitch_deg % ladder_label_step_deg == 0
		var stepped := pitch_deg % ladder_step_deg == 0
		if pitch_deg == 0:
			ticks.append([_tick_points(base, outward, 0.0, ladder_tick_deg.w), 2.0, 1.0, true])
		elif labelled or stepped:
			var length := ladder_tick_deg.z if labelled else ladder_tick_deg.y
			var strength := 1.0 if labelled else 0.75
			var width := 2.0 if labelled else 1.5
			if pitch_deg < 0:
				ticks.append([_tick_points(base, outward, 0.0, length * 0.4), width, strength, true])
				ticks.append([_tick_points(base, outward, length * 0.6, length), width, strength, true])
			else:
				ticks.append([_tick_points(base, outward, 0.0, length), width, strength, true])
		else:
			ticks.append([_tick_points(base, outward, 0.0, ladder_tick_deg.x), 1.2, 0.6, false])


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


## Column point at a pitch (deg) of the level ladder: forward pitched up by it, moved
## sideways onto the column's small circle.
func _ladder_point(offset: Vector3, radius: float, pitch_deg: float) -> Vector3:
	var e := deg_to_rad(pitch_deg)
	return offset + (Vector3.FORWARD * cos(e) + Vector3.UP * sin(e)) * radius


## Tick from `from` to `to` deg outward of `base`, along a great circle so it keeps its
## length toward the zenith.
func _tick_points(base: Vector3, outward: Vector3, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 3
	for k in steps + 1:
		var t := deg_to_rad(lerpf(from, to, float(k) / steps))
		pts.append(hud.projector.direction_to_canvas(base * cos(t) + outward * sin(t)))
	return pts
