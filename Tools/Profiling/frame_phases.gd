extends SceneTree

# Where the main thread's frame goes. Windowed, vsync off, the suit coasting at 300 m/s.
# physics = physics_frame → process_frame (ticks: scripts + Jolt), process = process_frame →
# frame_pre_draw (_process scripts, canvas recording), draw = pre → post draw (render
# submission and GPU waits), rest = post draw → next frame (swap, input, idle).
# Run: godot-double --path . -s Tools/Profiling/frame_phases.gd   (~10 s)
# GPU passes: add --gpu-profile to the same command.
var _n := 0
var _suit: RigidBody3D
var _t := {}
var _acc := {"physics": 0.0, "process": 0.0, "draw": 0.0, "rest": 0.0}
var _frames := 0
var _steps := 0
var _last_post := 0
var _phys_start := -1
var _measuring := false
var _vps: Array = []
var _vp_acc := {}


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	process_frame.connect(_on_process)
	physics_frame.connect(_on_physics)
	RenderingServer.frame_pre_draw.connect(_on_pre)
	RenderingServer.frame_post_draw.connect(_on_post)


func _now() -> int:
	return Time.get_ticks_usec()


func _on_physics() -> void:
	if _suit:
		_suit.linear_velocity = -_suit.global_basis.z * 300.0
	if _phys_start < 0:
		_phys_start = _now()
	if _measuring:
		_steps += 1


func _on_process() -> void:
	var now := _now()
	if _measuring and _last_post > 0:
		var start := _phys_start if _phys_start >= 0 else now
		_acc.rest += start - _last_post
		_acc.physics += now - start
	_t.process = now
	_phys_start = -1
	_n += 1
	if _n == 1:
		change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	elif _n == 150:
		_suit = current_scene.find_child("MobileSuitRX93", false, false)
		_vps = [root]
		_find(root)
		for v in _vps:
			RenderingServer.viewport_set_measure_render_time(v.get_viewport_rid(), true)
	elif _n == 400:
		_measuring = true
	elif _n == 1600:
		_report()
		quit()


func _on_pre() -> void:
	_t.pre = _now()
	if _measuring and _t.has("process"):
		_acc.process += _t.pre - _t.process


func _on_post() -> void:
	var now := _now()
	if _measuring:
		_acc.draw += now - _t.pre
		_frames += 1
		for v in _vps:
			var rid: RID = v.get_viewport_rid()
			var a: Vector2 = _vp_acc.get(v, Vector2.ZERO)
			_vp_acc[v] = a + Vector2(RenderingServer.viewport_get_measured_render_time_cpu(rid),
					RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_last_post = now


func _report() -> void:
	var total := 0.0
	for k in _acc:
		total += _acc[k]
	var f := float(_frames)
	print("frames %d, physics steps/frame %.2f, frame %.2f ms (%.0f fps)" % [_frames, _steps / f, total / 1000.0 / f, 1000000.0 * f / total])
	for k in _acc:
		print("  %-8s %.2f ms  %4.1f%%" % [k, _acc[k] / 1000.0 / f, 100.0 * _acc[k] / total])
	print("  per physics step: %.2f ms" % (_acc.physics / 1000.0 / maxf(_steps, 1)))
	for v in _vps:
		var a: Vector2 = _vp_acc[v] / f
		print("  vp %-28s cpu %.2f gpu %.2f" % [String(v.name), a.x, a.y])
	print("  frame setup cpu %.2f" % RenderingServer.get_frame_setup_time_cpu())


func _find(n: Node) -> void:
	for c in n.get_children(true):
		if c is SubViewport:
			_vps.append(c)
		_find(c)
