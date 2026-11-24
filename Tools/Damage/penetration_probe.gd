extends SceneTree

## Beams against the RX-93's damage model (Docs/Damage/physics.md §1): fires the rifle's
## beam at chosen parts from 300 m and reports what it went through, how long it took,
## what it hit and what it left. Also the shield's I-field, the drone, vulcan impulse,
## severing and repair.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Damage/penetration_probe.gd -- \
##       [cases=head,chest,waist,forearm,thigh,shin,backpack,shield,bareshield,drone,vulcan,repair]

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const RIFLE := preload("res://Entities/Projectiles/Specs/nu_beam_rifle.tres")
const VULCAN := preload("res://Entities/Projectiles/Specs/vulcan_60mm.tres")

var _suit: RigidBody3D
var _model: DamageModel
var _fc: FlightComputer
var _fcs: FireControl
var _skel: Skeleton3D
var _failed := 0
var _cases := PackedStringArray(["head", "chest", "waist", "forearm", "thigh", "shin", "backpack",
		"shield", "bareshield", "drone", "vulcan", "repair"])
var _log: PackedStringArray = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("cases="):
			_cases = arg.get_slice("=", 1).split(",")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _ticks(20)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
			break
	var vehicle := _suit as Node as VehicleBase
	_model = vehicle.find_component(DamageModel) as DamageModel
	_fc = vehicle.find_component(FlightComputer) as FlightComputer
	_fcs = vehicle.find_component(FireControl) as FireControl
	_fcs.sensors.enabled = false
	_check("damage model built", _model != null and _model.is_built())
	if _model == null or not _model.is_built():
		print("RESULT: FAILED (no model)")
		quit()
		return
	_skel = (vehicle.find_component(LimbReaction) as LimbReaction).skeleton
	print("parts %d, components %d" % [_model.parts.size(), _model.components.size()])
	for p in _model.parts:
		if p.equipment == null:
			print("  %-18s dry %6.0f kg  tank %6.0f  vol %5.1f  density %5.1f  width %4.2f m" % [p.name, p.dry, p.tank, p.volume, p.density, p.width])
	_model.pilot_killed.connect(func() -> void: _log.append("pilot killed"))
	_model.reactor_breached.connect(func() -> void: _log.append("reactor breached"))
	_model.part_severed.connect(func(n: StringName) -> void: _log.append("severed %s" % n))
	_model.component_destroyed.connect(func(k: StringName, n: StringName) -> void: _log.append("%s %s out" % [k, n]))
	for c in _cases:
		match c:
			"layout": _layout()
			"cockpit": await _shot_at_point("cockpit (pilot)", _pilot_eye())
			"head": await _shot_at("head", &"head", Vector3.ZERO)
			"chest": await _shot_at("chest (cockpit)", &"chest", Vector3(0.0, 0.6, 0.0))
			"waist": await _shot_at("waist (reactor)", &"pelvis", Vector3(0.0, 0.5, 0.0))
			"forearm": await _shot_at("right forearm", &"forearm.R", Vector3.ZERO)
			"thigh": await _shot_at("left thigh", &"thigh.L", Vector3.ZERO)
			"shin": await _shot_at("right shin", &"shin.R", Vector3.ZERO)
			"backpack": await _shot_at("backpack from behind", &"backpack", Vector3.ZERO, true)
			"shield": await _shield(true)
			"bareshield": await _shield(false)
			"drone": await _drone()
			"vulcan": await _vulcan()
			"repair": await _repair()
	print("RESULT: %s" % ("PASS" if _failed == 0 else "%d FAILED" % _failed))
	quit()


## Where every component sits, in the body frame (x right, y up, -z forward).
func _layout() -> void:
	var inv := _suit.global_transform.affine_inverse()
	for c in _model.components:
		var at := inv * _model.component_position(c)
		print("  %-10s %-22s (%6.2f, %6.2f, %6.2f) r %.2f  part %s" % [DamageModel.KIND_NAMES[c.kind], c.name, at.x, at.y, at.z, c.radius, c.part.name if c.part else "-"])
	for p in _model.parts:
		if p.equipment == null:
			var centre := inv * _part_centre(p.name)
			print("  part %-16s centre (%6.2f, %6.2f, %6.2f) size %s section %.1f m² %s" % [p.name, centre.x, centre.y, centre.z, p.aabb.size, p.section, "limb" if p.limb else ""])


