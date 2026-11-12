class_name FlightPathWidget
extends HudWidget

## Where the suit is actually going, relative to the reference frame: two split bars of
## slanted dashes either side of the flight path, with a circle on the way you're
## moving (prograde) and an X on the way you're coming from (retrograde). The dashes
## stream in toward the circle and out from the X, faster the faster you move, so even
## a glance tells "going toward" from "coming from".

@export var min_speed: float = 0.3   ## m/s, below this the markers are hidden
@export var marker_deg: float = 0.8
## Each bar runs from bar_from_deg to bar_to_deg either side of the marker.
@export var bar_from_deg: float = 1.8
@export var bar_to_deg: float = 6.5
@export var dash_spacing_deg: float = 0.55
@export var dash_height_deg: float = 0.45
## Dash stream speed, deg/s: base + per decade of speed (m/s).
@export var flow_base_deg: float = 0.6
@export var flow_per_decade_deg: float = 0.9


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var v := fc.state.linear_velocity
	var speed := v.length()
	if speed < min_speed:
		return
	var flow := flow_base_deg + flow_per_decade_deg * log(speed + 1.0) / log(10.0)
	var phase := fposmod(Time.get_ticks_msec() / 1000.0 * flow, dash_spacing_deg)
	var up := Vector3.UP
	_marker(patch(hud.world_to_display(v), up), phase, true)
	_marker(patch(hud.world_to_display(-v), up), phase, false)


func _marker(p: Patch, phase: float, prograde: bool) -> void:
	var c := hud.primary_color if prograde else PanoramicHud.dimmed(hud.primary_color)
	var r := marker_deg
	if prograde:
		patch_arc(p, Vector2.ZERO, r, 0.0, TAU, c, 0.0, 20)
		patch_line(p, Vector2(0, r), Vector2(0, r * 1.9), c, 0.0, 1)
	else:
		var k := r * 0.75
		patch_line(p, Vector2(-k, -k), Vector2(k, k), c, 0.0, 2)
		patch_line(p, Vector2(-k, k), Vector2(k, -k), c, 0.0, 2)
	# Inward toward the circle, outward from the X.
	var shift := -phase if prograde else phase
	var h := dash_height_deg * 0.5
	var span := bar_to_deg - bar_from_deg
	for side in [-1.0, 1.0]:
		var x := bar_from_deg + fposmod(shift, dash_spacing_deg)
		while x <= bar_to_deg:
			# Fade in and out at the bar's ends so dashes don't pop.
			var t := (x - bar_from_deg) / span
			var fade := clampf(minf(t, 1.0 - t) * 5.0, 0.0, 1.0)
			var lean := 0.22  # tops lean outward on both sides, like a lane converging ahead
			patch_line(p, Vector2((x + lean) * side, h), Vector2((x - lean) * side, -h),
					Color(c, c.a * fade), 0.0, 1)
			x += dash_spacing_deg
		# Thin rails above and below the dashes.
		for y in [h * 1.6, -h * 1.6]:
			patch_line(p, Vector2(bar_from_deg * side, y), Vector2(bar_to_deg * side, y),
					PanoramicHud.dimmed(c), 1.5, 4)
