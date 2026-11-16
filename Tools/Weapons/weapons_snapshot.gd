extends SceneTree

## Renders the weapons in use to PNGs, with scripted pilot input: HUD symbology, the beam
## from the cockpit and from outside, poses, the weapon ring. A visual check.
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 -s Tools/Weapons/weapons_snapshot.gd -- <out_dir> [shots]
##
## shots: comma list of hud,beam,external,impact,ring,vulcan,missile,block,turret,glow,offaxis
## (default all). offaxis also prints AIM lines: lead, gun and target agreement and miss.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.fire_main = out.fire_main
		cmd.vulcan_ready = out.vulcan_ready
		cmd.vulcan_fire = out.vulcan_fire
		cmd.shield_block = out.shield_block
		cmd.lock_preview = out.lock_preview
		return out

var _out := "user://weapons_snapshot"
var _suit: RigidBody3D
var _vehicle: VehicleBase
var _fcs: FireControl
var _input := ScriptedInput.new()
var _fp: PilotCamera
var _ext: Camera3D


## A weapon whose aim is swept while a sequence is saved (linear beam bending).
var _sweep: MsWeapon


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var shots := PackedStringArray(["hud", "beam", "external", "linear", "explode", "impact", "ring", "vulcan", "missile", "block", "turret", "glow", "offaxis"])
	if args.size() > 1:
		shots = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred(shots)


