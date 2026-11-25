class_name MsLoadout
extends Node3D

## Mounts the MsEquipment children on the suit skeleton (each on its own
## BoneAttachment3D) and toggles them with their input actions.
## Other components query it: occupied AMBAC groups, active poses.
##
## Equipment with a draw_motion also gets a stow attachment (rifle: the rear skirt) and is
## drawn into the hand when `hand_wanted` (FireControl: in a weapons mode) and stowed again
## when not: the arm reaches for it, the hand takes it, brings it round (or the reverse).
## EquipmentDrawModifier poses the arm; the parts' mass changes bone with the hand-off,
## so LimbReaction pushes the suit back for the whole motion, the equipment included.

signal equipment_changed(equipment: MsEquipment)
## An item was put on or taken off the suit (set_equipped).
signal equipment_fitted(equipment: MsEquipment, equipped: bool)

@export var skeleton: Skeleton3D
## Toggle equipment from PilotInputActions (e.g. 1 = rifle, 2 = shield).
@export var listen_for_input: bool = true

var equipment: Array[MsEquipment] = []
var _hand_attach := {}      ## MsEquipment → BoneAttachment3D in the hand
var _stow_attach := {}      ## MsEquipment → BoneAttachment3D on its stow point
var _hand_local := {}       ## MsEquipment → its transform on the hand attachment
var _stow_frame := {}       ## MsEquipment → body frame (rest) into its stow attachment's
var _arms := {}             ## MsEquipment → its StowArm
var _keys := {}             ## MsEquipment → [bone → pose rotation] per draw key
var _settling := {}         ## MsEquipment → [from transform, seconds in]
var _skel_from_body := Transform3D.IDENTITY
var _reaction: LimbReaction
var _followers: LimbFollowers
var _ambac: AmbacController
var _thruster_saved := {}   ## Thruster → [pitch limit, pitch bias] while narrowed


func _ready() -> void:
	PilotInputActions.ensure_defaults()
	if skeleton == null:
		push_error("MsLoadout: skeleton not assigned")
		return
	for child in get_children():
		if child is MsEquipment:
			_mount(child as MsEquipment)
	var vehicle := VehicleBase.find_vehicle(self)
	var fc := vehicle.find_component(FlightComputer) as FlightComputer if vehicle else null
	if fc != null:
		fc.add_payload_mass(get_total_mass())
	_reaction = vehicle.find_component(LimbReaction) as LimbReaction if vehicle else null
	_followers = vehicle.find_component(LimbFollowers) as LimbFollowers if vehicle else null
	_ambac = vehicle.find_component(AmbacController) as AmbacController if vehicle else null
	for eq: MsEquipment in _stow_attach:
		_limit_legs(eq)
	if not _stow_attach.is_empty():
		var modifier := EquipmentDrawModifier.new()
		modifier.name = "EquipmentDrawModifier"
		modifier.loadout = self
		skeleton.add_child(modifier)


func _process(delta: float) -> void:
	for eq: MsEquipment in _settling.keys():
		var entry: Array = _settling[eq]
		entry[1] += delta
		var k := smoothstep(0.0, 1.0, entry[1] / maxf(eq.draw_motion.settle_time, 0.01))
		var to: Transform3D = _hand_local[eq] if eq.is_in_hand() else stowed_local(eq)
		eq.transform = (entry[0] as Transform3D).interpolate_with(to, k)
		if k >= 1.0:
			_settling.erase(eq)
	for eq: MsEquipment in _stow_attach:
		if not eq.is_in_hand() and not _settling.has(eq):
			eq.transform = stowed_local(eq)
		_update_arm(eq)
	if not listen_for_input:
		return
	for eq in equipment:
		if eq.input_action != &"" and InputMap.has_action(eq.input_action) \
				and Input.is_action_just_pressed(eq.input_action):
			eq.toggle()


## Equipment whose stow point is gone (DamageModel: its manipulator or the part it is on was
## shot off): it can't be stowed any more, it stays in the hand.
var stow_lost := {}


func set_stow_lost(eq: MsEquipment, lost: bool) -> void:
	if lost:
		stow_lost[eq] = true
	else:
		stow_lost.erase(eq)


## Whether `eq` can be stowed (it has a stow point and that is still there).
func can_stow(eq: MsEquipment) -> bool:
	return _stow_attach.has(eq) and not stow_lost.has(eq)