func _pilot_eye() -> Vector3:
	return (_suit as Node as VehicleBase).get_cockpit().get_player_camera().global_position


func _shot_at_point(label: String, target: Vector3) -> void:
	_model.repair()
	await _ticks(20)
	_log.clear()
	var forward := -_suit.global_basis.z
	var timing := await _fire(RIFLE, target + forward * 300.0, -forward)
	print("%-22s stalled %4.0f ms, beam %s | %s" % [label, timing[1] * 1000.0, "through" if timing[2] else "stopped", ", ".join(_log) if not _log.is_empty() else "-"])


func _part_centre(part_name: StringName) -> Vector3:
	var p := _model.find_part(part_name)
	return _skel.global_transform * _skel.get_bone_global_pose(p.bone) * p.aabb.get_center()


## Fires one rifle shot at `part` (offset in the body's frame) from 300 m ahead (or behind).
func _shot_at(label: String, part: StringName, offset: Vector3, from_behind := false) -> void:
	_model.repair()
	await _ticks(20)
	_log.clear()
	var target := _part_centre(part) + _suit.global_basis * offset
	var forward := -_suit.global_basis.z
	var muzzle_at := target + forward * (-300.0 if from_behind else 300.0)
	var dir := (target - muzzle_at).normalized()
	var timing := await _fire(RIFLE, muzzle_at, dir)
	var holed := PackedStringArray()
	for p in _model.parts:
		if p.mesh != null and _model.holes.get_hole_count(p.mesh) > 0:
			holed.append("%s(%d%%)" % [p.name, roundi(p.left * 100.0)])
	print("%-22s first contact %5.3f s, front stalled %4.0f ms | holed: %s" % [label, timing[0], timing[1] * 1000.0, ", ".join(holed)])
	print("%-22s events: %s" % ["", ", ".join(_log) if not _log.is_empty() else "-"])
	print("%-22s beam %s, reach past the target %.0f m" % ["", "went through" if timing[2] else "stopped", timing[3]])


## Fires `spec` from `at` along `dir` (a bare barrel held still for the pour). Returns
## [first contact s, stalled s, came out the far side, reach past the target point m].
func _fire(spec: ProjectileSpec, at: Vector3, dir: Vector3) -> Array:
	var pm := ProjectileManager.of(current_scene)
	var muzzle := Marker3D.new()
	current_scene.add_child(muzzle)
	muzzle.global_position = at
	var shot := pm.spawn(spec, at, _suit.linear_velocity + dir * spec.speed, dir, [], current_scene)
	var feed := func() -> Array: return [muzzle.global_position, _suit.linear_velocity + dir * spec.speed, dir]
	pm.stream_from(shot, muzzle, feed)
	var t := 0.0
	var first := -1.0
	var stall := 0.0
	var target_d := 300.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var through := false
	var reach_past := 0.0
	while t < 0.6:
		await physics_frame
		t += dt
		var touching := shot.blocked and shot.reach < target_d + 40.0 and shot.reach > target_d - 40.0
		if touching:
			if first < 0.0:
				first = t
			stall += dt
		if shot.reach > target_d + 40.0:
			through = true
		reach_past = maxf(reach_past, shot.reach - target_d)
	muzzle.queue_free()
	return [first, stall, through, reach_past]


func _shield(charged: bool) -> void:
	_model.repair()
	await _ticks(20)
	_log.clear()
	var shield := _suit.find_children("*", "MsShield", true, false)[0] as MsShield
	if not charged:
		shield.charges = 0
	var target := shield.global_transform * MsLoadout.local_box(shield).get_center()
	# Straight onto its face from where the suit's left side looks.
	var forward := -_suit.global_basis.z
	var left := -_suit.global_basis.x
	var dir := -(forward * 0.6 + left * 0.8).normalized()
	var timing := await _fire(RIFLE, target - dir * 300.0, dir)
	print("%-22s field %s, charges left %d, plate left %d%% | stalled %4.0f ms, %s | %s" % [
			"shield" + (" (charged)" if charged else " (no charge)"), "UP" if timing[1] > 0.0 and charged else "-",
			shield.charges, roundi(shield.left * 100.0), timing[1] * 1000.0,
			"through" if timing[2] else "stopped", ", ".join(_log) if not _log.is_empty() else "-"])
	if charged:
		_check("a charged shield's I-field takes the beam", shield.charges == 2 and not timing[2])
	else:
		_check("without a charge the beam goes through the shield", not timing[2] or _log.size() > 0 or shield.left < 1.0)


