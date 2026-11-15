class_name WeaponAimModifier
extends SkeletonModifier3D

## Makes the model point its weapons where FireControl aims them, on top of the pose
## animation and AMBAC: the torso twists a little toward the selected weapon's aim, then
## each weapon's `aim_bone` (shoulder, neck) is turned by whatever takes its muzzle from
## where the pose left it onto its aim. Created at runtime by FireControl.

var fire_control: FireControl

var _entries := {}   # MsWeapon → [aim bone, parent bone, carrying bone, muzzle in carrying bone]


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
		var muzzle: Transform3D = skel.get_bone_global_pose(entry[2]) * (entry[3] as Transform3D)
		var from := -muzzle.basis.z.normalized()
		var to := (skel_from_body * SpatialMath.angles_to_direction(weapon.aim)).normalized()
		if from.dot(to) > 0.999999:
			continue
		var arc := Quaternion(from, to)
		var w := smoothstep(0.0, 1.0, weapon.aim_weight)
		_turn(skel, entry[0], Quaternion.IDENTITY.slerp(arc, w))


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
		entry = [aim_bone, skel.get_bone_parent(aim_bone), carrier,
				(attach as Node3D).global_transform.affine_inverse() * muzzle.global_transform]
	else:
		push_warning("WeaponAimModifier: can't aim %s (bone '%s')" % [weapon.name, weapon.aim_bone])
	_entries[weapon] = entry
	return entry
