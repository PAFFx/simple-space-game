extends SceneTree

## Headless check of the weapons chain on the RX-93: modes, selection, lock, aim, lead,
## hits and damage, with scripted pilot input.
##
##   godot-double --headless --path . -s Tools/Weapons/weapons_probe.gd

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		# One-shots last one tick.
		cmd = PilotCommand.new()
		cmd.fire_main = out.fire_main
		cmd.vulcan_ready = out.vulcan_ready
		cmd.vulcan_fire = out.vulcan_fire
		cmd.shield_block = out.shield_block
		return out

var _suit: RigidBody3D
var _fcs: FireControl
var _input := ScriptedInput.new()
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _ticks(10)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
	var vehicle := _suit as Node as VehicleBase
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = vehicle.find_component(FireControl) as FireControl
	# Logic checks shoot from a perfect track; sensor noise is track_probe's job.
	_fcs.sensors.enabled = false
	print("weapons: ", _fcs.weapons.keys())
	_check("weapons found", _fcs.weapons.size() == 4)

	# NAV: nothing selected; the hat drops into DGFT with the rifle.
	_check("starts NAV / SAFE", _fcs.mode == FireControl.MasterMode.NAV and not _fcs.master_arm and _fcs.selected == null)
	_check("centre display has the SOI from the start", _fcs.soi == FireControl.Soi.MFD)
	_input.cmd.scs = FireControl.Scs.FORWARD
	await _ticks(1)
	_check("SCS forward: HUD cursor", _fcs.soi == FireControl.Soi.HUD_CURSOR)
	_input.cmd.scs = FireControl.Scs.FORWARD
	await _ticks(1)
	_check("SCS forward again: HMCS", _fcs.soi == FireControl.Soi.HMCS)
	_input.cmd.scs = FireControl.Scs.LEFT
	await _ticks(1)
	_check("SCS left: left display", _fcs.soi == FireControl.Soi.MFD and _fcs.soi_display != null)
	_input.cmd.scs = FireControl.Scs.FORWARD
	await _ticks(1)
	_check("SCS forward from a display: HUD cursor", _fcs.soi == FireControl.Soi.HUD_CURSOR)
	_input.cmd.weapon_select = FireControl.Hat.FORWARD
	await _ticks(2)
	_check("hat forward → DGFT + rifle", _fcs.mode == FireControl.MasterMode.DGFT and _id() == &"beam_rifle")
	_input.cmd.weapon_select = FireControl.Hat.FORWARD
	await _ticks(2)
	_check("forward again stays on the rifle", _id() == &"beam_rifle")
	_input.cmd.weapon_select = FireControl.Hat.LEFT
	await _ticks(2)
	_check("left → missile", _id() == &"shield_missile")
	_input.cmd.weapon_select = FireControl.Hat.AFT
	await _ticks(2)
	_check("aft (nothing fitted) keeps selection", _id() == &"shield_missile")
	_input.cmd.master_mode = FireControl.MasterMode.NAV
	await _ticks(2)
	_check("NAV stows", _fcs.selected == null)
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _ticks(2)
	_check("DGFT selects rifle", _id() == &"beam_rifle")

	# Static target 1.2 km ahead, 20° right, 10° up.
	var drone := _spawn(TargetDrone.Behaviour.STATIC, 1200.0, Vector2(20, 10))
	await _ticks(5)
	# Lock through the HUD cursor: slew it onto the target, preview, commit.
	_fcs.cursor = Vector2(20, 10)
	await _ticks(2)
	_check("candidate under cursor", _fcs.candidate == drone)
	_input.cmd.lock_commit = true
	await _ticks(2)
	_check("locked", _fcs.locked == drone)
	_check("no cursor while locked", not _fcs.is_cursor_shown() and _fcs.candidate == null)
	_input.cmd.lock_commit = true
	await _ticks(2)
	_check("locking again keeps the lock", _fcs.locked == drone)
	_input.cmd.zoom = true
	await _ticks(1)
	_input.cmd.zoom = true
	await _ticks(1)
	_check("zoom opens and cycles", _fcs.zoom_level == 2)
	_input.cmd.unlock = true
	await _ticks(1)
	_check("unlock closes the zoom first", _fcs.zoom_level == 0 and _fcs.locked == drone)
	var other := _spawn(TargetDrone.Behaviour.STATIC, 1200.0, Vector2(-20, 10))
	await _ticks(2)
	_input.cmd.target_cycle = 1
	await _ticks(1)
	_check("cycle right steps to another contact", _fcs.locked != drone and _fcs.locked != null)
	_input.cmd.target_cycle = -1
	await _ticks(1)
	_check("cycle left steps back", _fcs.locked == drone)
	other.queue_free()
	_fcs.cursor = Vector2(50, 0)
	_input.cmd.unlock = true
	await _ticks(1)
	_check("unlock drops the lock, cursor back ahead", _fcs.locked == null and _fcs.cursor == Vector2.ZERO)
	_fcs.cursor = Vector2(20, 10)
	await _ticks(1)
	_check("hovering previews without a button", _fcs.candidate == drone)
	_input.cmd.zoom = true
	await _ticks(2)
	_check("zoom with nothing locked locks the candidate and opens", _fcs.locked == drone and _fcs.zoom_level == 1)
	_input.cmd.unlock = true
	await _ticks(1)
	_input.cmd.unlock = true
	await _ticks(1)
	var near := _spawn(TargetDrone.Behaviour.STATIC, 60.0, Vector2(-40, -10))
	await _ticks(10)
	_input.cmd.lock_nearest = true
	await _ticks(2)
	_check("TMS depress locks the nearest contact", _fcs.locked == near)
	_fcs.lock(null)
	near.queue_free()
	await _ticks(2)
	_fcs.cursor = Vector2(20, 10)
	await _ticks(1)
	# Behind a wall: out of sight, so it can't be designated.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 200, 20)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	_suit.get_parent().add_child(wall)
	var los_dir := _suit.global_basis.orthonormalized() * SpatialMath.angles_to_direction(Vector2(-60, -20))
	wall.global_transform = Transform3D(Basis.looking_at(los_dir), _fcs.get_view_origin() + los_dir * 500.0)
	var hidden := _spawn(TargetDrone.Behaviour.STATIC, 1200.0, Vector2(-60, -20))
	var saved_cursor := _fcs.cursor
	_fcs.cursor = SpatialMath.direction_to_angles(_fcs._display_basis().inverse() * los_dir)
	await _ticks(10)
	_check("contact behind a wall is hidden and not designated", not _fcs.can_see(hidden) and _fcs.candidate != hidden)
	wall.queue_free()
	await _ticks(10)
	_check("back in sight once the wall is gone", _fcs.can_see(hidden) and _fcs.candidate == hidden)
	hidden.queue_free()
	_fcs.cursor = saved_cursor
	await _ticks(2)
	_input.cmd.lock_commit = true
	await _ticks(2)
	var rifle := _fcs.get_weapon(&"beam_rifle")
	await _ticks(90)
	print("rifle state %d readiness %.2f aim %s lead %s on_target %s tof %.3f range %.0f" % [rifle.state, rifle.readiness,
			rifle.aim, rifle.lead_angles, rifle.on_target, rifle.time_of_flight, rifle.target_range])
	_check("rifle ready and on target", rifle.state == MsWeapon.State.READY and rifle.on_target)

	# SAFE: no shot.
	_input.cmd.fire_main = true
	await _ticks(5)
	_check("SAFE holds fire", rifle.ammo == rifle.max_ammo)
	_input.cmd.fire_main = false
	_input.cmd.master_arm = 1
	await _ticks(2)
	# Spool: let go early and nothing leaves; hold through it and one shot leaves, however
	# long it is held after.
	var spool_ticks := ceili(rifle.projectile.spool_time * Engine.physics_ticks_per_second)
	_input.cmd.fire_main = true
	await _ticks(spool_ticks / 2)
	_check("spooling shows", rifle.is_spooling())
	_input.cmd.fire_main = false
	await _ticks(2)
	_check("let go early: no shot, spool drops", rifle.ammo == rifle.max_ammo and not rifle.is_spooling())
	_input.cmd.fire_main = true
	await _ticks(spool_ticks + 2)
	_check("held through the spool: shot leaves", rifle.ammo == rifle.max_ammo - 1)
	var hp := drone.hit_points if is_instance_valid(drone) else 0.0
	# The beam: one straight line on the barrel while it pours out, then flying free.
	var manager := ProjectileManager.find(_fcs)
	var beam: ProjectileManager.Shot = null
	for shot in manager._shots:
		if shot.spec == rifle.projectile:
			beam = shot
	await _ticks(maxi(ceili(rifle.projectile.emit_time * Engine.physics_ticks_per_second / 2.0) - 2, 1))
	_check("beam pours out along the barrel", beam != null and beam.emitting and beam.tail == 0.0
			and rad_to_deg(beam.thrust_dir.angle_to(rifle.get_aim_direction(_fcs))) < 0.5
			and beam.position.distance_to(rifle.get_muzzle_position()) < 1.0)
	if beam != null:
		print("beam: front %.0f m after %.3f s (speed × age %.0f)" % [beam.reach, beam.age, rifle.projectile.speed * beam.age])
		_check("its front travels at the beam's speed", absf(beam.reach - rifle.projectile.speed * beam.age) < 60.0)
		await _ticks(ceili(rifle.projectile.emit_time * Engine.physics_ticks_per_second))
		print("beam let go: tail %.0f front %.0f blocked %s" % [beam.tail, beam.reach, beam.blocked])
		_check("let go, the line flies on", not beam.emitting and beam.tail > 0.0)
	await _ticks(ceili(rifle.cycle_time * Engine.physics_ticks_per_second) + spool_ticks + 10)
	_check("held on: no second shot", rifle.ammo == rifle.max_ammo - 1)
	_input.cmd.fire_main = false
	await _ticks(40)
	_check("beam kills the static drone", not is_instance_valid(drone) or drone.hit_points < hp)
	_check("lock drops with the target", _fcs.locked == null)

	await _beam_range_check()

	# Drifting target crossing at ~100 m/s: lead must hit.
	drone = _spawn(TargetDrone.Behaviour.DRIFT, 2000.0, Vector2(10, 0))
	drone.velocity = _suit.linear_velocity + _suit.global_basis * Vector3(100, 20, 0)
	drone.hit_points = 5000.0
	_fcs.lock(drone)
	await _ticks(60)
	print("drift: aim %s lead %s on_target %s tof %.3f" % [rifle.aim, rifle.lead_angles, rifle.on_target, rifle.time_of_flight])
	hp = drone.hit_points
	_input.cmd.fire_main = true
	await _ticks(spool_ticks + 2)
	_input.cmd.fire_main = false
	await _ticks(60)
	_check("lead shot hits a crossing target", drone.hit_points < hp)

	# Vulcans: head envelope, burst.
	var vulcan := _fcs.get_vulcan()
	if is_instance_valid(drone):
		drone.queue_free()
	await _ticks(2)
	drone = _spawn(TargetDrone.Behaviour.STATIC, 400.0, Vector2(-15, 5))
	drone.hit_points = 5000.0
	_fcs.lock(drone)
	_input.cmd.vulcan_ready = true
	await _ticks(40)
	_check("vulcan spun up and on target", vulcan.state == MsWeapon.State.READY and vulcan.on_target)
	hp = drone.hit_points
	_input.cmd.vulcan_fire = true
	await _ticks(60)
	_input.cmd.vulcan_fire = false
	_input.cmd.vulcan_ready = false
	await _ticks(40)
	print("vulcan: fired %d, damage %.0f" % [vulcan.max_ammo - vulcan.ammo, hp - drone.hit_points])
	_check("vulcan burst lands", hp - drone.hit_points > 100.0)

	# Missiles: burst near the target; blocked while the shield is up.
	drone.queue_free()
	await _ticks(2)
	drone = _spawn(TargetDrone.Behaviour.STATIC, 700.0, Vector2(-10, 0))
	drone.hit_points = 5000.0
	_fcs.lock(drone)
	_input.cmd.weapon_select = FireControl.Hat.LEFT
	await _ticks(2)
	var missile := _fcs.get_weapon(&"shield_missile")
	_check("missile selected", _fcs.selected == missile)
	_input.cmd.shield_block = true
	_input.cmd.fire_main = true
	await _ticks(90)
	_check("no launch while blocking", missile.ammo == missile.max_ammo and _fcs.blocking)
	_input.cmd.shield_block = false
	_input.cmd.fire_main = false
	await _ticks(120)
	print("missile: state %d aim %s lead %s on_target %s tof %.2f" % [missile.state, missile.aim, missile.lead_angles, missile.on_target, missile.time_of_flight])
	hp = drone.hit_points
	_input.cmd.fire_main = true
	await _ticks(3)
	_input.cmd.fire_main = false
	await _ticks(240)
	print("missile: left %d, damage %.0f" % [missile.ammo, hp - drone.hit_points])
	_check("missile blast hurts the target", hp - drone.hit_points > 50.0)
	_check("fired missile leaves the shield", not missile.get_node(missile.round_meshes[0]).visible
			and missile.get_node(missile.round_meshes[1]).visible)
	# The rest of the rack, flying fast: none may stop on the suit's own shield.
	_suit.linear_velocity = -_suit.global_basis.z * 300.0
	var self_hits := [0]
	var on_self := func(_spec: ProjectileSpec, _at: Vector3, collider: Node) -> void:
		if VehicleBase.find_vehicle(collider) == _fcs.vehicle:
			self_hits[0] += 1
	ProjectileManager.of(_suit).shot_hit.connect(on_self)
	for i in 3:
		_input.cmd.fire_main = true
		await _ticks(3)
		_input.cmd.fire_main = false
		await _ticks(60)
	await _ticks(180)
	ProjectileManager.of(_suit).shot_hit.disconnect(on_self)
	print("missile rack: left %d, self hits %d" % [missile.ammo, self_hits[0]])
	_check("whole rack fired", missile.ammo == 0)
	_check("no missile stops on its own shield", self_hits[0] == 0)
	_check("rack empty on the model", missile.round_meshes.all(func(p: NodePath) -> bool: return not missile.get_node(p).visible))
	_fcs.rearm()
	_check("rearm reloads the rack", missile.round_meshes.all(func(p: NodePath) -> bool: return missile.get_node(p).visible))

	# A turret shoots back; the hit is reported, and blocked when the shield faces it.
	drone.queue_free()
	await _ticks(2)
	var hits := [0, 0]
	_fcs.hit_taken.connect(func(blocked: bool) -> void: hits[1 if blocked else 0] += 1)
	drone = _spawn(TargetDrone.Behaviour.TURRET, 500.0, Vector2(0, 0))
	drone.fire_interval = Vector2(0.4, 0.5)
	drone.aim_error_deg = 0.0
	drone.jink_accel_g = 0.0
	await _ticks(240)
	print("turret: hits taken %d, blocked %d" % [hits[0], hits[1]])
	_check("turret hits the suit", hits[0] > 0)
	_input.cmd.shield_block = true
	await _ticks(60)
	hits[0] = 0
	hits[1] = 0
	await _ticks(240)
	print("turret vs shield: hits taken %d, blocked %d" % [hits[0], hits[1]])
	_check("shield blocks the turret's shots", hits[1] > 0 and hits[0] == 0)

	# Dug in: the head can't see through the shield, a body camera holds the track, and
	# the vulcans can't fire through it.
	drone.queue_free()
	await _ticks(2)
	drone = _spawn(TargetDrone.Behaviour.STATIC, 400.0, Vector2(0, 0))
	drone.hit_points = 5000.0
	_fcs.sensors.enabled = true
	_fcs.lock(drone)
	await _ticks(60)
	print("dug in: sensor source %s" % SensorSuite.Source.keys()[_fcs.sensors.source])
	_check("body camera tracks while dug in", _fcs.sensors.source == SensorSuite.Source.BODY)
	_fcs.sensors.enabled = false
	var vulcan_left := vulcan.ammo
	_input.cmd.vulcan_ready = true
	_input.cmd.vulcan_fire = true
	await _ticks(90)
	var masked := vulcan.masked
	_input.cmd.vulcan_ready = false
	_input.cmd.vulcan_fire = false
	await _ticks(60)
	print("vulcan at own shield: masked %s, fired %d" % [masked, vulcan_left - vulcan.ammo])
	_check("vulcans hold fire into own shield", masked and vulcan.ammo == vulcan_left)
	_input.cmd.shield_block = false

	print("RESULT: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _id() -> StringName:
	return _fcs.selected.weapon_id if _fcs.selected != null else &""


func _spawn(behaviour: TargetDrone.Behaviour, distance: float, angles: Vector2) -> TargetDrone:
	var drone := TargetDrone.new()
	drone.behaviour = behaviour
	drone.quarry = _suit
	drone.velocity = _suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(angles) * distance
	return drone


func _check(what: String, ok: bool) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## A beam fired straight up from high above the suit into empty space, its range cut to
## 1.2 km: its front stops and dissipates there, and the whole shot is gone after its tail
## and wake get there.
func _beam_range_check() -> void:
	var spec := (_fcs.get_weapon(&"beam_rifle").projectile as ProjectileSpec).duplicate() as ProjectileSpec
	spec.lifetime = 1200.0 / spec.speed
	var barrel := Node3D.new()
	_suit.get_parent().add_child(barrel)
	barrel.global_position = _suit.global_position + Vector3.UP * 3000.0
	var manager := ProjectileManager.of(_suit)
	var beam := manager.spawn(spec, barrel.global_position, Vector3.UP * spec.speed, Vector3.UP)
	manager.stream_from(beam, barrel, func() -> Array:
		return [barrel.global_position, Vector3.UP * spec.speed, Vector3.UP])
	var tps := Engine.physics_ticks_per_second
	await _ticks(ceili((1200.0 / spec.speed + 0.05) * tps))
	print("beam at range: front %.0f tail %.0f at_range %s" % [beam.reach, beam.tail, beam.at_range])
	_check("beam's front stops at its range", is_equal_approx(beam.reach, 1200.0) and beam.at_range and beam.tail > 0.0)
	await _ticks(ceili((spec.emit_time + spec.trail_time + 0.1) * tps))
	_check("then it is gone, wake and all", not manager._shots.has(beam))
	barrel.queue_free()


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
