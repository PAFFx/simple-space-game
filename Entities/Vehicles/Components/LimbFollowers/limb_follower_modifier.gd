class_name LimbFollowerModifier
extends SkeletonModifier3D

## Applies LimbFollowers' rotations after animation, AMBAC and weapon aim (pose followers
## read the final pose): it keeps itself just before LimbReactionModifier, which must stay
## last, or last when there is none. Created at runtime.

var followers: LimbFollowers


func _enter_tree() -> void:
	var skel := get_parent()
	if skel != null and not skel.child_order_changed.is_connected(_keep_late):
		skel.child_order_changed.connect(_keep_late)


func _keep_late() -> void:
	var skel := get_parent()
	if skel == null:
		return
	var last := skel.get_child(skel.get_child_count() - 1)
	var want := skel.get_child_count() - (2 if last is LimbReactionModifier and last != self else 1)
	if get_index() != want:
		skel.move_child.call_deferred(self, want)


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or followers == null:
		return
	var rotations := followers.get_bone_rotations(skel)
	for bone_name: StringName in rotations:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var g := skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
		var q: Quaternion = rotations[bone_name]
		skel.set_bone_pose_rotation(idx, skel.get_bone_pose_rotation(idx) * (g.inverse() * q * g))
