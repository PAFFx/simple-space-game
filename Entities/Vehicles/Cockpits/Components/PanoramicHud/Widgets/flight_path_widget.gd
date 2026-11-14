class_name FlightPathWidget
extends HudWidget

## Where the suit is actually going, relative to the reference frame: two wide bars of
## slanted stripes either side of the flight path, reaching out to the pitch ladder, the
## stripes closer together toward the middle. The stripes stay put; a highlight runs
## across them, outward on the way you're moving (prograde, small circle) and inward on
## the way you're coming from (retrograde, small X). Each sits inside a wide reticle of
## radial dashes on the diagonals, so it's easy to find anywhere around you.
##
## Below show_speed the markers grow out from the middle; below hide_speed they shrink
## back and hold their last direction, so they don't wander about at a near-stop.
##
## The markers are drawn into the HUD's fpm layer and turned onto the velocity by the
## screen shader, which also runs the highlight, tint, fade-in and pulse
## (hud_layers.gdshaderinc). The layer is redrawn only while the shape changes: growing in
## or out, boost / brake stretching the bars, hard brake flipping the lean.

@export var show_speed: float = 2.0   ## m/s
@export var hide_speed: float = 1.0   ## m/s
## Seconds to grow in or shrink away.
@export var reveal_time: float = 0.45
@export var marker_deg: float = 0.6
## Each bar runs from bar_from_deg to bar_to_deg either side of the marker.
@export var bar_from_deg: float = 3.0
@export var bar_to_deg: float = 27.0
@export var stripe_count: int = 16
## > 1 packs the stripes toward the middle.
@export var spacing_power: float = 1.7
## Stripe half-height and how far its top leans outward, deg.
@export var stripe_half_height_deg: float = 0.45
@export var stripe_lean_deg: float = 0.75
@export var base_alpha: float = 0.3
## Highlight sweeps per second: base + per decade of speed (m/s), up to sweep_max, so it
## runs clearly faster the faster you go (≈0.8 at 2 m/s, 1.8 at 20, 3.0 at 200).
@export var sweep_base: float = 0.2
@export var sweep_per_decade: float = 1.2
@export var sweep_max: float = 4.0
## Highlight width, fraction of the bar.
@export var highlight_width: float = 0.12
## Reticle: circle radius, dash length, dashes per diagonal and the arc they cover in each
## quarter (deg from the bars' line), deg.
@export var reticle_radius_deg: float = 17.0
@export var reticle_dash_deg: float = 1.6
@export var reticle_dashes: int = 4
@export var reticle_arc_deg := Vector2(12.0, 45.0)

## Boost / brake response (levels 0 off, 1 on, 2 full eased in at this rate, per s):
## boost speeds, widens and stretches the highlight, full boost adds a second one, tints
## the stripes with the accent and kicks a flash outward when it engages; brake turns the
## highlight inward and squeezes the bars, hard brake flips the stripes' lean and pulses.
@export var mode_ease_rate: float = 6.0
@export var boost_stretch_deg: float = 4.0
@export var brake_squeeze_deg: float = 5.0
@export var kick_time: float = 0.35

var _reveal := 0.0
var _visible := false
var _dir := Vector3.FORWARD
var _head := 0.0
var _boost := 0.0
var _brake := 0.0
var _kick := 0.0
var _was_full := false
var _last_ms := -1
# Shape the layer was drawn in: grow, bar end (deg), lean sign.
var _drawn := Vector3(0.0, 0.0, 1.0)


func setup_layers() -> void:
	_drawn.y = bar_to_deg
	hud.add_layer_drawer(&"fpm", _draw_markers, true)
	hud.set_hud_parameter(&"hud_fpm_color", hud.primary_color)
	hud.set_hud_parameter(&"hud_fpm_retro_color", PanoramicHud.dimmed(hud.primary_color))
	hud.set_hud_parameter(&"hud_fpm_accent_color", hud.suit_accent_color)
	hud.set_hud_parameter(&"hud_fpm_halo_color", hud.halo_color)
	_push_shape()


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var now := Time.get_ticks_msec()
	var dt := 0.0 if _last_ms < 0 else (now - _last_ms) / 1000.0
	_last_ms = now

	var v := fc.state.linear_velocity
	var speed := v.length()
	if speed > show_speed:
		_visible = true
	elif speed < hide_speed:
		_visible = false
	if _visible:
		_dir = v / speed
	_reveal = move_toward(_reveal, 1.0 if _visible else 0.0, dt / maxf(reveal_time, 0.01))
	_update_modes(fc, dt)
	if _reveal <= 0.0:
		hud.set_hud_parameter(&"hud_fpm_anim", Vector4.ZERO)
		return

	var sweep := minf(sweep_base + sweep_per_decade * log(speed + 1.0) / log(10.0), sweep_max)
	sweep *= 1.0 + 0.6 * _boost
	# Outward on the prograde bars; braking turns it round smoothly.
	var heading := 1.0 - 2.0 * clampf(_brake, 0.0, 1.0)
	_head = fposmod(_head + dt * sweep * heading, 1.0)

	var grow := ease(_reveal, -2.0)  # ease in-out
	var hard := clampf(_brake - 1.0, 0.0, 1.0)
	var shape := Vector3(grow, bar_to_deg + boost_stretch_deg * minf(_boost, 1.0)
			- brake_squeeze_deg * minf(_brake, 1.0), lerpf(1.0, -1.0, hard))
	if shape != _drawn:
		_drawn = shape
		hud.redraw_layer(&"fpm")
		_push_shape()

	var boost := minf(_boost, 1.0)
	# Hard brake: the bars pulse.
	var pulse := lerpf(1.0, 0.7 + 0.3 * sin(now / 1000.0 * 14.0), hard)
	hud.set_hud_parameter(&"hud_fpm_frame", _layer_frame(hud.world_to_display(_dir)))
	hud.set_hud_parameter(&"hud_fpm_stripes", Vector4(stripe_count, spacing_power,
			base_alpha * (1.0 + 0.4 * boost), highlight_width * (1.0 + 0.5 * boost)))
	hud.set_hud_parameter(&"hud_fpm_anim",
			Vector4(grow, _head, clampf(_boost - 1.0, 0.0, 1.0), _kick))
	hud.set_hud_parameter(&"hud_fpm_pulse", pulse)


