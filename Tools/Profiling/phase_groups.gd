extends SceneTree

# Frame cost by subtree. Windowed, vsync off, the suit coasting at 300 m/s. For each subtree:
# a baseline, then the subtree disabled, split into physics (per step), process and draw
# (per frame), so costs aren't skewed by the physics steps per frame changing with fps.
# Run: godot-double --path . -s Tools/Profiling/phase_groups.gd   (prints a table, ~4 min)
const SAMPLE := 300
var _n := 0
var _suit: RigidBody3D
var _groups: Array = []
var _gi := 0
var _base := true
var _phase_start := 0
var _acc := {}
var _base_acc := {}
var _t_process := 0
var _t_pre := 0
var _phys_start := -1
var _results: Array = []
var _total0 := {}


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	process_frame.connect(_on_process)
	physics_frame.connect(_on_physics)
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec(); _add("process", _t_pre - _t_process))
	RenderingServer.frame_post_draw.connect(_on_post)


func _add(k: String, v: float) -> void:
	_acc[k] = _acc.get(k, 0.0) + v


func _on_physics() -> void:
	if _suit:
		_suit.linear_velocity = -_suit.global_basis.z * 300.0
	if _phys_start < 0:
		_phys_start = Time.get_ticks_usec()
	_add("steps", 1)


func _on_post() -> void:
	_add("draw", Time.get_ticks_usec() - _t_pre)
	_add("frames", 1)


func _on_process() -> void:
	var now := Time.get_ticks_usec()
	if _phys_start >= 0:
		_add("physics", now - _phys_start)
	_phys_start = -1
	_t_process = now
	_n += 1
	if _n == 1:
		change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
		return
	if _n < 300:
		return
	if _n == 300:
		_suit = current_scene.find_child("MobileSuitRX93", false, false)
		_collect()
		_start()
		return
	if _n - _phase_start < SAMPLE:
		return
	var m := _means()
	if _base:
		_base_acc = m
		if _gi == 0:
			_total0 = m
		_toggle(_groups[_gi], false)
		_base = false
	else:
		_toggle(_groups[_gi], true)
		_results.append([_groups[_gi][0], _base_acc, m])
		_gi += 1
		_base = true
		if _gi >= _groups.size():
			_report()
			return
	_start()


func _means() -> Dictionary:
	var f: float = _acc.get("frames", 1.0)
	var s: float = maxf(_acc.get("steps", 1.0), 1.0)
	return {"phys": _acc.get("physics", 0.0) / 1000.0 / s, "proc": _acc.get("process", 0.0) / 1000.0 / f,
			"draw": _acc.get("draw", 0.0) / 1000.0 / f, "spf": s / f}


func _start() -> void:
	_phase_start = _n
	_acc.clear()


func _collect() -> void:
	var scene := current_scene
	_groups.append(["physics server (Jolt step)", null])
	for c in scene.get_children():
		if c != _suit:
			_groups.append(["stage/" + c.name, c])
	var cockpit: Node = null
	for c in _suit.get_children():
		if c is CollisionShape3D:
			continue
		if c.name == "CockpitMount":
			cockpit = _find_cockpit(c)
			continue
		_groups.append(["suit/" + c.name, c])
	for c in cockpit.get_children():
		if c.name == "PanoramicHud":
			for w in c.get_node("HudViewport").get_children():
				_groups.append(["hud/" + w.name, w])
		_groups.append(["cockpit/" + c.name, c])


func _find_cockpit(n: Node) -> Node:
	for c in n.get_children():
		if c is CockpitBase:
			return c
		var r := _find_cockpit(c)
		if r:
			return r
	return null


func _toggle(g: Array, on: bool) -> void:
	if g[1] == null:
		PhysicsServer3D.set_active(on)
		return
	var node: Node = g[1]
	node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		node.visible = on
	_mods(node, on)


func _mods(n: Node, on: bool) -> void:
	if n is SkeletonModifier3D or n is AnimationMixer:
		n.active = on
	elif n is SubViewport:
		n.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for c in n.get_children(true):
		_mods(c, on)


func _report() -> void:
	var t := _total0
	print("BASE physics %.2f ms/step (%.2f steps/frame)  process %.2f ms/frame  draw %.2f ms/frame"
			% [t.phys, t.spf, t.proc, t.draw])
	print("%-34s %9s %9s %9s" % ["disabled", "phys/step", "proc/frm", "draw/frm"])
	for r in _results:
		var b: Dictionary = r[1]
		var m: Dictionary = r[2]
		print("%-34s %9.2f %9.2f %9.2f" % [r[0], b.phys - m.phys, b.proc - m.proc, b.draw - m.draw])
	quit()
