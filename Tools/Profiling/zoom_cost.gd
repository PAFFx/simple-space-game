extends SceneTree

# What the zoom window costs. Windowed, vsync off, main scene: a drone ahead is locked and
# the frame measured with the zoom closed, then open at ×16. Prints the frame's phases
# (process = _process scripts, draw = render submission, rest = swap / GPU wait) and each
# 3D viewport's render time.
# Run: godot-double --path . -s Tools/Profiling/zoom_cost.gd   (~30 s)

const CASES := ["closed", "open", "open, WeaponsWidget off", "open, PanoramicScreen off", "open, CockpitDisplays off"]
const FRAMES := 400

var _fcs: FireControl
var _head: SensorHead
var _n := 0
var _case := -1
var _count := 0
var _acc := {}
var _last := 0
var _proc := 0
var _pre := 0
var _vps: Array[SubViewport] = []
var _results: Array = []


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	process_frame.connect(_on_process)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(_on_post)


func _on_process() -> void:
	_n += 1
	_proc = Time.get_ticks_usec()
	if _n == 1:
		change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	elif _n == 120:
		var suit := current_scene.find_child("MobileSuitRX93", false, false) as Node3D
		_fcs = (suit as VehicleBase).find_component(FireControl) as FireControl
		_head = (suit as VehicleBase).get_sensor_head()
		var drone := TargetDrone.new()
		drone.quarry = suit
		current_scene.add_child(drone)
		drone.global_position = _fcs.get_view_origin() - suit.global_basis.z * 1500.0
		_fcs.lock(drone)
		for v in current_scene.find_children("*", "SubViewport", true, false):
			if not (v as SubViewport).disable_3d:
				_vps.append(v)
				RenderingServer.viewport_set_measure_render_time((v as SubViewport).get_viewport_rid(), true)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	elif _n == 300:
		_next_case()


func _on_post() -> void:
	var now := Time.get_ticks_usec()
	if _case >= 0 and _last > 0:
		_count += 1
		if _count > 60:
			_add("frame", now - _last)
			_add("process", _pre - _proc)
			_add("draw", now - _pre)
			_add("gpu root", RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) * 1000.0)
			for v in _vps:
				_add("gpu " + String(v.name), RenderingServer.viewport_get_measured_render_time_gpu(v.get_viewport_rid()) * 1000.0)
				_add("cpu " + String(v.name), RenderingServer.viewport_get_measured_render_time_cpu(v.get_viewport_rid()) * 1000.0)
		if _count == FRAMES + 60:
			_results.append([CASES[_case], _acc.duplicate()])
			_next_case()
	_last = now


func _add(key: String, usec: float) -> void:
	_acc[key] = _acc.get(key, 0.0) + usec / 1000.0 / FRAMES


func _next_case() -> void:
	_case += 1
	_count = 0
	_acc = {}
	if _case >= CASES.size():
		for r in _results:
			print("== %s" % r[0])
			for k: String in r[1]:
				if r[1][k] > 0.02 and not k.begins_with("cpu ") and not k.begins_with("gpu "):
					print("  %-28s %.2f ms" % [k, r[1][k]])
		quit()
		return
	_fcs.zoom_level = 0 if _case == 0 else 4
	for cls in ["WeaponsWidget", "PanoramicScreen", "CockpitDisplays"]:
		for node in current_scene.find_children("*", cls, true, false):
			node.process_mode = Node.PROCESS_MODE_INHERIT
	var off := {2: "WeaponsWidget", 3: "PanoramicScreen", 4: "CockpitDisplays"}
	if off.has(_case):
		for node in current_scene.find_children("*", off[_case], true, false):
			node.process_mode = Node.PROCESS_MODE_DISABLED
