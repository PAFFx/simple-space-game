class_name FinalPoses
extends RefCounted

## The bones' global poses as drawn: after the skeleton modifiers (AMBAC, limb reaction, aim,
## followers). Outside the skeleton's update, `get_bone_global_pose()` returns the pose before
## them, metres off for a swinging limb, so hole records, hull frames and baked debris would
## not match the mesh. One cache per skeleton, refreshed on `skeleton_updated`.

signal updated

var _skeleton: Skeleton3D
var _poses: Array[Transform3D] = []


static func of(skeleton: Skeleton3D) -> FinalPoses:
	if skeleton.has_meta(&"final_poses"):
		return skeleton.get_meta(&"final_poses")
	var fp := FinalPoses.new()
	fp._skeleton = skeleton
	skeleton.set_meta(&"final_poses", fp)
	skeleton.skeleton_updated.connect(fp._capture)
	return fp


## `bone`'s global pose (skeleton space) as last drawn; before the first update, the live one.
func pose(bone: int) -> Transform3D:
	if bone >= 0 and bone < _poses.size():
		return _poses[bone]
	return _skeleton.get_bone_global_pose(bone)


func _capture() -> void:
	var n := _skeleton.get_bone_count()
	if _poses.size() != n:
		_poses.resize(n)
	for i in n:
		_poses[i] = _skeleton.get_bone_global_pose(i)
	updated.emit()
