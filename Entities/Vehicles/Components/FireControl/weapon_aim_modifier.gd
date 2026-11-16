class_name WeaponAimModifier
extends SkeletonModifier3D

## Makes the model point its weapons where FireControl aims them, on top of the pose
## animation and AMBAC: the torso twists a little toward the selected weapon's aim, each
## of the weapon's assist joints (collarbone, wrist) takes its share of the turn, then its
## `aim_bone` (shoulder, neck) turns by whatever still takes the muzzle from where the pose
## left it onto its aim. Created at runtime by FireControl.

var fire_control: FireControl

# MsWeapon → [aim bone, carrying bone, muzzle in carrying bone, assist bones]
var _entries := {}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or fire_control == null:
		return
	var body := fire_control.get_body()
	if body == null:
		return
	var skel_from_body := (body.global_basis.orthonormalized().inverse() * skel.global_basis.orthonormalized()).inverse()

	var twist := fire_control.get_torso_yaw()
	if absf(twist) > 0.01:
		var spine := skel.find_bone(fire_control.torso_bone)
		if spine >= 0:
			# Azimuth + is to the right: a negative turn about up.
			_turn(skel, spine, Quaternion(skel_from_body * Vector3.UP, -deg_to_rad(twist)))

	for weapon: MsWeapon in fire_control.get_aimed_weapons():
		if weapon.aim_weight <= 0.001:
			continue
		var entry := _entry(skel, weapon)
		if entry.is_empty():
			continue
		var to := (skel_from_body * SpatialMath.angles_to_direction(weapon.aim)).normalized()
		var w := smoothstep(0.0, 1.0, weapon.aim_weight)
		_extend_elbow(skel, weapon, w)
		var assists: PackedInt32Array = entry[3]
		for k in assists.size():
			var share := weapon.aim_assist_shares[k] if k < weapon.aim_assist_shares.size() else 0.0
			var limit := weapon.aim_assist_limits_deg[k] if k < weapon.aim_assist_limits_deg.size() else 180.0
			var arc := _arc(skel, entry, to)
			var angle := minf(arc.get_angle() * share, deg_to_rad(limit))
			if angle > 1e-4:
				_turn(skel, assists[k], Quaternion(arc.get_axis().normalized(), angle * w))
		var rest := _arc(skel, entry, to)
		_turn(skel, entry[0], Quaternion.IDENTITY.slerp(rest, w))


## Opens the weapon's elbow with how far the aim is off its boresight.
func _extend_elbow(skel: Skeleton3D, weapon: MsWeapon, w: float) -> void:
	if weapon.elbow_extend_deg <= 0.0 or weapon.elbow_bone == &"":
		return
	var bone := skel.find_bone(weapon.elbow_bone)
	if bone < 0:
		return
	var off := rad_to_deg(SpatialMath.angles_to_direction(weapon.aim).angle_to(
			SpatialMath.angles_to_direction(weapon.boresight)))
	var k := smoothstep(weapon.elbow_extend_from_deg, weapon.elbow_extend_full_deg, off)
	if k <= 0.0:
		return
	var g := skel.get_bone_global_rest(bone).basis.get_rotation_quaternion()
	var q := Quaternion(weapon.elbow_axis.normalized(), -deg_to_rad(weapon.elbow_extend_deg) * k * w)
	skel.set_bone_pose_rotation(bone, skel.get_bone_pose_rotation(bone) * (g.inverse() * q * g))


## Skeleton-space rotation taking the muzzle's current direction onto `to`.
func _arc(skel: Skeleton3D, entry: Array, to: Vector3) -> Quaternion:
	var muzzle: Transform3D = skel.get_bone_global_pose(entry[1]) * (entry[2] as Transform3D)
	var from := -muzzle.basis.z.normalized()
	if from.dot(to) > 0.999999:
		return Quaternion.IDENTITY
	return Quaternion(from, to)


## Turns a bone by a skeleton-space rotation, about its own origin.
func _turn(skel: Skeleton3D, bone: int, rotation: Quaternion) -> void:
	var parent := skel.get_bone_parent(bone)
	var parent_rot := Quaternion.IDENTITY
	if parent >= 0:
		parent_rot = skel.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	skel.set_bone_pose_rotation(bone, parent_rot.inverse() * rotation * parent_rot * skel.get_bone_pose_rotation(bone))


func _entry(skel: Skeleton3D, weapon: MsWeapon) -> Array:
	if _entries.has(weapon):
		return _entries[weapon]
	var entry := []
	var aim_bone := skel.find_bone(weapon.aim_bone)
	# The BoneAttachment3D the weapon hangs from.
	var attach: Node = weapon
	while attach != null and not attach is BoneAttachment3D:
		attach = attach.get_parent()
	if aim_bone >= 0 and attach != null:
		var carrier := skel.find_bone((attach as BoneAttachment3D).bone_name)
		var muzzle := weapon.muzzles[0]
		var assists := PackedInt32Array()
		for bone_name in weapon.aim_assist_bones:
			var idx := skel.find_bone(bone_name)
			if idx >= 0:
				assists.append(idx)
			else:
				push_warning("WeaponAimModifier: no assist bone '%s' for %s" % [bone_name, weapon.name])
		entry = [aim_bone, carrier,
				(attach as Node3D).global_transform.affine_inverse() * muzzle.global_transform, assists]
	else:
		push_warning("WeaponAimModifier: can't aim %s (bone '%s')" % [weapon.name, weapon.aim_bone])
	_entries[weapon] = entry
	return entry