## Draws or stows the equipment that has a stow point, toward `hand_wanted`.
func _physics_process(delta: float) -> void:
	if draw_frozen:
		return
	for eq: MsEquipment in _stow_attach:
		if stow_lost.has(eq) and eq.draw_progress > 0.0:
			eq.hand_wanted = true   # nowhere to put it: it stays in the hand
		var goal := 2.0 if eq.hand_wanted and eq.equipped else 0.0
		var p := eq.draw_progress
		if p == goal:
			continue
		var m := eq.draw_motion
		var going_up := goal > p
		var in_reach := p < 1.0 or (p == 1.0 and not going_up)
		var rate := 1.0 / maxf(m.reach_time if in_reach else m.draw_time, 0.01)
		var next := move_toward(p, goal, rate * delta)
		# Don't carry the reach's rate past the grab, nor the draw's below it.
		if going_up and p < 1.0:
			next = minf(next, 1.0)
		elif not going_up and p > 1.0:
			next = maxf(next, 1.0)
		eq.draw_progress = next
		_hold_followers(eq)
		_limit_legs(eq)
		_narrow_thrusters(eq)
		if p < 1.0 and next >= 1.0:
			_hand_over(eq, true)
		elif p >= 1.0 and next < 1.0:
			_hand_over(eq, false)
		elif next < 1.0 and _reaction != null and not m.present_keys.is_empty():
			# Carried by the stow arm: its mass moves with it (the move is motion).
			_reaction.move_part(eq.name, stowed_local(eq), local_box(eq))


## Holds the draw at `progress` (0..2) instead of playing it (tools: stills of the motion).
var draw_frozen := false


## Sets eq's draw progress directly, changing hands if it crosses the grab (tools).
func set_draw_progress(eq: MsEquipment, progress: float) -> void:
	if not _stow_attach.has(eq):
		return
	var was := eq.is_in_hand()
	eq.draw_progress = clampf(progress, 0.0, 2.0)
	if eq.is_in_hand() != was:
		_hand_over(eq, eq.is_in_hand())
	_settling.erase(eq)
	eq.transform = _hand_local[eq] if eq.is_in_hand() else stowed_local(eq)


## Keeps the legs off eq while it is on its stow point (MsDrawMotion.stowed_leg_limits) and
## while it is drawn or stowed (drawing_leg_limits).
func _limit_legs(eq: MsEquipment) -> void:
	if _ambac == null:
		return
	_apply_leg_limits(eq.name + "_stow", eq.draw_motion.stowed_leg_limits, not eq.is_in_hand())
	_apply_leg_limits(eq.name + "_draw", eq.draw_motion.drawing_leg_limits, eq.is_drawing())


## Narrows (or gives back) the thrusters' swing that drawing_thruster_swing lists while eq
## is drawn or stowed.
func _narrow_thrusters(eq: MsEquipment) -> void:
	var swing: Dictionary = eq.draw_motion.drawing_thruster_swing
	if swing.is_empty():
		return
	var vehicle := VehicleBase.find_vehicle(self)
	for t_name: String in swing:
		var t := vehicle.find_child(t_name, true, false) as Thruster
		if t == null:
			continue
		if eq.is_drawing() and not _thruster_saved.has(t):
			_thruster_saved[t] = [t.gimbal_pitch_limit_deg, t.gimbal_pitch_bias_deg]
			var r: Vector2 = swing[t_name]
			t.gimbal_pitch_limit_deg = (r.y - r.x) * 0.5
			t.gimbal_pitch_bias_deg = (r.y + r.x) * 0.5
		elif not eq.is_drawing() and _thruster_saved.has(t):
			t.gimbal_pitch_limit_deg = _thruster_saved[t][0]
			t.gimbal_pitch_bias_deg = _thruster_saved[t][1]
			_thruster_saved.erase(t)


func _apply_leg_limits(prefix: String, limits: Array, on: bool) -> void:
	for k in limits.size():
		var key := StringName("%s_%d" % [prefix, k])
		if not on:
			_ambac.remove_coupled_limit(key)
			continue
		var l: Array = limits[k]
		_ambac.add_coupled_limit(key, _ambac.find_joint(l[0], l[1]), _ambac.find_joint(l[2], l[3]),
				_ambac.find_joint(l[4], l[5]), l[6], l[7])


## Holds the motion's armour followers while eq is on its way in or out.
func _hold_followers(eq: MsEquipment) -> void:
	if _followers == null:
		return
	for bone in eq.draw_motion.held_followers:
		_followers.hold_bone(bone, eq.is_drawing())


