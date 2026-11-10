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
	draw_string(hud.font, pos - Vector2(offset, 0.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, s, c)


func line(a: Vector2, b: Vector2, color: Color = Color.TRANSPARENT, width: float = 0.0) -> void:
	draw_line(a, b, hud.primary_color if color.a == 0.0 else color,
			hud.line_width if width <= 0.0 else width, true)


## Corner brackets around a rectangle centred at the local origin.
func brackets(half: Vector2, corner: float, color: Color) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var c := Vector2(half.x * sx, half.y * sy)
			line(c, c - Vector2(corner * sx, 0.0), color)
			line(c, c - Vector2(0.0, corner * sy), color)


## Polyline through canvas points, broken where it wraps across the back seam.
func seam_safe_polyline(points: PackedVector2Array, color: Color, width: float = 0.0) -> void:
	var limit := hud.projector.size.x * 0.25
	for i in range(1, points.size()):
		if points[i].distance_to(points[i - 1]) < limit:
			line(points[i - 1], points[i], color, width)
