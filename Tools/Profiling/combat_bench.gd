extends SceneTree

# Frame cost in a combat scene: the RX-93 in DGFT, master arm on, rifle drawn, flying a
# gentle scripted manoeuvre, N jinking drones in view and one of them locked. Windowed,
# vsync off; the suit's input is scripted, so the real sticks don't count.
#
#   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating
#   godot-double --path . --resolution 1280x720 -s Tools/Profiling/combat_bench.gd -- \
#       [drones=6] [lock=1] [seconds=8] [silence=<path>] [viewports=1] [damage=1]
#
# silence: a node path under the suit (e.g. FireControl, CockpitMount, or a HUD widget as
# CockpitMount/<cockpit>/PanoramicHud/HudViewport/Contacts), Stage/<child> or drones; that subtree's
# process and physics processing are turned off for the measurement, so its cost is the
# difference to a run without it. Prints one BENCH line; viewports=1 adds each viewport's
# measured render time (CPU submission and GPU), the busiest first. damage=1: the suit is badly
# holed first (24 holes over 12 parts, the head's eyes out, two holes in the screen), so the
# damage shaders and the body-camera screen path are in the frame.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.translation = out.translation
		cmd.rotation = out.rotation
		return out

var _drones := 6
var _lock := true
var _seconds := 8.0
var _silence := ""
var _viewports := false
var _damage := false
var _nohulls := false
var _nodamage := false
var _vps: Array[Viewport] = []
var _vp_time := {}
var _suit: RigidBody3D
var _input := ScriptedInput.new()
var _measuring := false
var _t := {}
var _acc := {"frame": 0.0, "physics": 0.0, "process": 0.0, "draw": 0.0, "steps": 0, "frames": 0}
var _last_post := 0
var _phys_start := -1
var _time := 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"drones": _drones = int(value)
			"lock": _lock = value != "0"
			"seconds": _seconds = float(value)
			"silence": _silence = value
			"viewports": _viewports = value != "0"
			"damage": _damage = value != "0"
			"nohulls": _nohulls = value != "0"
			"nodamage": _nodamage = value != "0"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if _nodamage and node is MobileSuitBody:
			(node as MobileSuitBody).damage_model = false
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _frames(10)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
		elif node is MouseLookController:
			node.set_process(false)
			node.set_process_input(false)
	var vehicle := _suit as Node as VehicleBase
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	var old := fc.input_source
	fc.add_child(_input)
	fc.input_source = _input
	if old != null and old != _input:
		old.set_process(false)
		old.set_physics_process(false)
	var fcs := vehicle.find_component(FireControl) as FireControl
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	_input.cmd.master_arm = 1
	await _frames(60)
	fcs.draw_now()
	var basis := _suit.global_basis.orthonormalized()
	var first: TargetDrone
	for i in _drones:
		var drone := TargetDrone.new()
		drone.behaviour = TargetDrone.Behaviour.JINK
		drone.hit_points = 1e12
		drone.leash = 150.0
		stage.add_child(drone)
		var az := -30.0 + 60.0 * (float(i) / maxf(_drones - 1, 1))
		drone.global_position = fcs.get_view_origin() + basis * SpatialMath.angles_to_direction(
				Vector2(az, 4.0 + 6.0 * sin(i))) * (600.0 + 150.0 * i)
		if first == null:
			first = drone
	await _frames(30)
	if _lock and first != null:
		fcs.lock(first)
	if _silence != "":
		var targets: Array[Node] = []
		if _silence == "drones":
			for n in stage.get_children():
				if n is TargetDrone:
					targets.append(n)
		else:
			var target := _suit.get_node_or_null(_silence) if not _silence.begins_with("Stage/") \
					else stage.get_node_or_null(_silence.substr(6))
			if target == null:
				print("BENCH no node at %s" % _silence)
				quit()
				return
			targets.append(target)
		var all: Array[Node] = []
		for target in targets:
			all.append(target)
			all.append_array(target.find_children("*", "", true, false))
		for n in all:
			n.set_process(false)
			n.set_physics_process(false)
			n.set_process_internal(false)
			n.set_physics_process_internal(false)
	if _damage:
		_apply_damage()
	if _nohulls:
		for n in _suit.find_children("DamageHull_*", "BoneAttachment3D", true, false):
			n.queue_free()
	await _frames(120)
	if _viewports:
		_vps.append(root)
		for n in root.find_children("*", "SubViewport", true, false):
			_vps.append(n)
		for vp in _vps:
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	process_frame.connect(_on_process)
	physics_frame.connect(_on_physics)
	RenderingServer.frame_pre_draw.connect(func() -> void: _t.pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(_on_post)
	_measuring = true
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < _seconds * 1000.0:
		await process_frame
	_measuring = false
	var f := float(_acc.frames)
	var s := maxf(float(_acc.steps), 1.0)
	print("BENCH %-40s frame %.2f ms (%.0f fps)  physics %.2f ms/step (%.2f steps/frame)  process %.2f  draw %.2f" % [
			_silence if _silence != "" else "baseline", _acc.frame / 1000.0 / f, 1000000.0 * f / _acc.frame,
			_acc.physics / 1000.0 / s, s / f, _acc.process / 1000.0 / f, _acc.draw / 1000.0 / f])
	if _viewports:
		var rows := []
		for vp in _vps:
			var v: Vector2 = _vp_time.get(vp, Vector2.ZERO) / f
			rows.append([vp, v])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1].x + a[1].y > b[1].x + b[1].y)
		for r in rows:
			var vp: Viewport = r[0]
			var size := (vp as SubViewport).size if vp is SubViewport else Vector2i(vp.get_visible_rect().size)
			print("VIEWPORT %-34s %4dx%-4d cpu %.3f ms  gpu %.3f ms" % [String(vp.name), size.x, size.y, r[1].x, r[1].y])
	quit()


func _on_physics() -> void:
	_time += 1.0 / Engine.physics_ticks_per_second
	# A gentle weave, so the attitude, flight path and contacts keep changing.
	_input.cmd.translation = Vector3(0.3 * sin(_time * 0.7), 0.0, -0.4)
	_input.cmd.rotation = Vector3(0.15 * sin(_time * 0.5), 0.2 * sin(_time * 0.3), 0.0)
	if _phys_start < 0:
		_phys_start = Time.get_ticks_usec()
	if _measuring:
		_acc.steps += 1


func _on_process() -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _phys_start >= 0:
		_acc.physics += now - _phys_start
	_phys_start = -1
	_t.process = now


func _on_post() -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _t.has("process") and _t.has("pre"):
		_acc.process += _t.pre - _t.process
		_acc.draw += now - _t.pre
		if _last_post > 0:
			_acc.frame += now - _last_post
		_acc.frames += 1
		for vp in _vps:
			var rid := vp.get_viewport_rid()
			_vp_time[vp] = _vp_time.get(vp, Vector2.ZERO) + Vector2(
					RenderingServer.viewport_get_measured_render_time_cpu(rid),
					RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_last_post = now


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _apply_damage() -> void:
	var model := (_suit as Node as VehicleBase).find_component(DamageModel) as DamageModel
	if model == null or not model.is_built():
		return
	var skel := (_suit as Node as VehicleBase).find_component(LimbReaction).skeleton as Skeleton3D
	var n := 0
	for p in model.parts:
		if p.mesh == null or n >= 12:
			continue
		n += 1
		var frame := skel.global_transform * skel.get_bone_global_pose(p.bone)
		for k in 2:
			var dir := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
			var c := frame * p.aabb.get_center()
			var h := model.holes.add_hole(p.mesh, skel, p.bone, c - dir * p.width, dir, 0.6, p.width * 2.0)
			h.s_drill = h.s_out
	for c in model.components:
		if c.kind == DamageModel.Kind.EYES:
			model._kill_component(c)
	var screen := (_suit as Node as VehicleBase).get_cockpit().get_panoramic_screen()
	screen.add_screen_hole(-_suit.global_basis.z + _suit.global_basis.x, deg_to_rad(16.0))
	screen.add_screen_hole(_suit.global_basis.z - _suit.global_basis.x, deg_to_rad(16.0))
