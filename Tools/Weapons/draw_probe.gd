extends SceneTree

## Headless check of the rifle's stow / draw and its low ready on the RX-93: starts on the
## rear skirt, DGFT draws it (the SOI goes to the panoramic screen), it is held low with
## the arm free, the trigger brings it up on the boresight and the shot leaves once it is
## up, a lock brings it up, NAV stows it. Prints how much the draw turns the suit.
##
##   godot-double --headless --path . -s Tools/Weapons/draw_probe.gd

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.fire_main = out.fire_main
		return out

var _suit: RigidBody3D
var _fcs: FireControl
var _loadout: MsLoadout
var _ambac: AmbacController
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
	await _ticks(30)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
	var vehicle := _suit as Node as VehicleBase
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = vehicle.find_component(FireControl) as FireControl
	_fcs.sensors.enabled = false
	_loadout = vehicle.find_component(MsLoadout) as MsLoadout
	_ambac = vehicle.find_component(AmbacController) as AmbacController
	var rifle := _fcs.get_weapon(&"beam_rifle")
	var eq := rifle.equipment
	var m := eq.draw_motion

	var order := {}
	for child in _loadout.skeleton.get_children():
		order[child.get_class() if child.get_script() == null else child.get_script().get_global_name()] = child.get_index()
	print("DRAW modifiers: ", order)
	_check("draw runs after the aim and before LimbReaction", order.get(&"EquipmentDrawModifier", -1) > order.get(&"WeaponAimModifier", 99)
			and order.get(&"EquipmentDrawModifier", 99) < order.get(&"LimbReactionModifier", -1))
	_check("starts stowed on the skirt", eq.draw_progress == 0.0 and eq.get_parent().name.begins_with("Stow_"))
	_check("rifle mass rides the skirt", _loadout.get_carry(eq)[0] == m.stow_bone)
	_check("NAV: arm free for AMBAC", not _ambac.is_group_locked(&"arm_r"))

	# DGFT from the centre display: the panoramic screen's cursor takes the SOI.
	await _ticks(60)
	var w0 := _suit.angular_velocity
	var q0 := _suit.global_basis.orthonormalized().get_rotation_quaternion()
	var turned := 0.0
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _ticks(2)
	_check("DGFT takes the SOI to the HUD cursor", _fcs.soi == FireControl.Soi.HUD_CURSOR)
	_check("drawing holds the arm and waist", eq.is_drawing() and _ambac.is_group_locked(&"arm_r") and _ambac.is_group_locked(&"torso"))
	var peak := 0.0
	var grabbed_at := -1
	var drawn_at := -1
	var total := ceili((m.reach_time + m.draw_time) * Engine.physics_ticks_per_second) + 20
	for i in total:
		await _ticks(1)
		var dw := _suit.global_basis.orthonormalized().inverse() * (_suit.angular_velocity - w0)
		peak = maxf(peak, rad_to_deg(dw.length()))
		var q := _suit.global_basis.orthonormalized().get_rotation_quaternion()
		turned = maxf(turned, rad_to_deg(q0.angle_to(q)) - rad_to_deg(w0.length()) * (i + 1) / 60.0)
		if i % 6 == 0:
			print("DRAW t %.2f p %.2f body rate (deg/s, body) %s" % [i / 60.0, eq.draw_progress, (dw * 57.3).snapped(Vector3.ONE * 0.1)])
		if grabbed_at < 0 and eq.is_in_hand():
			grabbed_at = i
			var want: Transform3D = _loadout._hand_local[eq]
			print("DRAW grab miss %.2f m, %.1f deg" % [eq.transform.origin.distance_to(want.origin),
					rad_to_deg(eq.transform.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()))])
		if drawn_at < 0 and eq.is_drawn():
			drawn_at = i
	print("DRAW grab at %.2f s, drawn at %.2f s, peak body rate change %.2f deg/s, turned at most %.2f deg, now %.2f deg/s" % [
			grabbed_at / 60.0, drawn_at / 60.0, peak, turned, rad_to_deg((_suit.angular_velocity - w0).length())])
	_check("drawn into the hand", eq.is_drawn() and eq.get_parent().name.begins_with("Mount_"))
	_check("rifle mass rides the hand", _loadout.get_carry(eq)[0] == eq.mount_bone)
	_check("draw barely turns the suit (< 2°)", turned < 2.0)
	await _ticks(30)
	_check("held low: not raised, pose rifle_low", rifle.readiness == 0.0 and eq.active_pose == &"rifle_low")
	_check("low ready: arm free for AMBAC", not _ambac.is_group_locked(&"arm_r"))

	# Trigger with nothing locked: up on the boresight, the shot leaves once it is up.
	_input.cmd.master_arm = 1
	await _ticks(2)
	var ammo := rifle.ammo
	_input.cmd.fire_main = true
	var shot_at := -1
	var spool_started := -1
	for i in 60:
		await _ticks(1)
		if spool_started < 0 and rifle.is_spooling():
			spool_started = i
		if rifle.ammo < ammo:
			shot_at = i
			break
	print("DRAW trigger from low: spool from tick %d, shot at %.2f s, aim %s" % [spool_started, shot_at / 60.0, rifle.aim])
	_check("spool starts while coming up", spool_started >= 0 and spool_started <= 2)
	_check("shot leaves once up (≤ 0.5 s)", shot_at > 0 and shot_at <= 30)
	_check("aimed at the boresight", rifle.aim.distance_to(rifle.boresight) < 0.5)
	_input.cmd.fire_main = false
	await _ticks(10)
	_check("stays up after the shot", rifle.readiness >= 1.0)
	await _ticks(ceili((rifle.raise_hold_time + rifle.ready_time) * 60.0) + 60)
	_check("back to low ready after the hold", rifle.readiness == 0.0)

	# A lock brings it up.
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.STATIC
	_suit.get_parent().add_child(drone)
	drone.global_position = _suit.global_position + _suit.global_basis.orthonormalized() * SpatialMath.angles_to_direction(Vector2(10, 0)) * 1500.0
	await _ticks(5)
	_fcs.lock(drone)
	await _ticks(40)
	_check("lock raises it onto the target", rifle.readiness >= 1.0 and rifle.on_target)
	_fcs.lock(null)

	# HMCS kept on entering DGFT.
	_input.cmd.master_mode = FireControl.MasterMode.NAV
	await _ticks(2)
	_check("NAV stows: drawing back", eq.hand_wanted == false and eq.is_drawing())
	await _ticks(ceili((m.reach_time + m.draw_time) * 60.0) + 20)
	_check("back on the skirt", eq.draw_progress == 0.0 and eq.get_parent().name.begins_with("Stow_"))
	_check("rifle mass back on the skirt", _loadout.get_carry(eq)[0] == m.stow_bone)
	_fcs.select_soi(FireControl.Scs.FORWARD)
	if _fcs.soi != FireControl.Soi.HMCS:
		_fcs.select_soi(FireControl.Scs.FORWARD)
	_check("HMCS selected", _fcs.soi == FireControl.Soi.HMCS)
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _ticks(2)
	_check("DGFT keeps the HMCS", _fcs.soi == FireControl.Soi.HMCS)
	# Reversing halfway: back to the skirt without a jump.
	await _ticks(20)
	_input.cmd.master_mode = FireControl.MasterMode.NAV
	await _ticks(ceili(m.reach_time * 60.0) + 10)
	_check("reversed before the grab: back on the skirt", eq.draw_progress == 0.0 and not eq.is_in_hand())

	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(what: String, ok: bool) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		_failures += 1


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