func _update_modes(fc: FlightComputer, dt: float) -> void:
	var boost := fc.get_boost_level()
	var brake := fc.get_brake_level()
	_boost = move_toward(_boost, float(boost), dt * mode_ease_rate)
	_brake = move_toward(_brake, float(brake), dt * mode_ease_rate)
	if boost == 2 and not _was_full:
		_kick = 1.0
	_was_full = boost == 2
	_kick = move_toward(_kick, 0.0, dt / maxf(kick_time, 0.01))


func _push_shape() -> void:
	hud.set_hud_parameter(&"hud_fpm_bar", Vector4(bar_from_deg, _drawn.y - bar_from_deg,
			stripe_lean_deg * _drawn.z, stripe_half_height_deg))


## Display → layer: the layer's -X (where the prograde marker is drawn) onto `dir`, with
## up made the way patch() makes it, so the markers sit as if drawn around `dir`.
static func _layer_frame(dir: Vector3) -> Basis:
	var c := dir.normalized()
	var up := Vector3.UP - c * c.y
	if up.length_squared() < 1e-8:
		up = Vector3.BACK - c * c.z
	up = up.normalized()
	return Basis(-c, up, (-c).cross(up)).transposed()


## Both markers as coverage for the fpm layer (R stripes, G halo, B the rest × its fade),
## off the layer's back seam: prograde at -X, retrograde at +X.
func _draw_markers(w: HudWidget) -> void:
	var strokes: Array = []  # [canvas points, coverage colour]
	_marker_strokes(w.patch(Vector3.LEFT, Vector3.UP), true, strokes)
	_marker_strokes(w.patch(Vector3.RIGHT, Vector3.UP), false, strokes)
	if hud.halo_color.a > 0.0:
		for s: Array in strokes:
			w.draw_polyline(s[0], Color(0, 1, 0), 2.0 + hud.halo_width, true)
	for s: Array in strokes:
		w.draw_polyline(s[0], s[1], 2.0, true)


func _marker_strokes(p: Patch, prograde: bool, out: Array) -> void:
	var grow := _drawn.x
	var mark := Color(0, 0, 1)
	var r := marker_deg
	if prograde:
		var ring := PackedVector2Array()
		for k in 21:
			var a := TAU * k / 20.0
			ring.append(Vector2(cos(a), sin(a)) * r)
		out.append([_points(p, ring), mark])
	else:
		var k := r * 0.75
		out.append([_points(p, _line(Vector2(-k, -k), Vector2(k, k))), mark])
		out.append([_points(p, _line(Vector2(-k, k), Vector2(k, -k))), mark])

	_reticle(p, grow, out)

	var span := _drawn.y - bar_from_deg
	var h := stripe_half_height_deg
	for side in [-1.0, 1.0]:
		for i in stripe_count:
			var u := float(i) / (stripe_count - 1)
			# Stripes fade in from the inside out; the shader does the fade.
			if grow * 1.15 - u <= 0.0:
				continue
			var x := bar_from_deg + span * pow(u, spacing_power)
			var lean := stripe_lean_deg * (0.7 + 0.3 * u) * _drawn.z
			out.append([_points(p, _line(Vector2((x + lean) * side, h),
					Vector2((x - lean) * side, -h))), Color(1, 0, 0)])


static func _line(a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, a.lerp(b, 0.5), b])


func _points(p: Patch, deg: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for d in deg:
		pts.append(patch_point(p, d))
	return pts


## Radial dashes on a wide circle around the marker, only in the left and right quarters
## (within 45° of the bars' line, leaving a narrow gap at the bars); the top and bottom
## quarters stay open. Grows out with the bars.
func _reticle(p: Patch, grow: float, out: Array) -> void:
	var radius := deg_to_rad(reticle_radius_deg * lerpf(0.6, 1.0, grow))
	var half := deg_to_rad(reticle_dash_deg) * 0.5
	var from := deg_to_rad(reticle_arc_deg.x)
	var to := deg_to_rad(reticle_arc_deg.y)
	for q in 4:
		var base := q * PI * 0.5
		for i in reticle_dashes:
			var t := float(i) / maxf(reticle_dashes - 1, 1)
			# Quadrant 0 starts at the right bar going up; odd quadrants run the other way
			# so each arc reads from its bar toward the top / bottom.
			var a := base + (lerpf(from, to, t) if q % 2 == 0 else PI * 0.5 - lerpf(from, to, t))
			var fade := 1.0 - 0.5 * absf(t - 0.5) * 2.0
			out.append([PackedVector2Array([_ring_point(p, a, radius - half),
					_ring_point(p, a, radius + half)]), Color(0, 0, fade)])


## Canvas point `radius` rad from the patch centre, at angle `a` (from patch right, up = CCW).
## Exact on the sphere, so a wide circle stays round.
func _ring_point(p: Patch, a: float, radius: float) -> Vector2:
	var side := p.right * cos(a) + p.up * sin(a)
	return hud.projector.direction_to_canvas(p.centre * cos(radius) + side * sin(radius))
