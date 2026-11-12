class_name SilhouetteWidget
extends HudWidget

## Draws every HudSilhouette (group `hud_silhouettes`) as an outline, seen from
## the sensor head, like the image around it. Edges are subdivided because straight 3D edges curve on the
## equirectangular canvas.

@export var subdivisions: int = 12
@export var label_offset := Vector2(8.0, -8.0)


func draw_widget() -> void:
	var origin := hud.get_view_origin()
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
		seam_safe_polyline(canvas, hud.dim_color)
		if sil.label != "":
			var top := canvas[0]
			for p in canvas:
				if p.y < top.y:
					top = p
			text_at(top + label_offset, sil.label, hud.dim_color, HORIZONTAL_ALIGNMENT_LEFT, 14)
