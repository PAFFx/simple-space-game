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
		cmd.lock_preview = out.lock_preview
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
	print("weapons: ", _fcs.weapons.keys())
	_check("weapons found", _fcs.weapons.size() == 5)

	# NAV: nothing selected; the hat drops into DGFT with the rifle.
	_check("starts NAV / SAFE", _fcs.mode == FireControl.MasterMode.NAV and not _fcs.master_arm and _fcs.selected == null)
	_input.cmd.weapon_select = FireControl.Hat.FORWARD
	await _ticks(2)
	_check("hat forward → DGFT + rifle", _fcs.mode == FireControl.MasterMode.DGFT and _id() == &"beam_rifle")
	_input.cmd.weapon_select = FireControl.Hat.FORWARD
	await _ticks(2)
	_check("forward again → linear", _id() == &"beam_linear")
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
	_input.cmd.lock_preview = true
	await _ticks(2)
	_check("candidate under cursor", _fcs.candidate == drone)
	_input.cmd.lock_commit = true
	await _ticks(2)
	_check("locked", _fcs.locked == drone)
	_input.cmd.lock_preview = false
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
	await _ticks(ceili(rifle.cycle_time * Engine.physics_ticks_per_second) + spool_ticks + 10)
	_check("held on: no second shot", rifle.ammo == rifle.max_ammo - 1)
	_input.cmd.fire_main = false
	await _ticks(40)
	_check("beam kills the static drone", not is_instance_valid(drone) or drone.hit_points < hp)
	_check("lock drops with the target", _fcs.locked == null)

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

	# Linear: forward again keeps the arm up, costs 3 of the shared E-pack, follows the
	# barrel while it pours out and hits the crossing target.
	_input.cmd.weapon_select = FireControl.Hat.FORWARD
	await _ticks(2)
	var linear := _fcs.get_weapon(&"beam_linear")
	# Inside the linear's reach (speed × emit time).
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(Vector2(10, 0)) * 1200.0
	_check("linear selected, still ready", _fcs.selected == linear and linear.state == MsWeapon.State.READY)
	# The pulse's cooldown holds the linear too (one barrel).
	await _ticks(100)
	var before := linear.ammo
	_check("shares the E-pack", before == rifle.ammo)
	hp = drone.hit_points
	var lin_spool := ceili(linear.projectile.spool_time * Engine.physics_ticks_per_second)
	_input.cmd.fire_main = true
	await _ticks(lin_spool + 2)
	_input.cmd.fire_main = false
	_check("linear costs 3", rifle.ammo == before - 3)
	var manager := ProjectileManager.find(_fcs)
	var beam: ProjectileManager.Shot = null
	for shot in manager._shots:
		if shot.spec.kind == ProjectileSpec.Kind.LINEAR:
			beam = shot
	await _ticks(10)
	_check("linear still on the barrel, front advancing", beam != null and beam.emitting and beam.reach > 30.0)
	if beam != null:
		var barrel := linear.get_aim_direction(_fcs)
		print("linear: reach %.0f length %.0f, off the barrel %.3f°" % [beam.reach, beam.length, rad_to_deg(beam.thrust_dir.angle_to(barrel))])
		_check("linear lies along the barrel", rad_to_deg(beam.thrust_dir.angle_to(barrel)) < 0.5)
	await _ticks(90)
	print("linear: damage %.0f" % (hp - drone.hit_points))
	_check("linear hits a crossing target", drone.hit_points < hp)
	# A kill mid-beam: the barrel holds where it was instead of swinging back at once.
	drone.queue_free()
	await _ticks(2)
	drone = _spawn(TargetDrone.Behaviour.STATIC, 600.0, Vector2(25, 8))
	drone.hit_points = 1.0
	_fcs.lock(drone)
	await _ticks(ceili(linear.cycle_time * Engine.physics_ticks_per_second) + 60)
	_input.cmd.fire_main = true
	await _ticks(lin_spool + 2)
	_input.cmd.fire_main = false
	await _ticks(20)
	var aim_at_kill := linear.aim
	_check("linear kills, lock drops", _fcs.locked == null)
	await _ticks(20)
	print("linear after the kill: aim %s → %s" % [aim_at_kill, linear.aim])
	_check("aim holds after the kill", linear.aim.distance_to(aim_at_kill) < 0.5)
	await _ticks(90)
	_check("then back to the boresight", linear.aim.distance_to(linear.boresight) < 1.0)
	_input.cmd.weapon_select = FireControl.Hat.FORWARD
	await _ticks(2)
	_check("forward again → pulse", _fcs.selected == rifle)

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
	_check("shield blocks what the pilot looks at", hits[1] > 0 and hits[0] == 0)

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


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