## Puts equipment straight into the hand or on its stow point (tests, spawning).
func snap_draw(eq: MsEquipment, in_hand: bool) -> void:
	if not _stow_attach.has(eq):
		return
	var was := eq.is_in_hand()
	eq.hand_wanted = in_hand
	eq.draw_progress = 2.0 if in_hand else 0.0
	if was != in_hand:
		_hand_over(eq, in_hand)
	_settling.erase(eq)
	eq.transform = _hand_local[eq] if in_hand else stowed_local(eq)


## The body frame into skeleton space.
func skel_from_body() -> Transform3D:
	return _skel_from_body


## Solved bone poses per key of eq's draw motion (EquipmentDrawModifier).
func get_draw_keys(eq: MsEquipment) -> Array:
	return _keys.get(eq, [])


## The bone eq rides now and its place in that bone's frame: [bone name, transform].
func get_carry(eq: MsEquipment) -> Array:
	if eq.is_in_hand():
		return [eq.mount_bone, _hand_local.get(eq, Transform3D.IDENTITY)]
	return [eq.draw_motion.stow_bone, stowed_local(eq)]


## eq's transform on its stow attachment now: stowed, or where the stow arm has carried it.
func stowed_local(eq: MsEquipment) -> Transform3D:
	var m := eq.draw_motion
	return _stow_frame[eq] * m.get_presented(m.get_arm_progress(eq.draw_progress))


## The stow arm and its hatch for eq's draw progress. Carrying eq, the gripper holds it
## where the stow arm has brought it; once the hand has it the empty gripper backs off its
## face and goes straight back in through the hatch (and comes out that way to take it back).
func _update_arm(eq: MsEquipment) -> void:
	var arm: StowArm = _arms.get(eq)
	if arm == null:
		return
	var m := eq.draw_motion
	var p := eq.draw_progress
	var k := m.get_arm_progress(p)
	var frame: Transform3D = _stow_frame[eq]
	var in_dir := frame.basis * m.arm_in_dir
	var out_dir := frame.basis * m.arm_out_dir
	var hatch := m.get_hatch_open(p)
	if p < 1.0:
		var at: Transform3D = frame * m.get_presented(k)
		arm.set_pose(Transform3D(at.basis * m.arm_clamp_basis, at * m.arm_clamp), m.get_deploy(k),
				in_dir, out_dir, hatch)
		return
	# Empty: off the equipment's face, round to just outside the hatch, in through it.
	var grab: Transform3D = frame * m.get_grab()
	var held := Transform3D(grab.basis * m.arm_clamp_basis, grab * m.arm_clamp)
	var n := frame.basis * m.hatch_normal.normalized()
	var mouth: Vector3 = frame * m.hatch_centre
	var keys: Array[Vector3] = [held.origin, held.origin + held.basis.x.normalized() * 0.5,
			mouth + n * 1.2, mouth - n * 0.6]
	var f := 1.0 - k   # 0 at the grab … 1 folded in
	var x := smoothstep(0.0, 1.0, f) * (keys.size() - 1)
	var i := mini(int(x), keys.size() - 2)
	var at := keys[i].lerp(keys[i + 1], x - i)
	arm.set_pose(Transform3D(held.basis, at), clampf((1.0 - f) / maxf(m.deploy_share, 0.01), 0.0, 1.0) \
			if f > 1.0 - m.deploy_share else 1.0, in_dir, out_dir, hatch, f >= 0.999)


## The hand takes eq off its stow point (`to_hand`) or puts it back: it changes
## attachment where it is and slides into its exact place there.
func _hand_over(eq: MsEquipment, to_hand: bool) -> void:
	var attach: BoneAttachment3D = _hand_attach[eq] if to_hand else _stow_attach[eq]
	eq.reparent(attach, true)
	_limit_legs(eq)
	_settling[eq] = [eq.transform, 0.0]
	if _reaction != null:
		# An attachment's frame is its bone's: the equipment's local transform is its place there.
		var carry := get_carry(eq)
		_reaction.carry_part(eq.name, carry[0], carry[1], local_box(eq))


