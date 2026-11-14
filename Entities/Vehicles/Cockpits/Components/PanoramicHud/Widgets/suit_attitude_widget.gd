class_name SuitAttitudeWidget
extends HudWidget

## The suit's orientation against the cockpit (which auto-rotation can lean or roll
## away from the suit):
##
##   suit line          the suit's horizontal plane (its forward and right axes) as one
##                      double-rail great circle all the way round, open ahead: ahead it
##                      tilts with the suit's roll and lifts with its pitch, beside you
##                      it slopes with the pitch, side-on
##   arrowheads         at the edges of the opening, pointing in; midway between them
##                      is the suit's nose
##   90° left / right   segmented rings with cockpit-level marks to read the slope
##                      against
##
## Mostly level; they come alive when auto-rotation leans or rolls the suit.
##
## Nothing here is redrawn per frame: the suit line and arrowheads are drawn once in the
## suit's frame (the suit layer, turned into place by the screen shader), the side rings
## once in the static layer.

@export var side_radius_deg: float = 13.0
@export var ring_segments: int = 36
## Half the opening ahead, deg along the suit line from its nose to the arrow tips.
@export var front_gap_deg: float = 14.0
## Rail half-spacing, deg; the rails go dim behind this bearing from the nose.
@export var rail_offset_deg: float = 0.3
@export var rail_bright_deg: float = 100.0
@export var sample_step_deg: float = 1.5

## Arrowhead size: 1 = 2.6° long; the rails start where it ends.
@export var arrow_scale: float = 1.7

const ARROW_LEN := 2.6


func setup_layers() -> void:
	hud.add_layer_drawer(&"suit", _draw_suit_frame)
	hud.add_layer_drawer(&"static", _draw_side_rings)


func _process(_delta: float) -> void:
	if hud == null or not hud.is_live() or hud.vehicle == null:
		return
	# The suit layer is drawn with the body level in the display; turn it by the body
	# relative to the display.
	var display := hud.get_display_basis()
	var body := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	hud.set_hud_parameter(&"hud_suit_frame", (display.inverse() * body).inverse())


func draw_widget() -> void:
	pass


func _draw_suit_frame(w: HudWidget) -> void:
	_suit_line(w, Basis.IDENTITY)
	for side in [-1.0, 1.0]:
		_arrowhead(w, Basis.IDENTITY, side)


func _draw_side_rings(w: HudWidget) -> void:
	for side in [-1.0, 1.0]:
		_side_ring(w, side)


## Direction on the suit line, `bearing` rad from the suit's nose (+ = right), lifted
## `lift` rad along the suit's up. Display frame.
func _line_dir(rel: Basis, bearing: float, lift: float) -> Vector3:
	var flat := Vector3(sin(bearing), 0.0, -cos(bearing)) * cos(lift)
	return rel * (flat + Vector3.UP * sin(lift))


## Two rails from the arrow tails round the back, ticks hanging below the lower rail.
func _suit_line(w: HudWidget, rel: Basis) -> void:
	var c := hud.suit_color
	var dim := PanoramicHud.dimmed(c)
	var faint := Color(c, c.a * 0.4)
	var start := front_gap_deg + ARROW_LEN * arrow_scale
	var lift := deg_to_rad(rail_offset_deg)
	for s in [-1.0, 1.0]:
		for y in [lift, -lift]:
			var near := PackedVector2Array()
			var far := PackedVector2Array()
			var b := start
			while b <= 180.0:
				var at := hud.projector.direction_to_canvas(_line_dir(rel, deg_to_rad(b * s), y))
				# Overlap one sample so the bright and dim parts join.
				if b <= rail_bright_deg + sample_step_deg:
					near.append(at)
				if b >= rail_bright_deg - sample_step_deg:
					far.append(at)
				b = minf(b + sample_step_deg, 180.0) if b < 180.0 else 181.0
			w.seam_safe_polyline(near, c, 1.5, false)
			w.seam_safe_polyline(far, dim, 1.2, false)
		# Faint wide band between the rails, in front.
		var band := PackedVector2Array()
		var b2 := start
		while b2 <= rail_bright_deg:
			band.append(hud.projector.direction_to_canvas(_line_dir(rel, deg_to_rad(b2 * s), 0.0)))
			b2 += sample_step_deg
		w.seam_safe_polyline(band, Color(c, c.a * 0.22), rail_offset_deg * 2.0 * hud.projector.px_per_deg, false)
		# Ticks every 5°, longer every 30°.
		var k := ceili(start / 5.0) * 5
		while k < 180:
			var long := k % 30 == 0
			var color := (c if k <= rail_bright_deg else dim) if long else faint
			var a := deg_to_rad(float(k) * s)
			var depth := deg_to_rad(0.75 if long else 0.4)
			w.line(hud.projector.direction_to_canvas(_line_dir(rel, a, -lift)),
					hud.projector.direction_to_canvas(_line_dir(rel, a, -lift - depth)), color, 1.5, false)
			k += 5


