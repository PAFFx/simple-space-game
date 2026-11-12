class_name TargetPage
extends MfdPage

## Target information. Placeholder until targeting exists: the page's layout with no
## target selected.


func draw_page() -> void:
	label(Vector2(20, 34), "TGT", INFO, 22)
	var r := Rect2(20, 64, size.x - 40, size.y - 100)
	window(r, "TARGET")
	label(r.get_center() + Vector2(0, 8), "NO TARGET", DIM, 30, HORIZONTAL_ALIGNMENT_CENTER)
	var y := r.end.y - 70.0
	for i in 3:
		var x := r.position.x + 20.0 + i * (r.size.x - 40.0) / 3.0
		label(Vector2(x, y), ["RNG", "Vc", "ASPECT"][i], DIM, 14)
		label(Vector2(x, y + 28), "---", DIM, 20)
