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
		return

	var sweep := minf(sweep_base + sweep_per_decade * log(speed + 1.0) / log(10.0), sweep_max)
	sweep *= 1.0 + 0.6 * _boost
	# Outward on the prograde bars; braking turns it round smoothly.
	var heading := 1.0 - 2.0 * clampf(_brake, 0.0, 1.0)
	_head = fposmod(_head + dt * sweep * heading, 1.0)
	var grow := ease(_reveal, -2.0)  # ease in-out
	_marker(patch(hud.world_to_display(_dir), Vector3.UP), grow, true)
	_marker(patch(hud.world_to_display(-_dir), Vector3.UP), grow, false)


func _update_modes(fc: FlightComputer, dt: float) -> void:
	var boost := fc.get_boost_level()
	var brake := fc.get_brake_level()
	_boost = move_toward(_boost, float(boost), dt * mode_ease_rate)
	_brake = move_toward(_brake, float(brake), dt * mode_ease_rate)
	if boost == 2 and not _was_full:
		_kick = 1.0
	_was_full = boost == 2
	_kick = move_toward(_kick, 0.0, dt / maxf(kick_time, 0.01))


## grow: 0..1, how far out the bars have appeared.
func _marker(p: Patch, grow: float, prograde: bool) -> void:
	var c := hud.primary_color if prograde else PanoramicHud.dimmed(hud.primary_color)
	var r := marker_deg
	var centre := Color(c, c.a * grow)
	if prograde:
		patch_arc(p, Vector2.ZERO, r, 0.0, TAU, centre, 2.0, 20)
	else:
		var k := r * 0.75
		patch_line(p, Vector2(-k, -k), Vector2(k, k), centre, 2.0, 2)
		patch_line(p, Vector2(-k, k), Vector2(k, -k), centre, 2.0, 2)

	_reticle(p, c, grow, prograde)

	var full := clampf(_boost - 1.0, 0.0, 1.0)
	var hard := clampf(_brake - 1.0, 0.0, 1.0)
	var stripe_c := c.lerp(Color(hud.suit_accent_color, c.a), full * 0.7)
	# Highlight position along the bar, 0 = inner end; mirrored behind.
	var head := _head if prograde else 1.0 - _head
	var width := highlight_width * (1.0 + 0.5 * minf(_boost, 1.0))
	var to := bar_to_deg + boost_stretch_deg * minf(_boost, 1.0) \
			- brake_squeeze_deg * minf(_brake, 1.0)
	var span := to - bar_from_deg
	var h := stripe_half_height_deg
	# Hard brake: the lean swings through upright to the other way, and the bars pulse.
	var lean_sign := lerpf(1.0, -1.0, hard)
	var pulse := lerpf(1.0, 0.7 + 0.3 * sin(Time.get_ticks_msec() / 1000.0 * 14.0), hard)
	for side in [-1.0, 1.0]:
		for i in stripe_count:
			var u := float(i) / (stripe_count - 1)
			var x := bar_from_deg + span * pow(u, spacing_power)
			# Grow from the inside out: each stripe fades in as the front passes it.
			var shown := clampf((grow * 1.15 - u) / 0.15, 0.0, 1.0)
			if shown <= 0.0:
				continue
			var glow := _glow(u, head, width)
			glow = maxf(glow, _glow(u, fposmod(head + 0.5, 1.0), width) * full)
			if prograde and _kick > 0.0:
				glow = maxf(glow, exp(-pow((u - (1.0 - _kick)) / 0.08, 2.0)) * _kick)
			var a := lerpf(base_alpha * (1.0 + 0.4 * minf(_boost, 1.0)), 1.0, glow) * shown * pulse
			var lean := stripe_lean_deg * (0.7 + 0.3 * u) * lean_sign
			patch_line(p, Vector2((x + lean) * side, h), Vector2((x - lean) * side, -h),
					Color(stripe_c, stripe_c.a * a), 2.0, 2)


## Highlight strength at `u` for a highlight at `head`, wrapping round the bar.
func _glow(u: float, head: float, width: float) -> float:
	var d := absf(u - head)
	d = minf(d, 1.0 - d)
	return exp(-pow(d / width, 2.0))

## Radial dashes on a wide circle around the marker, only in the left and right quarters
## (within 45° of the bars' line, leaving a narrow gap at the bars); the top and bottom
## quarters stay open. Grows out with the bars.
func _reticle(p: Patch, c: Color, grow: float, _prograde: bool) -> void:
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
			var col := Color(c, c.a * grow * fade)
			seam_safe_polyline(PackedVector2Array([_ring_point(p, a, radius - half),
					_ring_point(p, a, radius + half)]), col, 2.0)


## Canvas point `radius` rad from the patch centre, at angle `a` (from patch right, up = CCW).
## Exact on the sphere, so a wide circle stays round.
func _ring_point(p: Patch, a: float, radius: float) -> Vector2:
	var side := p.right * cos(a) + p.up * sin(a)
	return hud.projector.direction_to_canvas(p.centre * cos(radius) + side * sin(radius))