## Arrowhead at the edge of the opening, pointing at the nose: a tinted, outlined
## pentagon with a chevron inside, and a small accent chevron just ahead of it.
func _arrowhead(w: HudWidget, rel: Basis, side: float) -> void:
	var p := w.patch(_line_dir(rel, deg_to_rad(front_gap_deg * side), 0.0), rel * Vector3.UP)
	var accent := hud.suit_accent_color
	var c := hud.suit_color
	# u = distance outward from the tip along the line, v = up.
	var k := arrow_scale
	var pt := func(u: float, v: float) -> Vector2: return Vector2(u * side, v) * k
	var shape := PackedVector2Array([pt.call(0.0, 0.0), pt.call(1.1, 0.85),
			pt.call(ARROW_LEN, 0.85), pt.call(ARROW_LEN, -0.85), pt.call(1.1, -0.85)])
	w.patch_polygon(p, shape, Color(accent, accent.a * 0.28))
	for i in shape.size():
		w.patch_line(p, shape[i], shape[(i + 1) % shape.size()], accent, 2.0, 3)
	# Inner chevron, pointing in.
	w.patch_line(p, pt.call(1.7, 0.45), pt.call(1.0, 0.0), c, 2.0, 2)
	w.patch_line(p, pt.call(1.0, 0.0), pt.call(1.7, -0.45), c, 2.0, 2)
	# Accent chevron ahead of the tip.
	w.patch_line(p, pt.call(-0.35, 0.6), pt.call(-0.95, 0.0), accent, 2.5, 2)
	w.patch_line(p, pt.call(-0.95, 0.0), pt.call(-0.35, -0.6), accent, 2.5, 2)


## side: -1 = left of the pilot, +1 = right. The suit line runs through the centre;
## the marks at the ring's front and back are cockpit level.
func _side_ring(w: HudWidget, side: float) -> void:
	var p := w.patch(Vector3(side, 0, 0), Vector3.UP)
	var r := side_radius_deg
	var c := hud.suit_color
	var dim := PanoramicHud.dimmed(c)
	var faint := Color(c, c.a * 0.45)

	# Dotted outer ring.
	for i in 72:
		var a := TAU * i / 72.0
		w.patch_line(p, Vector2(cos(a), sin(a)) * r * 1.32, Vector2(cos(a), sin(a)) * r * 1.34, dim, 2.0, 1)
	# Segmented ring of trapezoid blocks.
	var gap := 0.3 * TAU / ring_segments
	for i in ring_segments:
		var a0 := TAU * i / ring_segments + gap * 0.5
		var a1 := TAU * (i + 1) / ring_segments - gap * 0.5
		w.patch_polygon(p, PackedVector2Array([
			Vector2(cos(a0), sin(a0)) * r * 0.86, Vector2(cos(a0), sin(a0)) * r,
			Vector2(cos(a1), sin(a1)) * r, Vector2(cos(a1), sin(a1)) * r * 0.86,
		]), faint)
	# Cockpit-level marks just outside the ring, front and back.
	for s in [-1.0, 1.0]:
		w.patch_line(p, Vector2(r * 1.05 * s, 0), Vector2(r * 1.25 * s, 0), dim, 2.0, 1)