func _run(shots: PackedStringArray) -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _frames(20)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_vehicle = node
	_suit = _vehicle as Node as RigidBody3D
	var fc := _vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = _vehicle.find_component(FireControl) as FireControl
	_fp = _vehicle.get_cockpit().get_player_camera() as PilotCamera
	_ext = Camera3D.new()
	_ext.cull_mask = Layers.MASK_THIRD_PERSION
	_ext.fov = 45.0
	_ext.far = 20000.0
	_vehicle.add_child(_ext)

	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	_input.cmd.master_arm = 1
	await _frames(5)
	var drone := _spawn(TargetDrone.Behaviour.STATIC, 900.0, Vector2(14, 6), 100000.0)
	_fcs.cursor = Vector2(14, 6)
	_input.cmd.lock_preview = true
	await _frames(8)
	if "hud" in shots:
		await _shot("hud_candidate")
	_input.cmd.lock_commit = true
	await _frames(3)
	_input.cmd.lock_preview = false
	await _frames(25)
	if "hud" in shots:
		await _shot("hud_slewing")
	await _frames(70)
	if "hud" in shots:
		await _shot("hud_shoot")
		_look(14, 6, 35.0)
		await _shot("hud_shoot_zoom")
		_look(0, 0)

	if "beam" in shots:
		await _fire_sequence("beam_fp", 6)
		await _frames(90)
		_look(14, 6, 35.0)
		await _fire_sequence("beam_fp_zoom", 5)
		_look(0, 0)
		await _frames(90)
		# Looking back down at the lap: the cockpit lit by the shot.
		_look(-30, -35)
		await _fire_sequence("beam_cockpit", 5)
		_look(0, 0)
		await _frames(90)

	if "external" in shots:
		_ext.make_current()
		_ext_view(Vector3(22, 20, 26), Vector3(4, 16, -10))
		await _shot("ext_rifle_pose")
		await _fire_sequence("ext_beam", 5)
		await _frames(90)
		_ext_view(Vector3(-30, 16, -45), Vector3(3, 16, 0))
		await _shot("ext_front_pose")
		await _fire_sequence("ext_front_beam", 4)
		await _frames(90)
		# Side-on from far away: the whole bolt and its wake.
		_ext_view(Vector3(500, 80, -300), Vector3(60, 40, -300))
		_ext.fov = 60.0
		await _fire_sequence("ext_far_beam", 6)
		_ext.fov = 45.0
		await _frames(90)
		_fp.make_current()

	if "linear" in shots:
		_input.cmd.weapon_select = FireControl.Hat.FORWARD
		await _frames(10)
		var linear := _fcs.selected
		await _fire_sequence("linear_fp", 6, 2)
		# Side-on from far away, the barrel sweeping while it pours out: the column bends
		# with it and stays on the muzzle.
		_ext.make_current()
		_ext_view(Vector3(700, 120, -500), Vector3(60, 40, -500))
		_ext.fov = 70.0
		_sweep = linear
		await _fire_sequence("linear_ext_sweep", 10, 3)
		_sweep = null
		linear.aim_override = null
		_ext_view(Vector3(26, 22, 30), Vector3(4, 16, -10))
		_ext.fov = 45.0
		await _fire_sequence("linear_ext_close", 6, 2)
		_fp.make_current()
		_input.cmd.weapon_select = FireControl.Hat.FORWARD
		await _frames(30)

	if "explode" in shots:
		var victim := _spawn(TargetDrone.Behaviour.STATIC, 600.0, Vector2(-20, 0), 1.0)
		await _frames(5)
		_ext.make_current()
		var to_suit := (_suit.global_position - victim.global_position).normalized()
		_ext.global_transform = Transform3D(Basis.IDENTITY, victim.global_position + to_suit * 160.0 + Vector3.UP * 40.0) \
				.looking_at(victim.global_position, Vector3.UP)
		ProjectileManager.of(victim).explode(victim.global_position, victim.velocity, victim.radius * 3.0)
		victim.queue_free()
		for i in 8:
			await _frames(5)
			await _shot("explode_drone_%d" % i)
		# A missile-sized one (90 m), from 400 m.
		var at := _suit.global_position + _suit.global_basis * Vector3(0, 0, -900)
		_ext.global_transform = Transform3D(Basis.IDENTITY, at + Vector3(0, 60, 400)).looking_at(at, Vector3.UP)
		ProjectileManager.of(_suit).explode(at, _suit.linear_velocity, 90.0, Color(1, 0.72, 0.45))
		for i in 8:
			await _frames(6)
			await _shot("explode_blast_%d" % i)
		_fp.make_current()

	if "impact" in shots:
		# From beside the target, looking back along the shot.
		_ext.make_current()
		var to_suit := (_suit.global_position - drone.global_position).normalized()
		var side := to_suit.cross(Vector3.UP).normalized()
		_ext.global_transform = Transform3D(Basis.IDENTITY, drone.global_position + side * 45.0 + to_suit * 25.0 + Vector3.UP * 8.0) \
				.looking_at(drone.global_position, Vector3.UP)
		await _fire_sequence("impact", 14, 2)
		_fp.make_current()
		await _frames(60)

	if "ring" in shots:
		_look(31, -40, 24.0)
		_input.cmd.weapon_select = FireControl.Hat.FORWARD
		await _frames(12)
		await _shot("ring_missile")
		_input.cmd.weapon_select = FireControl.Hat.AFT
		await _frames(6)
		await _shot("ring_aft_unfitted")
		await _frames(180)
		await _shot("target_page")
		_input.cmd.weapon_select = FireControl.Hat.FORWARD
		await _frames(100)
		_look(0, 0)

	if "vulcan" in shots:
		drone.queue_free()
		await _frames(3)
		drone = _spawn(TargetDrone.Behaviour.STATIC, 350.0, Vector2(-12, 8), 100000.0)
		_fcs.lock(drone)
		_input.cmd.vulcan_ready = true
		await _frames(40)
		await _shot("vulcan_ready_fp")
		_input.cmd.vulcan_fire = true
		await _frames(25)
		await _shot("vulcan_fire_fp")
		_look(-12, 8, 35.0)
		await _shot("vulcan_fire_zoom")
		_look(0, 0)
		_ext.make_current()
		_ext_view(Vector3(-12, 22, -22), Vector3(0, 20, -3))
		await _shot("vulcan_fire_ext")
		_fp.make_current()
		_input.cmd.vulcan_fire = false
		_input.cmd.vulcan_ready = false
		await _frames(60)

	if "missile" in shots:
		_input.cmd.weapon_select = FireControl.Hat.LEFT
		await _frames(120)
		await _shot("missile_hud")
		_ext.make_current()
		_ext_view(Vector3(-30, 18, -42), Vector3(-3, 15, -4))
		await _shot("missile_pose_ext")
		_input.cmd.fire_main = true
		await _frames(2)
		_input.cmd.fire_main = false
		for i in 4:
			await _frames(6)
			await _shot("missile_launch_ext_%d" % i)
		_fp.make_current()
		await _frames(30)
		await _shot("missile_burst_fp")
		await _frames(90)
		_input.cmd.weapon_select = FireControl.Hat.FORWARD
		await _frames(60)

	if "block" in shots:
		_look(-40, 10)
		_input.cmd.shield_block = true
		await _frames(60)
		await _shot("block_fp")
		_ext.make_current()
		_ext_view(Vector3(-26, 20, -40), Vector3(-2, 16, 0))
		await _shot("block_left_ext")
		_fp.make_current()
		_look(25, 25)
		await _frames(50)
		_ext.make_current()
		await _shot("block_right_up_ext")
		_fp.make_current()
		_input.cmd.shield_block = false
		_look(0, 0)
		await _frames(40)

	if "overlay" in shots:
		# The arm / rifle outlines resolving in on entering DGFT, and breaking up in NAV.
		_input.cmd.master_mode = FireControl.MasterMode.NAV
		await _frames(60)
		_input.cmd.master_mode = FireControl.MasterMode.DGFT
		for i in 8:
			await _frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/overlay_in_%02d.png" % [_out, i])
		await _frames(30)
		_input.cmd.master_mode = FireControl.MasterMode.NAV
		for i in 5:
			await _frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/overlay_out_%02d.png" % [_out, i])
		_input.cmd.master_mode = FireControl.MasterMode.DGFT
		await _frames(60)

	if "turret" in shots:
		if is_instance_valid(drone):
			drone.queue_free()
		await _frames(3)
		drone = _spawn(TargetDrone.Behaviour.TURRET, 700.0, Vector2(5, 4), 100000.0)
		drone.fire_interval = Vector2(0.5, 0.6)
		drone.jink_accel_g = 0.0
		drone.aim_error_deg = 0.0
		await _frames(150)
		_look(5, 4, 30.0)
		for i in 8:
			await _frames(4)
			await _shot("turret_%02d" % i)
		_look(0, 0)
		_input.cmd.shield_block = true
		await _frames(60)
		for i in 4:
			await _frames(7)
			await _shot("turret_block_%02d" % i)
		_input.cmd.shield_block = false

	if "glow" in shots:
		# The turret's charge as the pilot sees it (normal field of view), at three ranges,
		# with the old look (no size floor, no glare) and the new one.
		if is_instance_valid(drone):
			drone.queue_free()
		var manager := ProjectileManager.of(_suit)
		var floor_angle := manager.charge_min_angle
		var glare := manager.charge_glare
		for r in [700.0, 1500.0, 3000.0]:
			for look in ["old", "new"]:
				manager.charge_min_angle = 0.0 if look == "old" else floor_angle
				manager.charge_glare = 0.0 if look == "old" else glare
				await _frames(3)
				var turret := _spawn(TargetDrone.Behaviour.TURRET, r, Vector2(6, 3), 100000.0)
				turret.jink_accel_g = 0.0
				turret.fire_range = r * 2.0
				turret.fire_interval = Vector2(0.3, 0.3)
				_look(6, 3)
				for k in 600:
					if turret.is_spooling():
						break
					await physics_frame
				# _shot waits 3 ticks itself: half-way, then ~85% of the 0.5 s spool.
				await _frames(9)
				await _shot("glow_%04d_%s_half" % [int(r), look])
				await _frames(7)
				await _shot("glow_%04d_%s_late" % [int(r), look])
				turret.queue_free()
		manager.charge_min_angle = floor_angle
		manager.charge_glare = glare
		_look(0, 0)

	if "offaxis" in shots:
		# Lock straight ahead, then yaw and strafe away: the lead, the gun cross and where a
		# shot actually goes must still agree.
		if is_instance_valid(drone):
			drone.queue_free()
		await _frames(3)
		# Clear of the station, which is a contact too.
		drone = _spawn(TargetDrone.Behaviour.STATIC, 900.0, Vector2(-25, 12), 100000.0)
		_fcs.cursor = Vector2(-25, 12)
		_input.cmd.lock_preview = true
		await _frames(8)
		_input.cmd.lock_commit = true
		await _frames(3)
		_input.cmd.lock_preview = false
		await _frames(60)
		_report_aim("locked", drone)
		await _shot("offaxis_locked")
		for i in 25:
			_input.cmd.rotation = Vector3(0, 1, 0)
			_input.cmd.translation = Vector3(1, 0, 0)
			_input.cmd.boost = true
			await physics_frame
		for i in 60:
			_input.cmd.translation = Vector3(1, 0, 0)
			_input.cmd.boost = true
			await physics_frame
			if i % 20 == 0:
				_report_aim("turned+%d" % i, drone)
		var to := _suit.global_basis.orthonormalized().inverse() * (drone.global_position - _fcs.get_view_origin())
		var angles := SpatialMath.direction_to_angles(to.normalized())
		_look(angles.x, angles.y, 40.0)
		await _shot("offaxis_turned")
		await _fire_sequence("offaxis_fire", 6)
		_report_aim("after", drone)
		_look(0, 0)
	quit()


