class_name HudSilhouette
extends Node3D

## Outline of a nearby object drawn on the panoramic HUD instead of the object
## itself, e.g. a shield the sensor sees "through" (SilhouetteWidget draws it).

const GROUP := &"hud_silhouettes"

## Outline points in this node's local space.
@export var outline := PackedVector3Array()
## Build `outline` from the models under the parent instead: their rim seen face-on
## (across the model's thinnest axis), each corner kept at its real depth, so a curved
## shield's outline sits on its actual edge.
@export var from_meshes: bool = false
## Corners turning less than this are dropped from a built outline, deg.
@export var min_corner_deg: float = 4.0
@export var closed: bool = true
@export var label: String = ""


func _ready() -> void:
	add_to_group(GROUP)
	if from_meshes:
		outline = _rim_from_meshes()


## World-space outline at the rendered (interpolated) pose, so it moves with the image
## between physics ticks instead of jumping at each one.
func get_world_outline() -> PackedVector3Array:
	var xf := get_global_transform_interpolated()
	var out := PackedVector3Array()
	for p in outline:
		out.append(xf * p)
	return out


func _rim_from_meshes() -> PackedVector3Array:
	var to_local := global_transform.affine_inverse()
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in get_parent().find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := to_local * mi.global_transform
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * v)
	if pts.size() < 3:
		push_warning("HudSilhouette: no mesh to build an outline from")
		return outline
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var thin := (hi - lo).min_axis_index()
	var u := (thin + 1) % 3
	var w := (thin + 2) % 3
	var hull := _convex_hull(pts, u, w)
	return _drop_flat_corners(hull, u, w)


## Monotone-chain convex hull of the points seen along the thin axis (counter-clockwise).
static func _convex_hull(pts: PackedVector3Array, u: int, w: int) -> PackedVector3Array:
	var sorted := Array(pts)
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a[u] < b[u] or (a[u] == b[u] and a[w] < b[w]))
	var cross := func(o: Vector3, a: Vector3, b: Vector3) -> float:
		return (a[u] - o[u]) * (b[w] - o[w]) - (a[w] - o[w]) * (b[u] - o[u])
	var lower: Array[Vector3] = []
	for p: Vector3 in sorted:
		while lower.size() >= 2 and cross.call(lower[-2], lower[-1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector3] = []
	for i in range(sorted.size() - 1, -1, -1):
		var p: Vector3 = sorted[i]
		while upper.size() >= 2 and cross.call(upper[-2], upper[-1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return PackedVector3Array(lower + upper)


func _drop_flat_corners(hull: PackedVector3Array, u: int, w: int) -> PackedVector3Array:
	var flat := func(p: Vector3) -> Vector2: return Vector2(p[u], p[w])
	var out := hull.duplicate()
	var changed := true
	while changed and out.size() > 4:
		changed = false
		for i in out.size():
			var a: Vector2 = flat.call(out[i - 1])
			var b: Vector2 = flat.call(out[i])
			var c: Vector2 = flat.call(out[(i + 1) % out.size()])
			if absf((b - a).angle_to(c - b)) < deg_to_rad(min_corner_deg):
				out.remove_at(i)
				changed = true
				break
	return out
