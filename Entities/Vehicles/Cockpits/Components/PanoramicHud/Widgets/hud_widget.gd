@abstract
class_name HudWidget
extends Node2D

## Base for HUD instruments. Place under PanoramicHud/HudViewport.
## Widgets lay themselves out in panoramic angles (degrees), so the HUD keeps its
## angular size regardless of canvas resolution.

var hud: PanoramicHud


func _ready() -> void:
	var node := get_parent()
	while node != null and not node is PanoramicHud:
		node = node.get_parent()
	hud = node as PanoramicHud


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if hud != null and hud.is_live():
		draw_widget()
		end_local()


## Override: draw this instrument.
@abstract func draw_widget() -> void


# --- Layout helpers ---

## Degrees → canvas pixels.
func px(deg: float) -> float:
	return deg * hud.projector.px_per_deg


## Start drawing in a local frame centred at (azimuth, elevation) in degrees,
## where 1 unit = 1 canvas pixel and equirectangular stretch is compensated.
func begin_local(azimuth_deg: float, elevation_deg: float) -> void:
	var pos := hud.projector.angles_deg_to_canvas(azimuth_deg, elevation_deg)
	begin_local_at(pos, deg_to_rad(elevation_deg))


func begin_local_at(canvas_pos: Vector2, elevation: float) -> void:
	draw_set_transform(canvas_pos, 0.0, Vector2(HudProjector.stretch_at(elevation), 1.0))


func end_local() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)


func text(pos: Vector2, value: String, color: Color = Color.TRANSPARENT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, size: int = 0) -> void:
	var c := hud.primary_color if color.a == 0.0 else color
	var s := hud.font_size if size <= 0 else size
	var offset := 0.0
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := hud.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
		offset = w * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	var at := pos - Vector2(offset, 0.0)
	if hud.halo_color.a > 0.0:
		draw_string_outline(hud.font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, s,
				roundi(hud.halo_width * 1.5), hud.halo_color)
	draw_string(hud.font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, s, c)


## Text at a canvas position (outside a local frame), widened by the canvas stretch at
## its elevation so it keeps its shape on the sphere instead of thinning toward the poles.
func text_at(canvas_pos: Vector2, value: String, color: Color = Color.TRANSPARENT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, size: int = 0) -> void:
	var elevation := (0.5 - canvas_pos.y / hud.projector.size.y) * hud.projector.elevation_range
	draw_set_transform(canvas_pos, 0.0, Vector2(HudProjector.stretch_at(elevation), 1.0))
	text(Vector2.ZERO, value, color, align, size)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## halo: false for hairlines, where the dark edge would outweigh the line.
func line(a: Vector2, b: Vector2, color: Color = Color.TRANSPARENT, width: float = 0.0,
		halo := true) -> void:
	var w := hud.line_width if width <= 0.0 else width
	if halo and hud.halo_color.a > 0.0:
		draw_line(a, b, hud.halo_color, w + hud.halo_width, true)
	draw_line(a, b, hud.primary_color if color.a == 0.0 else color, w, true)


## Corner brackets around a rectangle centred at the local origin.
func brackets(half: Vector2, corner: float, color: Color) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := Vector2(half.x * sx, half.y * sy)
			line(c, c - Vector2(corner * sx, 0.0), color)
			line(c, c - Vector2(0.0, corner * sy), color)


# --- Patches: shapes laid out in degrees around a direction ---
# Every point is turned into a direction and projected on its own, so a shape keeps
# its form anywhere on the sphere (beside the pilot, overhead, at the feet), unlike a
# flat drawing in a stretched local frame.

## A small patch of the sphere: `centre` and its `right` / `up` axes, display frame.
## `exact`: strokes and text are built on the sphere instead of on the canvas, so they
## keep their width and shape at the poles, where the canvas squeezes azimuth to a point.
class Patch:
	var centre: Vector3
	var right: Vector3
	var up: Vector3
	var exact := false


## Patch around `centre` (display frame) with `up_hint` as its up (made perpendicular).
func patch(centre: Vector3, up_hint: Vector3, exact := false) -> Patch:
	var p := Patch.new()
	p.centre = centre.normalized()
	p.exact = exact
	var up := up_hint - p.centre * up_hint.dot(p.centre)
	if up.length_squared() < 1e-8:
		up = Vector3.BACK - p.centre * p.centre.z
	p.up = up.normalized()
	p.right = p.up.cross(p.centre).normalized() * -1.0
	return p


## Canvas position of the point `deg` (x right, y up, degrees) from the patch centre.
func patch_point(p: Patch, deg: Vector2) -> Vector2:
	var d := p.centre + p.right * tan(deg_to_rad(deg.x)) + p.up * tan(deg_to_rad(deg.y))
	return hud.projector.direction_to_canvas(d)


func patch_line(p: Patch, a: Vector2, b: Vector2, color: Color, width: float = 0.0,
		steps: int = 6) -> void:
	if p.exact:
		steps = maxi(steps, ceili(a.distance_to(b) / EXACT_STEP_DEG))
	var deg := PackedVector2Array()
	for k in steps + 1:
		deg.append(a.lerp(b, float(k) / steps))
	_patch_polyline(p, deg, color, width)