## Lead, gun and target directions from the sensor head, and where a shot fired now would
## pass the target (straight-line flight, the drone at its current velocity).
func _report_aim(tag: String, drone: TargetDrone) -> void:
	var w := _fcs.selected
	if w == null:
		print("AIM %s: no weapon" % tag)
		return
	var eye := _fcs.get_view_origin()
	var body := _suit.global_basis.orthonormalized()
	var gun := body * SpatialMath.angles_to_direction(w.aim)
	var target := (drone.global_position - eye).normalized()
	var lead := (w.lead_point - eye).normalized()
	var muzzle := w.get_muzzle_position()
	var shot_v := _fcs.get_own_velocity() + gun * w.projectile.speed
	var rel_p := muzzle - drone.global_position
	var rel_v := shot_v - drone.get_velocity()
	var t := maxf(-rel_p.dot(rel_v) / rel_v.length_squared(), 0.0)
	var miss := (rel_p + rel_v * t).length()
	print("AIM %-10s valid %s env %s on %s | lead↔target %.2f° gun↔lead %.2f° | miss %.1f m | own v %.0f m/s, target az/el %s" % [
		tag, w.solution_valid, w.target_in_envelope, w.on_target, rad_to_deg(lead.angle_to(target)),
		rad_to_deg(gun.angle_to(lead)), miss, _fcs.get_own_velocity().length(),
		SpatialMath.direction_to_angles(body.inverse() * target)])
	print("    locked %s (drone %s) | fcs target pos−drone %.1f m | fcs target v %s, drone v %s | aim %s lead_angles %s | lead_point−drone %.1f m" % [
		_fcs.locked, drone, (_fcs.get_target_position() - drone.global_position).length(), _fcs.get_target_velocity(),
		drone.get_velocity(), w.aim, w.lead_angles, (w.lead_point - drone.global_position).length()])


