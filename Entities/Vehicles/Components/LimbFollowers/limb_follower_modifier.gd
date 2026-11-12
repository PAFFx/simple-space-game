class_name LimbFollowerModifier
extends SkeletonModifier3D

## Applies LimbFollowers' rotations after animation. Created at runtime.

var followers: LimbFollowers


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or followers == null:
		return
	var rotations := followers.get_bone_rotations()
	for bone_name: StringName in rotations:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var g := skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
		var q: Quaternion = rotations[bone_name]
		skel.set_bone_pose_rotation(idx, skel.get_bone_pose_rotation(idx) * (g.inverse() * q * g))
