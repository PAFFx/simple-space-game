class_name HatchWidget
extends HudWidget

## While the hatch is unsealed: orange segmented brackets down both sides of the screen's
## hatch opening, with a HATCH / UNLOCK tab over each top corner, chevron pointing in
## (SEALING while it closes). Placed from the screen's own aperture settings.

@export var color := Color(1.0, 0.42, 0.18, 0.92)
@export var segments: int = 5
@export var frame_clearance_deg: float = 5.0


func draw_widget() -> void:
	var hatch := hud.hatch
	var screen := hud.panoramic_screen
	if hatch == null or screen == null or not hatch.is_unsealed():
		return
	var fade := clampf(hatch.amount * 6.0, 0.0, 1.0)
	var c := Color(color, color.a * fade)
	var fill := Color(color, color.a * fade * 0.55)
	var centre_deg: Vector2 = screen.aperture_center_deg
	var half: Vector2 = screen.aperture_half_size_deg
	var az := deg_to_rad(centre_deg.x)
	var el := deg_to_rad(centre_deg.y)
	var p := patch(Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)), Vector3.UP)
	var words := ["HATCH", "UNLOCK" if hatch.is_open() else "SEALING"]
	for s: float in [-1.0, 1.0]:
		# Outside the cockpit's portal frame around the opening (it hides the first ~5°).
		var x0 := (half.x + frame_clearance_deg) * s
		# Segmented bracket: slanted slabs stacked along the edge, leaning away from the middle.
		var h := half.y * 2.0 / segments
		for i in segments:
			var y0 := -half.y + h * i + 0.15
			var y1 := y0 + h - 0.3
			var lean := (0.5 if (y0 + y1) * 0.5 > 0.0 else -0.5) * 0.6
			var w := 1.1 if i == segments / 2 else 0.7
			patch_polygon(p, PackedVector2Array([
				Vector2(x0, y0), Vector2(x0 + w * s, y0 + lean * 0.0),
				Vector2(x0 + (w + absf(lean)) * s, y1), Vector2(x0 + absf(lean) * s, y1),
			]), fill)
			patch_line(p, Vector2(x0, y0), Vector2(x0, y1), c, 2.0, 2)
		# Tab with the label over the top corner (clear of the side displays), chevron in.
		var tx := (half.x + frame_clearance_deg - 1.0) * s
		var ty := half.y + frame_clearance_deg + 1.8
		var tw := 3.6
		var th := 1.6
		var tab := PackedVector2Array([
			Vector2(tx - tw * s, ty + th), Vector2(tx + tw * s, ty + th), Vector2(tx + (tw + 0.9) * s, ty),
			Vector2(tx + tw * s, ty - th), Vector2(tx - tw * s, ty - th), Vector2(tx - (tw + 0.9) * s, ty),
		])
		patch_polygon(p, tab, Color(color, color.a * fade * 0.35))
		for k in tab.size():
			patch_line(p, tab[k], tab[(k + 1) % tab.size()], c, 2.0, 2)
		var chev := tx - (tw + 1.6) * s
		patch_line(p, Vector2(chev - 0.6 * s, ty + 0.7), Vector2(chev, ty), c, 2.5, 1)
		patch_line(p, Vector2(chev, ty), Vector2(chev - 0.6 * s, ty - 0.7), c, 2.5, 1)
		patch_text(p, Vector2(tx, ty + 0.15), words[0], c, HORIZONTAL_ALIGNMENT_CENTER, 18)
		patch_text(p, Vector2(tx, ty - 1.0), words[1], c, HORIZONTAL_ALIGNMENT_CENTER, 18)
