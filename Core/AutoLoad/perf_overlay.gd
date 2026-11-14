extends CanvasLayer

## Performance overlay. F3 cycles: off -> FPS only -> full stats with a frame-time graph.

const TOGGLE := &"debug_toggle_perf_overlay"
const TEXT_INTERVAL := 0.25
const GRAPH_SAMPLES := 180
## Graph ceiling, ms (about 30 fps).
const GRAPH_MAX_MS := 33.3

enum Mode { OFF, FPS, FULL }

var mode := Mode.OFF

var _panel: PanelContainer
var _label: Label
var _graph: Control
var _frame_ms := PackedFloat32Array()
var _text_timer := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action(TOGGLE):
		InputMap.add_action(TOGGLE)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event(TOGGLE, ev)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_frame_ms.resize(GRAPH_SAMPLES)
	_build_ui()
	_apply_mode()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE):
		mode = ((mode + 1) % Mode.size()) as Mode
		_apply_mode()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if mode == Mode.OFF:
		return
	_frame_ms.remove_at(0)
	_frame_ms.append(delta * 1000.0)
	if mode == Mode.FULL:
		_graph.queue_redraw()
	_text_timer -= delta
	if _text_timer <= 0.0:
		_text_timer = TEXT_INTERVAL
		_label.text = _fps_text() if mode == Mode.FPS else _full_text()


func _fps_text() -> String:
	return "%d FPS" % Engine.get_frames_per_second()


func _full_text() -> String:
	var vp_rid := get_viewport().get_viewport_rid()
	var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) \
			+ RenderingServer.get_frame_setup_time_cpu()
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	var worst := 0.0
	for ms in _frame_ms:
		worst = maxf(worst, ms)
	var lines := PackedStringArray([
		"%d FPS   %.2f ms   worst %.1f ms" % [Engine.get_frames_per_second(), _frame_ms[-1], worst],
		# Engine monitors: worst frame of the last second. "main" covers scripts plus
		# render submission and waiting on the GPU.
		"main %.2f ms   physics %.2f ms (worst/s)" % [
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"render cpu %.2f ms   gpu %.2f ms (main view)" % [cpu_ms, gpu_ms],
		"draws %d   prims %s   objects %d" % [
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				_si(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)],
		"vram %s   ram %s   nodes %d" % [
				_bytes(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
				_bytes(Performance.get_monitor(Performance.MEMORY_STATIC)),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT)],
	])
	var cam := get_viewport().get_camera_3d()
	if cam:
		lines.append("camera %s from origin" % _metres(cam.global_position.length()))
	return "\n".join(lines)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(8, 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])
	_label.add_theme_font_override(&"font", font)
	_label.add_theme_font_size_override(&"font_size", 13)
	_label.add_theme_constant_override(&"outline_size", 3)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	box.add_child(_label)

	_graph = Control.new()
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.custom_minimum_size = Vector2(GRAPH_SAMPLES * 2, 48)
	_graph.draw.connect(_draw_graph)
	box.add_child(_graph)


func _apply_mode() -> void:
	_panel.visible = mode != Mode.OFF
	_graph.visible = mode == Mode.FULL
	_text_timer = 0.0
	# Shrink back to the content when switching to the smaller mode.
	_panel.reset_size()


func _draw_graph() -> void:
	var size := _graph.size
	_graph.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.05))
	for target_ms: float in [1000.0 / 60.0, 1000.0 / 120.0]:
		var y := size.y * (1.0 - target_ms / GRAPH_MAX_MS)
		_graph.draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.25))
	var bar_w := size.x / GRAPH_SAMPLES
	for i in GRAPH_SAMPLES:
		var ms := _frame_ms[i]
		if ms <= 0.0:
			continue
		var h := minf(ms / GRAPH_MAX_MS, 1.0) * size.y
		var color := Color(0.4, 0.9, 0.5) if ms <= 1000.0 / 60.0 + 0.5 \
				else Color(1.0, 0.8, 0.3) if ms <= 1000.0 / 30.0 else Color(1.0, 0.35, 0.3)
		_graph.draw_rect(Rect2(i * bar_w, size.y - h, bar_w, h), color)


static func _si(n: float) -> String:
	if n >= 1.0e6:
		return "%.2fM" % (n / 1.0e6)
	if n >= 1.0e3:
		return "%.1fk" % (n / 1.0e3)
	return "%d" % n


static func _bytes(n: float) -> String:
	return "%.0f MB" % (n / 1048576.0)


static func _metres(m: float) -> String:
	return "%.2f km" % (m / 1000.0) if m >= 1000.0 else "%.1f m" % m