## eq's visible extent in its own frame.
static func local_box(eq: MsEquipment) -> AABB:
	var box := AABB()
	var first := true
	var inv := eq.global_transform.affine_inverse()
	for vi in eq.find_children("*", "VisualInstance3D", true, false):
		var b := inv * (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func get_total_mass() -> float:
	var total := 0.0
	for eq in equipment:
		if eq.equipped:
			total += eq.mass
	return total


## Puts `eq` on the suit or takes it off (test range): hidden, its mass off the suit and
## its weapons out of the fire control while it is off.
func set_equipped(eq: MsEquipment, on: bool) -> void:
	if eq.equipped == on or not equipment.has(eq):
		return
	if not on:
		eq.set_active(false)
		snap_draw(eq, false)
	eq.equipped = on
	eq.visible = on
	eq.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	var vehicle := VehicleBase.find_vehicle(self)
	var fc := vehicle.find_component(FlightComputer) as FlightComputer if vehicle else null
	if fc != null:
		fc.add_payload_mass(eq.mass if on else -eq.mass)
	equipment_fitted.emit(eq, on)


## True while equipment holds this AMBAC group: in use (MsEquipment.occupies_limb), or
## drawn / stowed with the group in its motion's held_groups (the waist leans with it).
func is_group_occupied(group: StringName) -> bool:
	for eq in equipment:
		if eq.ambac_group == group and eq.occupies_limb():
			return true
		if eq.is_drawing() and eq.draw_motion.held_groups.has(group):
			return true
	return false


## Some equipment is being drawn or stowed.
func is_drawing() -> bool:
	for eq in equipment:
		if eq.is_drawing():
			return true
	return false


## Pose name → true for every active equipment pose.
func get_active_poses() -> Dictionary:
	var poses := {}
	for eq in equipment:
		if eq.active and eq.active_pose != &"":
			poses[eq.active_pose] = true
	return poses


func _mount(eq: MsEquipment) -> void:
	var bone := skeleton.find_bone(eq.mount_bone)
	if bone < 0:
		push_error("MsLoadout: bone '%s' not found for %s" % [eq.mount_bone, eq.name])
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Mount_%s" % eq.name
	attach.bone_name = eq.mount_bone
	skeleton.add_child(attach)
	# mount_transform is in the body frame at rest; re-express it relative to the bone.
	var body := VehicleBase.find_vehicle(self)
	var skel_in_body := body.global_transform.affine_inverse() * skeleton.global_transform
	_skel_from_body = skel_in_body.affine_inverse()
	var bone_in_body := skel_in_body * skeleton.get_bone_global_rest(bone)
	eq.reparent(attach, false)
	eq.transform = bone_in_body.affine_inverse() * eq.mount_transform
	_hand_attach[eq] = attach
	_hand_local[eq] = eq.transform
	eq.active_changed.connect(func(_a: bool) -> void: equipment_changed.emit(eq))
	equipment.append(eq)
	if eq.draw_motion != null:
		_mount_stow(eq, skel_in_body)


## A stow point for eq: its attachment, and the arm's pose at every key of the draw.
func _mount_stow(eq: MsEquipment, skel_in_body: Transform3D) -> void:
	var m := eq.draw_motion
	var bone := skeleton.find_bone(m.stow_bone)
	if bone < 0 or skeleton.find_bone(m.hand_bone) < 0:
		push_error("MsLoadout: can't stow %s on '%s'" % [eq.name, m.stow_bone])
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Stow_%s" % eq.name
	attach.bone_name = m.stow_bone
	skeleton.add_child(attach)
	_stow_attach[eq] = attach
	_stow_frame[eq] = (skel_in_body * skeleton.get_bone_global_rest(bone)).affine_inverse()
	if not m.present_keys.is_empty():
		var arm := StowArm.new()
		arm.name = "StowArm_%s" % eq.name
		attach.add_child(arm)
		# The boom reaches from the hatch to the gripper's wrist wherever it goes.
		var reach := 0.0
		for i in 41:
			var at := m.get_presented(i / 40.0)
			var wrist := at * m.arm_clamp + (at.basis * m.arm_clamp_basis).x.normalized() * StowArm.PALM
			reach = maxf(reach, wrist.distance_to(m.hatch_centre))
		var frame: Transform3D = _stow_frame[eq]
		arm.build(frame * m.hatch_centre, frame.basis * m.hatch_normal, m.arm_link, reach + 0.6, m.arm_grip_span,
				Layers.VEHICLE_EXT | Layers.SENSOR_BODY_PARTS)
		# On the panoramic screen as an outline with the arms (FireControl shows it while
		# a draw or stow runs).
		var outline := SensorOutline.new()
		outline.sensor_layer = Layers.SENSOR_COMBAT
		outline.shown_by_fire_control = true
		outline.fill_alpha = 0.04
		arm.add_child(outline)
		_arms[eq] = arm
	var keys := ArmReachSolver.solve_motion(skeleton, m, eq.mount_transform, _skel_from_body)
	# Every key poses the same bones.
	for key in keys:
		for other in keys:
			for b: int in other:
				if not key.has(b):
					key[b] = skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
	_keys[eq] = keys
	eq.draw_progress = 0.0
	eq.reparent(attach, false)
	eq.transform = stowed_local(eq)
	_update_arm(eq)
