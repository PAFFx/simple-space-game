class_name AmbacModifier
extends SkeletonModifier3D

## Applies the AMBAC limb offsets on top of whatever the animation set this
## frame. Created at runtime by AmbacController under the skeleton.

var controller: AmbacController

var _cache := {}  ## bone name → [index, global rest rotation]


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or controller == null:
		return
	var rotations := controller.get_bone_rotations()
	for bone_name: StringName in rotations:
		if not _cache.has(bone_name):
			var idx := skel.find_bone(bone_name)
			if idx < 0:
				continue
			_cache[bone_name] = [idx, skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()]
		var entry: Array = _cache[bone_name]
		var g: Quaternion = entry[1]
		var q_skel: Quaternion = rotations[bone_name]
		# Skeleton-space rotation re-expressed in the bone's local frame.
		var pose := skel.get_bone_pose_rotation(entry[0])
		skel.set_bone_pose_rotation(entry[0], pose * (g.inverse() * q_skel * g))