## Arc of `radius` degrees about `centre` (degrees), angles in radians from +x, CCW = up.
func patch_arc(p: Patch, centre: Vector2, radius: float, from: float, to: float, color: Color,
		width: float = 0.0, segments: int = 32) -> void:
	if p.exact:
		segments = maxi(segments, ceili(absf(to - from) * radius / EXACT_STEP_DEG))
	var deg := PackedVector2Array()
	for k in segments + 1:
		var a := lerpf(from, to, float(k) / segments)
		deg.append(centre + Vector2(cos(a), sin(a)) * radius)
	_patch_polyline(p, deg, color, width)


## Filled polygon given in patch degrees.
func patch_polygon(p: Patch, deg_points: PackedVector2Array, color: Color) -> void:
	var pts := PackedVector2Array()
	for d in deg_points:
		pts.append(patch_point(p, d))
	if p.exact:
		_canvas_polygon(pts, color)
	else:
		draw_colored_polygon(pts, color)


func patch_text(p: Patch, deg: Vector2, value: String, color: Color = Color.TRANSPARENT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, size: int = 0) -> void:
	if not p.exact:
		text_at(patch_point(p, deg), value, color, align, size)
		return
	# Local frame from the projection's derivative: upright in the patch, true to shape.
	var at := patch_point(p, deg)
	var e := 0.05
	var per_px := 1.0 / (e * hud.projector.px_per_deg)
	var ax := _seam_delta(patch_point(p, deg + Vector2(e, 0)) - at) * per_px
	var ay := _seam_delta(patch_point(p, deg + Vector2(0, e)) - at) * per_px
	var w := hud.projector.size.x
	for shift in _seam_copies(at.x, at.x, w * 0.1):
		draw_set_transform_matrix(Transform2D(ax, -ay, at + Vector2(shift, 0)))
		text(Vector2.ZERO, value, color, align, size)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --- Exact patches ---

## Longest piece an exact stroke is cut into, deg.
const EXACT_STEP_DEG := 0.4


func _patch_polyline(p: Patch, deg: PackedVector2Array, color: Color, width: float) -> void:
	if not p.exact:
		var pts := PackedVector2Array()
		for d in deg:
			pts.append(patch_point(p, d))
		seam_safe_polyline(pts, color, width)
		return
	var w := hud.line_width if width <= 0.0 else width
	if hud.halo_color.a > 0.0:
		_patch_stroke(p, deg, (w + hud.halo_width) / hud.projector.px_per_deg, hud.halo_color)
	_patch_stroke(p, deg, w / hud.projector.px_per_deg, color)


## Each piece as a quad laid out in degrees, so the stroke is as wide across as along.
func _patch_stroke(p: Patch, deg: PackedVector2Array, width_deg: float, color: Color) -> void:
	var hw := width_deg * 0.5
	for i in range(1, deg.size()):
		var a := deg[i - 1]
		var b := deg[i]
		if a.is_equal_approx(b):
			continue
		var n := (b - a).orthogonal().normalized() * hw
		_canvas_polygon(PackedVector2Array([patch_point(p, a + n), patch_point(p, b + n),
				patch_point(p, b - n), patch_point(p, a - n)]), color)


## Polygon in canvas pixels, unwrapped across the back seam and drawn on both sides of it.
## Skipped if it spans much of the azimuth (it sits on the pole itself).
func _canvas_polygon(pts: PackedVector2Array, color: Color) -> void:
	var w := hud.projector.size.x
	var lo := pts[0].x
	var hi := lo
	for k in range(1, pts.size()):
		var q := pts[0] + _seam_delta(pts[k] - pts[0])
		pts[k] = q
		lo = minf(lo, q.x)
		hi = maxf(hi, q.x)
	if hi - lo > w * 0.25:
		return
	for shift in _seam_copies(lo, hi, 0.0):
		var shifted := PackedVector2Array()
		for q in pts:
			shifted.append(q + Vector2(shift, 0))
		if shifted.size() <= 4:
			draw_primitive(shifted, PackedColorArray([color]), PackedVector2Array())
		else:
			draw_colored_polygon(shifted, color)


## A canvas offset taken the short way round the seam.
func _seam_delta(v: Vector2) -> Vector2:
	var w := hud.projector.size.x
	return Vector2(wrapf(v.x, -w * 0.5, w * 0.5), v.y)


## Horizontal shifts to draw something spanning [lo, hi] at: itself, plus a copy on the
## other side of the canvas if it comes within `margin` of an edge.
func _seam_copies(lo: float, hi: float, margin: float) -> Array[float]:
	var w := hud.projector.size.x
	var shifts: Array[float] = [0.0]
	if lo < margin:
		shifts.append(w)
	if hi > w - margin:
		shifts.append(-w)
	return shifts


## Polyline through canvas points, broken where it wraps across the back seam.
func seam_safe_polyline(points: PackedVector2Array, color: Color, width: float = 0.0,
		halo := true) -> void:
	var limit := hud.projector.size.x * 0.25
	for i in range(1, points.size()):
		if points[i].distance_to(points[i - 1]) < limit:
			line(points[i - 1], points[i], color, width, halo)