func _drone() -> void:
	for case in [["core", 0.0], ["off-centre 4 m", 4.0], ["off-centre 5.5 m", 5.5]]:
		var drone := TargetDrone.new()
		drone.behaviour = TargetDrone.Behaviour.STATIC
		current_scene.add_child(drone)
		var at := _suit.global_position + Vector3(0, 0, -2000.0)
		drone.global_position = at
		await _ticks(3)
		var gone := [false]
		drone.destroyed.connect(func(_d: TargetDrone) -> void: gone[0] = true)
		var side := Vector3.RIGHT * float(case[1])
		var muzzle := at + Vector3(0, 0, 300.0) + side
		var timing := await _fire(RIFLE, muzzle, Vector3(0, 0, -1))
		var dead: bool = is_instance_valid(drone) and drone.get("_dead")
		print("%-22s %s, stalled %4.0f ms, beam %s" % ["drone " + String(case[0]),
				"DESTROYED" if gone[0] else ("dead in space" if dead else "still working"), timing[1] * 1000.0,
				"through" if timing[2] else "stopped"])
		if case[0] == "core":
			_check("a beam through the drone's core breaches it", gone[0])
		if is_instance_valid(drone):
			drone.queue_free()
		await _ticks(5)


func _vulcan() -> void:
	_model.repair()
	await _ticks(20)
	_fc.fcs_enabled = false
	_suit.angular_velocity = Vector3.ZERO
	_suit.linear_velocity = Vector3.ZERO
	await _ticks(2)
	var head := _part_centre(&"head")
	var w0 := _suit.angular_velocity
	var v0 := _suit.linear_velocity
	var dir := (_suit.global_basis.z).normalized()   # from the front, into the suit
	for i in 21:
		_model.apply_impact(VULCAN, head + _suit.global_basis.x * 0.8, dir * 1100.0, 0.0, null)
	await _ticks(1)
	var dw := rad_to_deg((_suit.angular_velocity - w0).length())
	var dv := (_suit.linear_velocity - v0).length()
	print("%-22s 1 s of both vulcans into the head: Δv %.2f m/s, spin %.2f°/s | %s" % ["vulcans", dv, dw, ", ".join(_log) if not _log.is_empty() else "-"])
	_check("a vulcan second barely moves 69 t (< 1.5 m/s, < 15°/s)", dv < 1.5 and dw < 15.0)
	_fc.fcs_enabled = true


func _repair() -> void:
	_model.repair()
	await _ticks(10)
	var forearm := _model.find_part(&"forearm.R")
	var thrusters_before := _count_enabled()
	var mass_before := _suit.mass
	_model.sever(_model.find_part(&"thigh.L"))
	await _ticks(30)
	var thrusters_cut := _count_enabled()
	var leg_gone := _model.find_part(&"shin.L").severed and not _model.find_part(&"shin.L").mesh.visible
	print("%-22s thigh severed: shin gone %s, thrusters %d → %d, mass %.1f → %.1f t" % ["sever + repair", leg_gone, thrusters_before, thrusters_cut, mass_before / 1000.0, _suit.mass / 1000.0])
	_check("severing a thigh takes the leg, its thrusters and its mass", leg_gone and thrusters_cut < thrusters_before and _suit.mass < mass_before - 3000.0)
	_model.repair()
	await _ticks(10)
	_check("repair puts it all back", not forearm.severed and _model.find_part(&"shin.L").mesh.visible
			and _count_enabled() == thrusters_before and absf(_suit.mass - mass_before) < 50.0)


func _count_enabled() -> int:
	var n := 0
	for t in _suit.find_children("*", "Thruster", true, false):
		if (t as Thruster).enabled:
			n += 1
	return n


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["ok   " if ok else "FAIL ", label])
	if not ok:
		_failed += 1


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
