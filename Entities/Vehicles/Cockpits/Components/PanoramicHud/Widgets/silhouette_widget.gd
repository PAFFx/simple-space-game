class_name SilhouetteWidget
extends HudWidget

## Draws every HudSilhouette (group `hud_silhouettes`) as an outline, seen from
## the sensor head, like the image around it: a fine rim with a bold bracket at every
## corner and the label on a tab. Edges are subdivided because straight 3D edges curve
## on the equirectangular canvas.

@export var subdivisions: int = 12
@export var label_offset := Vector2(10.0, -10.0)
## Share of each edge, from either end, drawn as the corner bracket.
@export var bracket_fraction: float = 0.17
@export var bracket_width: float = 4.5
@export var rim_width: float = 1.5


func draw_widget() -> void:
	var origin := hud.get_view_origin()
	var color := hud.equipment_color
	var rim_color := Color(color, color.a * 0.7)
	var bracket := maxi(roundi(subdivisions * bracket_fraction), 1)
	for node in get_tree().get_nodes_in_group(HudSilhouette.GROUP):
		var sil := node as HudSilhouette
		if sil == null or not sil.is_visible_in_tree():
			continue
		var pts := sil.get_world_outline()
		if pts.size() < 2:
			continue
		var canvas := PackedVector2Array()
		var edges := pts.size() if sil.closed else pts.size() - 1
		for i in edges:
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			for k in subdivisions:
				canvas.append(hud.world_dir_to_canvas(a.lerp(b, float(k) / subdivisions) - origin))
		if not sil.closed:
			canvas.append(hud.world_dir_to_canvas(pts[-1] - origin))
		elif not canvas.is_empty():
			canvas.append(canvas[0])
		seam_safe_polyline(canvas, rim_color, rim_width)
		# Brackets: the stretch around each corner (an open outline's two ends have none).
		for i in pts.size():
			if not sil.closed and (i == 0 or i == pts.size() - 1):
				continue
			var at := i * subdivisions
			var run := PackedVector2Array()
			for k in range(-bracket, bracket + 1):
				run.append(canvas[posmod(at + k, edges * subdivisions)])
			seam_safe_polyline(run, color, bracket_width)
		if sil.label != "":
			var top := canvas[0]
			for p in canvas:
				if p.y < top.y:
					top = p
			_label_tab(top + label_offset, sil.label, color)


## The label over a short underline with a slanted lead back toward the outline.
func _label_tab(at: Vector2, value: String, color: Color) -> void:
	var elevation := (0.5 - at.y / hud.projector.size.y) * hud.projector.elevation_range
	begin_local_at(at, elevation)
	var width := hud.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	text(Vector2(6.0, -5.0), value, color, HORIZONTAL_ALIGNMENT_LEFT, 14)
	draw_polyline(PackedVector2Array([Vector2(-8.0, 8.0), Vector2(0.0, 0.0), Vector2(width + 12.0, 0.0)]),
			color, 1.5, true)
	draw_rect(Rect2(width + 12.0, -4.0, 4.0, 4.0), color, true)
	end_local()