## Fires the selected weapon once and saves the next `count` frames, `every` frames apart.
## A beam is held through its spool (saving the charge half-way and nearly done).
func _fire_sequence(tag: String, count: int, every := 1) -> void:
	var w := _fcs.selected
	for i in 600:
		if w == null or w.can_fire():
			break
		await physics_frame
	var before := w.ammo if w != null else 0
	_input.cmd.fire_main = true
	if w != null and w.projectile != null and w.projectile.spool_time > 0.0:
		var saved := 0
		for i in 600:
			if w.ammo != before:
				break
			await physics_frame
			if saved == 0 and w.get_spool_fraction() > 0.5:
				saved = 1
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_spool_a.png" % [_out, tag])
			elif saved == 1 and w.get_spool_fraction() > 0.9:
				saved = 2
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_spool_b.png" % [_out, tag])
	else:
		await physics_frame
		await physics_frame
	_input.cmd.fire_main = false
	for i in count:
		for k in every:
			await process_frame
			if _sweep != null:
				_sweep.aim_override = _sweep.aim + Vector2(-1.2, 0.5)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%02d.png" % [_out, tag, i])


func _look(yaw_right_deg: float, pitch_deg: float, fov := 0.0) -> void:
	_fp.set_look_rotation(Basis(Vector3.UP, deg_to_rad(-yaw_right_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg)))
	if fov > 0.0:
		_fp.fov = fov
	else:
		_fp.fov = 75.0


func _ext_view(eye: Vector3, target: Vector3) -> void:
	_ext.transform = Transform3D(Basis.IDENTITY, eye).looking_at(target, Vector3.UP)


func _spawn(behaviour: TargetDrone.Behaviour, distance: float, angles: Vector2, hp: float) -> TargetDrone:
	var drone := TargetDrone.new()
	drone.behaviour = behaviour
	drone.quarry = _suit
	drone.hit_points = hp
	drone.velocity = _suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(angles) * distance
	return drone


func _shot(file: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, file])


## Waits in simulated time (physics ticks), so weapon cycle times hold at any frame rate.
func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame
