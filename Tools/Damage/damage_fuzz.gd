extends SceneTree

## Random damage, checked by rules instead of by eye. Each round repairs the suit, then lands a
## random sequence of real rifle beams (random parts, random directions), severs and joint
## hits, lets it settle and checks:
##   own       nothing shows on a part that is gone (or past a cut through it)
##   thrust    a dead thruster gives no thrust and shows no plume, even commanded to full; the
##             thrusters of a severed part (or one with under 30% of its section) are dead
##   control   a severed part, or one with a joint shot on its way to the torso, can't be moved:
##             its AMBAC joints are out, its weapons can't fire, its equipment can't be used
##   equip     equipment on a severed part is off the suit
##   sane      no NaN, no runaway spin
##   frame     the slowest frames while it took damage (spikes over 12 ms are reported)
## Prints one line per failure and a summary; exit status 1 on any failure.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Damage/damage_fuzz.gd -- [rounds=20] [seed=1] [hits=6]

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const RIFLE := preload("res://Entities/Projectiles/Specs/nu_beam_rifle.tres")
const SPIKE_MS := 12.0

var _suit: RigidBody3D
var _vehicle: VehicleBase
var _model: DamageModel
var _skel: Skeleton3D
var _rng := RandomNumberGenerator.new()
var _fails := {}
var _fail_lines: Array[String] = []
var _frames_ms: Array[float] = []
var _spikes: Array[String] = []
var _round := 0
var _start := Transform3D.IDENTITY
var _step := ""


func _initialize() -> void:
	var rounds := 20
	var hits := 6
	_rng.seed = 1
	for arg in OS.get_cmdline_user_args():
		var k := arg.get_slice("=", 0)
		var v := arg.get_slice("=", 1)
		match k:
			"rounds": rounds = int(v)
			"seed": _rng.seed = int(v)
			"hits": hits = int(v)
	_run.call_deferred(rounds, hits)


func _run(rounds: int, hits: int) -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	for i in 40:
		await physics_frame
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_vehicle = node
			break
	_suit = _vehicle as Node as RigidBody3D
	_model = _vehicle.find_component(DamageModel) as DamageModel
	if _model == null or not _model.is_built():
		print("FUZZ no damage model")
		quit(1)
		return
	_skel = _model._skel
	_start = _suit.global_transform
	(_vehicle.find_component(FireControl) as FireControl).sensors.enabled = false
	# The torn-panel skins are split a little each frame after load.
	for i in 600:
		if _model.parts.all(func(p: DamageModel.Part) -> bool: return p.small_done or p.mesh == null or p.equipment != null):
			break
		await physics_frame
	var timer := func() -> void: _tick()
	process_frame.connect(timer)
	for r in rounds:
		_round = r
		_step = "repair"
		_model.repair()
		_suit.global_transform = _start
		_suit.linear_velocity = Vector3.ZERO
		_suit.angular_velocity = Vector3.ZERO
		for i in 20:
			await physics_frame
		var log: Array[String] = []
		for h in hits:
			await _random_damage(log)
		_step = "settle"
		for i in 60:
			await physics_frame
		_step = "check"
		_check(log)
	process_frame.disconnect(timer)
	_report(rounds)


var _last_us := 0


var _prev_totals := {}
var _prev_nodes := 0


func _tick() -> void:
	var now := Time.get_ticks_usec()
	# What the damage code spent this frame, by function (outermost calls overlap inner ones).
	var spent: Array = []
	for k in DamageModel.timings:
		var tot: int = DamageModel.timings[k][1]
		var d := tot - int(_prev_totals.get(k, 0))
		if d > 300:
			spent.append([k, d / 1000.0])
		_prev_totals[k] = tot
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var dn := nodes - _prev_nodes
	_prev_nodes = nodes
	if _last_us > 0:
		var ms := (now - _last_us) / 1000.0
		_frames_ms.append(ms)
		if ms > SPIKE_MS:
			spent.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
			_spikes.append("round %d %s: %.1f ms  (nodes %+d)  (physics %.1f, process %.1f)  [%s]" % [_round, _step, ms, dn,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					", ".join(spent.slice(0, 6).map(func(e: Array) -> String: return "%s %.1f" % e))])
	_last_us = now


func _random_damage(log: Array[String]) -> void:
	var alive: Array = _model.parts.filter(func(p: DamageModel.Part) -> bool: return not p.severed)
	if alive.is_empty():
		return
	var p: DamageModel.Part = alive[_rng.randi() % alive.size()]
	var roll := _rng.randf()
	if roll < 0.7:
		_step = "beam %s" % p.name
		log.append(_step)
		await _beam(p)
	elif roll < 0.85 and p.equipment == null:
		_step = "joint %s" % p.name
		log.append(_step)
		_model._hit_joints(p, 1.0)
		await _frames(2)
	else:
		_step = "sever %s" % p.name
		log.append(_step)
		_model.sever(p, _rng.randf() < 0.5)
		await _frames(5)


func _beam(p: DamageModel.Part) -> void:
	var target := _part_point(p)
	var dir := Vector3(_rng.randfn(), _rng.randfn() * 0.5, _rng.randfn()).normalized()
	var pm := ProjectileManager.of(current_scene)
	var muzzle := Marker3D.new()
	_suit.add_child(muzzle)
	muzzle.global_position = target - dir * 300.0
	var aim := func() -> Vector3: return (_part_point(p) - muzzle.global_position).normalized()
	var d0: Vector3 = aim.call()
	pm.spawn(RIFLE, muzzle.global_position, _suit.linear_velocity + d0 * RIFLE.speed, d0, [], current_scene)
	var shot: ProjectileManager.Shot = pm._shots[-1] if not pm._shots.is_empty() else null
	if shot != null:
		pm.stream_from(shot, muzzle, func() -> Array:
			var d: Vector3 = aim.call()
			return [muzzle.global_position, _suit.linear_velocity + d * RIFLE.speed, d])
	await _frames(30)
	muzzle.queue_free()


func _part_point(p: DamageModel.Part) -> Vector3:
	if p.equipment != null:
		return p.equipment.global_transform * p.box.get_center()
	return _skel.global_transform * FinalPoses.of(_skel).pose(p.bone) * p.aabb.get_center()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _fail(rule: String, what: String, log: Array[String]) -> void:
	_fails[rule] = int(_fails.get(rule, 0)) + 1
	if _fail_lines.size() < 60:
		_fail_lines.append("FAIL %-7s round %d: %s   [%s]" % [rule, _round, what, ", ".join(log)])


func _check(log: Array[String]) -> void:
	var severed := {}
	for p in _model.parts:
		if p.severed and p.equipment == null:
			severed[p.bone] = p
	# own: anything visible riding a severed part's bone (or past a cut).
	for node in (_vehicle as Node).find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi is Light3D or not vi.is_visible_in_tree() or DamageModel._is_fx(vi):
			continue
		if not (vi.layers & (Layers.VEHICLE_EXT | Layers.WORLD)):
			continue
		var b := _bone_of(vi)
		if b < 0:
			continue
		var part := _model._part_of_bone(b)
		if part == null:
			continue
		if part.severed and part.mesh != vi:
			_fail("own", "%s still shows on severed %s" % [(_vehicle as Node).get_path_to(vi), part.name], log)
		elif part.cut_y != INF and not (vi.get_parent() is Thruster or vi is MeshInstance3D and (vi as MeshInstance3D).skin != null):
			var local := (_skel.global_transform * FinalPoses.of(_skel).pose(part.bone)).affine_inverse() * vi.global_position
			if local.y > part.cut_y + 0.3 and _model._followers.get(part, []).any(func(f: Node) -> bool: return f == vi or f.is_ancestor_of(vi)):
				_fail("own", "%s shows past the cut on %s" % [(_vehicle as Node).get_path_to(vi), part.name], log)
	# thrust
	for c in _model.components:
		if c.kind != DamageModel.Kind.THRUSTER:
			continue
		var t := c.ref as Thruster
		var p := c.part
		if p != null and (p.severed or p.left < DamageModel.THRUSTER_LEFT) and c.alive:
			_fail("thrust", "%s alive on %s (%s)" % [t.name, p.name, "severed" if p.severed else "%d%% left" % roundi(p.left * 100.0)], log)
		# A live thruster may not sit in any part that is gone.
		if c.alive:
			for q in _model.parts:
				if q.severed and q.equipment == null:
					var local := (_skel.global_transform * FinalPoses.of(_skel).pose(q.bone)).affine_inverse() * t.global_position
					if (local - local.clamp(q.aabb.position, q.aabb.end)).length() < 0.05 and _model._bone_is_under(q.bone, _model._bone_of_node(t)):
						_fail("thrust", "%s alive inside severed %s" % [t.name, q.name], log)
		if not c.alive:
			t.set_command(1.0, Vector3.FORWARD, t)
			if t.enabled or t.get_thrust() > 0.0 or t.get_available_thrust() > 0.0:
				_fail("thrust", "dead %s still gives thrust" % t.name, log)
			var plume := t.get_node_or_null(^"Gimbal/Visual/PlumePivot") as Node3D
			if plume != null and plume.visible:
				_fail("thrust", "dead %s shows a plume" % t.name, log)
	# control
	var ambac := _vehicle.find_component(AmbacController) as AmbacController
	for p in _model.parts:
		if p.equipment != null:
			continue
		var should_limp := _chain_broken(p)
		if should_limp != _model.limp.has(p):
			_fail("control", "%s limp=%s, expected %s" % [p.name, _model.limp.has(p), should_limp], log)
		if should_limp and ambac != null:
			for j in ambac.joints:
				if _model._part_of_bone(_skel.find_bone(j.bone_name)) == p and j.priority > 0.0:
					_fail("control", "AMBAC joint on limp %s still driven" % p.name, log)
	var fcs := _vehicle.find_component(FireControl) as FireControl
	for w: MsWeapon in fcs.weapons.values():
		var wp := _model._part_of_bone(_model._equipment_bone(w.equipment) if w.equipment != null else _skel.find_bone(w.mount_bone))
		if wp != null and _chain_broken(wp) and not (w.broken or w.limp):
			_fail("control", "weapon %s on limp %s can still fire" % [w.name, wp.name], log)
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	for eq in loadout.equipment:
		if not eq.equipped:
			continue
		var ep := _model._part_of_bone(_model._equipment_bone(eq))
		if ep == null:
			continue
		if ep.severed:
			_fail("equip", "%s still on the suit, its %s is gone" % [eq.name, ep.name], log)
		elif _chain_broken(ep):
			eq.set_active(true)
			if eq.active or not eq.disabled:
				_fail("control", "%s on limp %s can still be used" % [eq.name, ep.name], log)
	# sane
	var v := _suit.linear_velocity
	var w := _suit.angular_velocity
	if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and is_finite(w.x) and is_finite(w.y) and is_finite(w.z)):
		_fail("sane", "NaN velocity", log)
	elif not _model.reactor_gone and rad_to_deg(w.length()) > 180.0:
		_fail("sane", "spinning %.0f°/s" % rad_to_deg(w.length()), log)


## Severed, or a joint shot somewhere between it and the torso (itself included).
func _chain_broken(p: DamageModel.Part) -> bool:
	var b := p.bone
	while b >= 0:
		var q := _model._part_of_bone(b)
		if q == null:
			return false
		if q.severed or _model._joint_out.has(q.name):
			return true
		b = _skel.get_bone_parent(q.bone)
	return false


func _bone_of(n: Node) -> int:
	var mi := n as MeshInstance3D
	if mi != null and mi.skin != null and mi.get_parent() == _skel:
		return _model._dominant_bone(mi)
	return _model._bone_of_node(n)


func _report(rounds: int) -> void:
	for l in _fail_lines:
		print(l)
	_frames_ms.sort()
	var p99 := _frames_ms[int(_frames_ms.size() * 0.99)] if not _frames_ms.is_empty() else 0.0
	var worst := _frames_ms[-1] if not _frames_ms.is_empty() else 0.0
	_spikes.sort_custom(func(a: String, b: String) -> bool: return a.get_slice(": ", 1).to_float() > b.get_slice(": ", 1).to_float())
	print("SPIKES (frame ms [damage code in that frame, ms]):")
	for s in _spikes.slice(0, 10):
		print("SPIKE ", s)
	var rows: Array = []
	for k in _model.timings:
		var e: Array = _model.timings[k]
		rows.append([k, e[0], e[1] / 1000.0, e[2] / 1000.0])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[3] > b[3])
	for r in rows.slice(0, 24):
		print("TIME %-18s calls %5d  total %8.1f ms  worst %6.2f ms" % r)
	var total := 0
	for k in _fails:
		total += int(_fails[k])
	print("FUZZ %d rounds: %s | frames p99 %.1f ms, worst %.1f ms, %d over %.0f ms" % [rounds,
			"all rules held" if total == 0 else ", ".join(_fails.keys().map(func(k: String) -> String: return "%s %d" % [k, _fails[k]])),
			p99, worst, _spikes.size(), SPIKE_MS])
	quit(1 if total > 0 else 0)
