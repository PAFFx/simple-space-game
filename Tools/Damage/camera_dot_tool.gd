extends SceneTree

## Places the suit's dot cameras (CameraMarker without painted lens) by hand, from pictures.
##
## 1. Views:  renders one close-up per camera with a pixel grid and the thrusters marked red:
##      godot-double --path . --resolution 1280x720 --fixed-fps 60 -s Tools/Damage/camera_dot_tool.gd -- <out_dir>
## 2. Place:  a JSON file {"ShoulderR": [x, y], ...} of pixels picked on those views; a ray from
##    the view through each pixel finds the armour there. Renders the result and prints the
##    markers' new bone-local transforms (JSON line "PLACED_JSON"):
##      ... -s Tools/Damage/camera_dot_tool.gd -- <out_dir> <picks.json>

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const PROBE_LAYER := 1 << 19

# marker, part to frame, view offset from it (body frame), camera facing (body frame)
const VIEWS := {
	"Backpack": [&"backpack", Vector3(3.0, 3.0, 11.0), Vector3(0, 0.35, 1)],
	"ShoulderR": [&"shoulder.R", Vector3(6.0, 1.5, -6.0), Vector3(0.71, 0, -0.71)],
	"ShoulderL": [&"shoulder.L", Vector3(-6.0, 1.5, -6.0), Vector3(-0.71, 0, -0.71)],
	"WaistFront": [&"pelvis", Vector3(2.0, -1.0, -10.0), Vector3(0, -0.5, -1)],
	"WaistRear": [&"pelvis", Vector3(-1.0, -10.0, 5.0), Vector3(0, -0.5, 1)],
	"SkirtRearR": [&"skirt_rear.R", Vector3(6.0, -2.0, 8.0), Vector3(0.5, -0.5, 1)],
	"SkirtRearL": [&"skirt_rear.L", Vector3(-6.0, -2.0, 8.0), Vector3(-0.5, -0.5, 1)],
	"FootR": [&"foot.R", Vector3(4.0, -2.0, -6.0), Vector3(0.3, -1, 0)],
	"FootL": [&"foot.L", Vector3(-4.0, -2.0, -6.0), Vector3(-0.3, -1, 0)],
	"ForearmR": [&"forearm.R", Vector3(6.0, 0.5, -4.0), Vector3(1, -0.3, 0)],
	"ForearmL": [&"forearm.L", Vector3(3.5, -2.0, -7.0), Vector3(0.3, -1, -0.3)],
}

var _out := "user://camera_dots"
var _suit: Node3D
var _model: DamageModel
var _skel: Skeleton3D
var _cam: Camera3D
var _grid: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var picks := {}
	if args.size() > 1:
		picks = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	_run.call_deferred(picks)


