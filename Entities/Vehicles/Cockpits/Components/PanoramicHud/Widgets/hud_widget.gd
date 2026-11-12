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


func line(a: Vector2, b: Vector2, color: Color = Color.TRANSPARENT, width: float = 0.0) -> void:
	var w := hud.line_width if width <= 0.0 else width
	if hud.halo_color.a > 0.0:
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
class Patch:
	var centre: Vector3
	var right: Vector3
	var up: Vector3


## Patch around `centre` (display frame) with `up_hint` as its up (made perpendicular).
func patch(centre: Vector3, up_hint: Vector3) -> Patch:
	var p := Patch.new()
	p.centre = centre.normalized()
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
	var pts := PackedVector2Array()
	for k in steps + 1:
		pts.append(patch_point(p, a.lerp(b, float(k) / steps)))
	seam_safe_polyline(pts, color, width)


## Arc of `radius` degrees about `centre` (degrees), angles in radians from +x, CCW = up.
func patch_arc(p: Patch, centre: Vector2, radius: float, from: float, to: float, color: Color,
		width: float = 0.0, segments: int = 32) -> void:
	var pts := PackedVector2Array()
	for k in segments + 1:
		var a := lerpf(from, to, float(k) / segments)
		pts.append(patch_point(p, centre + Vector2(cos(a), sin(a)) * radius))
	seam_safe_polyline(pts, color, width)


## Filled polygon given in patch degrees.
func patch_polygon(p: Patch, deg_points: PackedVector2Array, color: Color) -> void:
	var pts := PackedVector2Array()
	for d in deg_points:
		pts.append(patch_point(p, d))
	draw_colored_polygon(pts, color)


func patch_text(p: Patch, deg: Vector2, value: String, color: Color = Color.TRANSPARENT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, size: int = 0) -> void:
	text_at(patch_point(p, deg), value, color, align, size)


## Polyline through canvas points, broken where it wraps across the back seam.
func seam_safe_polyline(points: PackedVector2Array, color: Color, width: float = 0.0) -> void:
	var limit := hud.projector.size.x * 0.25
	for i in range(1, points.size()):
		if points[i].distance_to(points[i - 1]) < limit:
			line(points[i - 1], points[i], color, width)
