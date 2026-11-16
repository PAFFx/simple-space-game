extends SceneTree

## Solid volume and centre of every skinned part of a suit, from its mesh: the surface is
## rasterised into a voxel grid, the outside flood-filled from the grid's border, and what
## the fill can't reach counts as inside (open seams narrower than a voxel don't leak).
## The mass tables in the scene builders are sized from this.
##
##   godot-double --headless --path . -s Tools/Godot/measure_part_volumes.gd -- [scene] [voxel m]

var _scene := "res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn"
var _voxel := 0.15
var _frames := 0
var _suit: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_scene = args[0]
	if args.size() > 1:
		_voxel = float(args[1])
	process_frame.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames == 1:
		_suit = load(_scene).instantiate()
		root.add_child(_suit)
		return
	if _frames < 4:
		return
	var sk := _suit.get_node("Model/Armature/Skeleton3D") as Skeleton3D
	var to_body := _suit.global_transform.affine_inverse() * sk.global_transform
	var total := 0.0
	for c in sk.get_children():
		if c is MeshInstance3D:
			var r := _measure(c as MeshInstance3D, to_body * (c as MeshInstance3D).transform)
			total += r[0]
			print("PART %-14s vol %6.2f m3  centre %s" % [c.name, r[0], r[1]])
	print("TOTAL vol %.2f m3" % total)
	quit()


## [volume m³, centre (body frame)]
func _measure(mi: MeshInstance3D, xf: Transform3D) -> Array:
	var tris := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			for p in v:
				tris.append(xf * p)
		else:
			for i in idx:
				tris.append(xf * v[i])
	var box := AABB(tris[0], Vector3.ZERO)
	for p in tris:
		box = box.expand(p)
	box = box.grow(_voxel * 2.0)
	var n := Vector3i((box.size / _voxel).ceil())
	var grid := PackedByteArray()
	grid.resize(n.x * n.y * n.z)
	# 1 = surface: sample each triangle finer than a voxel.
	for t in range(0, tris.size() - 2, 3):
		var a := tris[t]
		var b := tris[t + 1]
		var c := tris[t + 2]
		var steps := int(ceil(maxf((b - a).length(), (c - a).length()) / (_voxel * 0.5))) + 1
		for i in steps + 1:
			for j in steps + 1 - i:
				var p := a + (b - a) * (float(i) / steps) + (c - a) * (float(j) / steps)
				var q := Vector3i(((p - box.position) / _voxel).floor())
				grid[(q.z * n.y + q.y) * n.x + q.x] = 1
	# Inside: surface on both sides along at least 2 of the 3 axes. A flood fill from the
	# border leaked through the open cockpit tunnel and seams; this doesn't.
	var count := 0
	var sum := Vector3.ZERO
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var k := (z * n.y + y) * n.x + x
				if grid[k] == 1 or _enclosed(grid, n, x, y, z) >= 2:
					count += 1
					sum += Vector3(x + 0.5, y + 0.5, z + 0.5)
	var vol := count * _voxel * _voxel * _voxel
	var centre := box.position + sum / maxf(count, 1) * _voxel
	return [vol, centre]


## Axes along which voxel (x, y, z) has surface on both sides.
func _enclosed(grid: PackedByteArray, n: Vector3i, x: int, y: int, z: int) -> int:
	var axes := 0
	for axis in 3:
		var lo := false
		var hi := false
		var size: int = n[axis]
		var at: int = [x, y, z][axis]
		for i in size:
			var q := Vector3i(x, y, z)
			q[axis] = i
			if grid[(q.z * n.y + q.y) * n.x + q.x] == 1:
				if i < at:
					lo = true
				elif i > at:
					hi = true
		if lo and hi:
			axes += 1
	return axes
