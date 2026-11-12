class_name HatchWidget
extends HudWidget

## While the hatch is unsealed: orange segmented brackets around all four edges of the
## screen's hatch opening, hugging it, with a HATCH / UNLOCK tab over each top corner,
## chevron pointing in (SEALING while it closes). Placed from the screen's own aperture
## settings, in the same flat frame as the opening, so they line up with its edges.

@export var color := Color(1.0, 0.42, 0.18, 0.92)
## Gap between the opening's edge and the brackets, deg.
@export var gap_deg: float = 0.4
## Bracket depth outward (middle segment deeper), deg.
@export var depth_deg := Vector2(1.8, 2.6)
@export var side_segments: int = 5
@export var cap_segments: int = 4


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

	for s: float in [-1.0, 1.0]:
		# Left / right edges: segments stacked up the side, outward in x.
		_edge(p, Vector2(s, 0), Vector2(0, 1), half.x + gap_deg, half.y, side_segments, c, fill)
		# Top / bottom edges: segments along the edge, outward in y.
		_edge(p, Vector2(0, s), Vector2(1, 0), half.y + gap_deg, half.x, cap_segments, c, fill)

	var words := ["HATCH", "UNLOCK" if hatch.is_open() else "SEALING"]
	for s: float in [-1.0, 1.0]:
		# Tab over the top corner (clear of the side displays), chevron toward the opening.
		var tx := (half.x - 1.5) * s
		var ty := half.y + gap_deg + depth_deg.y + 2.6
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


## One edge's bracket: `segments` slanted slabs along `along` (from −length to +length),
## starting `offset` out along `out`, with a solid line on their inner side.
func _edge(p: Patch, out: Vector2, along: Vector2, offset: float, length: float, segments: int,
		c: Color, fill: Color) -> void:
	var step := length * 2.0 / segments
	for i in segments:
		var a0 := -length + step * i + 0.25
		var a1 := a0 + step - 0.5
		var mid := (a0 + a1) * 0.5
		var d := depth_deg.y if i == segments / 2 else depth_deg.x
		var lean := signf(mid) * 0.5  # slabs lean away from the edge's middle
		var inner0 := out * offset + along * a0
		var inner1 := out * offset + along * a1
		patch_polygon(p, PackedVector2Array([
			inner0, inner1, inner1 + out * d + along * lean, inner0 + out * d + along * lean,
		]), fill)
		patch_line(p, inner0, inner1, c, 2.5, 2)