func _run(picks: Dictionary) -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	# Physics frames (fixed 60 Hz), so every run holds the same pose.
	for i in 30:
		await physics_frame
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node
			break
	_model = (_suit as VehicleBase).find_component(DamageModel) as DamageModel
	_skel = ((_suit as VehicleBase).find_component(LimbReaction) as LimbReaction).skeleton
	((_suit as VehicleBase).find_component(FireControl) as FireControl).sensors.enabled = false
	_suit.process_mode = Node.PROCESS_MODE_DISABLED   # hold the pose
	_cam = Camera3D.new()
	_cam.cull_mask = Layers.MASK_THIRD_PERSION
	_cam.fov = 40.0
	_cam.near = 0.1
	_cam.far = 20000.0
	current_scene.add_child(_cam)
	_cam.make_current()
	_mark_thrusters()
	var markers := {}
	for node in _suit.find_children("*", "Marker3D", true, false):
		if node is CameraMarker:
			markers[node.name] = node
			# The dots only show in the editor: draw them here, bigger, to see them.
			var m := node as CameraMarker
			if not m.is_painted():
				m._make_lens()
				m._lens.scale = Vector3.ONE * 2.5
	if picks.is_empty():
		_add_grid()
		for name in VIEWS:
			_view(name)
			await _frames(4)
			_save("%s_view" % name)
		quit()
		return
	await _build_probe()
	var placed := {}
	var basis := _suit.global_basis
	for name in picks:
		var m: CameraMarker = markers.get(StringName(name))
		if m == null or not VIEWS.has(name):
			print("SKIP ", name)
			continue
		_view(name)
		await _frames(2)
		var px: Array = picks[name]
		var from := _cam.project_ray_origin(Vector2(px[0], px[1]))
		var dir := _cam.project_ray_normal(Vector2(px[0], px[1]))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, PROBE_LAYER)
		q.hit_back_faces = false
		var hit := _cam.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			print("MISS ", name)
			continue
		var part_name: StringName = (hit.collider as Node).get_meta(&"part", &"")
		if part_name == &"":
			print("ON EQUIPMENT ", name)
			continue
		var part := _model.find_part(part_name)
		var face: Vector3 = (basis * (VIEWS[name][2] as Vector3)).normalized()
		var at: Vector3 = hit.position + (hit.normal as Vector3) * 0.03
		var world := Transform3D(Basis.looking_at(face, Vector3.UP if absf(face.y) < 0.95 else Vector3.BACK), at)
		var frame := _skel.global_transform * _skel.get_bone_global_pose(part.bone)
		var local := frame.affine_inverse() * world
		m.global_transform = world
		var near := INF
		for t in _suit.find_children("*", "", true, false):
			if t is Thruster:
				near = minf(near, (t as Node3D).global_position.distance_to(at))
		print("PLACED ", name, " on ", part_name, ", nearest thruster ", snappedf(near, 0.01), " m")
		var b := local.basis
		placed[name] = [String(part_name), [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
				local.origin.x, local.origin.y, local.origin.z]]
	for name in placed:
		_view(name)
		await _frames(3)
		_save("%s_placed" % name)
	print("PLACED_JSON ", JSON.stringify(placed))
	quit()


func _view(name: String) -> void:
	var v: Array = VIEWS[name]
	var p := _model.find_part(v[0])
	var at := _skel.global_transform * _skel.get_bone_global_pose(p.bone) * p.aabb.get_center()
	_cam.global_position = at + _suit.global_basis * (v[1] as Vector3)
	_cam.look_at(at, _suit.global_basis.y)


## Each part's skin (posed) and the equipment as ray targets; a part's body knows its name.
func _build_probe() -> void:
	for p in _model.parts:
		if p.mesh == null or p.equipment != null:
			continue
		var faces := PackedVector3Array()
		var mi := p.mesh
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = DamageModel.skin_surface(mi, _skel, arrays)[0]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for i in (idx if not idx.is_empty() else range(verts.size())):
				faces.append(mi.global_transform * verts[i])
		_probe_body(faces).set_meta(&"part", p.name)
	var eq_faces := PackedVector3Array()
	for node in _suit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin != null or mi.mesh == null or not mi.is_visible_in_tree() or mi.get_parent() is CameraMarker:
			continue
		var faces := mi.mesh.get_faces()
		for i in faces.size():
			eq_faces.append(mi.global_transform * faces[i])
	_probe_body(eq_faces)
	await physics_frame
	await physics_frame


func _probe_body(faces: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PROBE_LAYER
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	current_scene.add_child(body)
	return body


func _mark_thrusters() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.1, 0.1)
	mat.no_depth_test = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	sphere.material = mat
	for t in _suit.find_children("*", "", true, false):
		if t is Thruster:
			var mi := MeshInstance3D.new()
			mi.mesh = sphere
			current_scene.add_child(mi)
			mi.global_position = (t as Node3D).global_position


func _add_grid() -> void:
	var layer := CanvasLayer.new()
	_grid = Control.new()
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.draw.connect(func() -> void:
		var size := _grid.get_viewport_rect().size
		var font := ThemeDB.fallback_font
		for x in range(0, int(size.x), 80):
			_grid.draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 0, 0.25), 1.0)
			_grid.draw_string(font, Vector2(x + 2, 12), str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0, 0.8))
		for y in range(0, int(size.y), 80):
			_grid.draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 0, 0.25), 1.0)
			_grid.draw_string(font, Vector2(2, y + 12), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 0, 0.8)))
	layer.add_child(_grid)
	current_scene.add_child(layer)


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
