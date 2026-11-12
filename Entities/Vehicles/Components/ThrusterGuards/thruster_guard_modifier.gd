class_name ThrusterGuardModifier
extends SkeletonModifier3D

## Applies ThrusterGuards' angles to their bones after animation. Created at runtime.

var guards: ThrusterGuards


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or guards == null:
		return
	for i in guards.guards.size():
		var g := guards.guards[i]
		var idx := skel.find_bone(g.bone_name)
		if idx < 0:
			continue
		var rest_global := skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
		var q_skel := guards.rotation_of(i)
		var pose := skel.get_bone_pose_rotation(idx)
		skel.set_bone_pose_rotation(idx, pose * (rest_global.inverse() * q_skel * rest_global))
