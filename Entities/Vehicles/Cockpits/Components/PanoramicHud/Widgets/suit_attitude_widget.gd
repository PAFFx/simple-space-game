class_name SuitAttitudeWidget
extends HudWidget

## The suit's orientation against the cockpit (which auto-rotation can lean or roll
## away from the suit):
##
##   90° left / right   side-view PITCH dials: a segmented ring around the long
##                      cockpit-level bar, with a pointer on the ring at the suit's nose
##   ahead              two split bars either side of the boresight, rolled and lifted
##                      with the suit: its wings, read against the cockpit's horizon
##
## Mostly level; they come alive when auto-rotation leans or rolls the suit.

@export var side_azimuth_deg: float = 90.0
@export var side_radius_deg: float = 13.0
@export var ring_segments: int = 36
## Front bars: from bar_from_deg to bar_to_deg either side of the boresight.
@export var bar_from_deg: float = 7.5
@export var bar_to_deg: float = 16.5
## Below this the readouts are drawn dim.
@export var active_deg: float = 1.0


func draw_widget() -> void:
	if hud.vehicle == null:
		return
	var display := hud.get_display_basis()
	var body := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	var rel := display.inverse() * body
	var fwd := rel * Vector3.FORWARD
	var pitch := atan2(fwd.y, -fwd.z)
	var right := rel * Vector3.RIGHT
	var roll := atan2(-right.y, right.x)  # + = rolled right (right shoulder down)

	_side_dial(-1.0, pitch)
	_side_dial(1.0, pitch)
	_front_bars(rel, roll)


## side: -1 = left of the pilot, +1 = right. The suit's nose is toward the front.
func _side_dial(side: float, pitch: float) -> void:
	var centre := Vector3(side, 0, 0)
	var p := patch(centre, Vector3.UP)
	var r := side_radius_deg
	var c := hud.suit_color
	var dim := PanoramicHud.dimmed(c)
	var faint := Color(c, c.a * 0.45)
	# Facing right the front is to the patch's left, facing left to its right.
	var front := -side

	# Dotted outer ring.
	for i in 72:
		var a := TAU * i / 72.0
		patch_line(p, Vector2(cos(a), sin(a)) * r * 1.32, Vector2(cos(a), sin(a)) * r * 1.34, dim, 2.0, 1)
	# Segmented ring of trapezoid blocks.
	var gap := 0.3 * TAU / ring_segments
	for i in ring_segments:
		var a0 := TAU * i / ring_segments + gap * 0.5
		var a1 := TAU * (i + 1) / ring_segments - gap * 0.5
		patch_polygon(p, PackedVector2Array([
			Vector2(cos(a0), sin(a0)) * r * 0.86, Vector2(cos(a0), sin(a0)) * r,
			Vector2(cos(a1), sin(a1)) * r, Vector2(cos(a1), sin(a1)) * r * 0.86,
		]), faint)
	# Long cockpit-level double bar, split around the centre.
	for s in [-1.0, 1.0]:
		for y in [0.18, -0.18]:
			patch_line(p, Vector2(1.4 * s, y), Vector2(r * 1.65 * s, y), dim, 1.5, 8)
		for k in range(2, int(r * 1.6), 2):
			patch_line(p, Vector2(k * s, 0.18), Vector2(k * s, 0.6 if k % 6 == 0 else 0.35), dim, 1.5, 1)
	patch_arc(p, Vector2.ZERO, 1.0, 0.0, TAU, dim, 1.5, 16)

	# The suit: a line through the centre at its pitch and a pointer on the ring at its nose.
	var active := absf(rad_to_deg(pitch)) >= active_deg
	var sc := c if active else dim
	var nose := Vector2(cos(pitch) * front, sin(pitch))
	patch_line(p, -nose * r * 0.8, nose * r * 0.8, sc, 0.0, 8)
	var tip := nose * r * 1.12
	var across := Vector2(-nose.y, nose.x)
	patch_polygon(p, PackedVector2Array([tip, nose * r * 0.9 + across * 1.1, nose * r * 0.9 - across * 1.1]), sc)
	patch_text(p, Vector2(0, -r * 1.5), "PITCH %+d°" % roundi(rad_to_deg(pitch)), sc,
			HORIZONTAL_ALIGNMENT_CENTER, 22)


## Split bars on the suit's body axis, along its right and up (so they roll and lift with it).
func _front_bars(rel: Basis, roll: float) -> void:
	var p := patch(rel * Vector3.FORWARD, rel * Vector3.UP)
	var c := hud.suit_color
	var dim := PanoramicHud.dimmed(c)
	for s in [-1.0, 1.0]:
		for y in [0.16, -0.16]:
			patch_line(p, Vector2(bar_from_deg * s, y), Vector2(bar_to_deg * s, y), c, 2.0, 8)
		for k in range(int(bar_from_deg) + 2, int(bar_to_deg), 2):
			patch_line(p, Vector2(k * s, -0.16), Vector2(k * s, -0.5), dim, 1.5, 1)
		# Diamond at the inner end, pointing at the boresight.
		var x: float = bar_from_deg * s
		patch_polygon(p, PackedVector2Array([
			Vector2(x - 0.55 * s, 0), Vector2(x, 0.4), Vector2(x + 0.55 * s, 0), Vector2(x, -0.4),
		]), c)
	var active := absf(rad_to_deg(roll)) >= active_deg
	patch_text(p, Vector2(bar_to_deg + 0.6, 0.35), "%+d°" % roundi(rad_to_deg(roll)),
			c if active else dim, HORIZONTAL_ALIGNMENT_LEFT, 16)
