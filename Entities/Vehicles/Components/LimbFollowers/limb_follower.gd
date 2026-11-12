class_name LimbFollower
extends Resource

## One armor part that moves with a limb joint, e.g. a skirt plate lifting as its thigh
## swings forward: `bone` turns about `axis` (skeleton space) by the source AMBAC joint's
## angle times `positive` (when the joint angle is > 0) or `negative` (< 0).

@export var bone_name: StringName = &""
@export var axis := Vector3.RIGHT
## AMBAC joint followed: its bone and axis.
@export var source_bone: StringName = &""
@export var source_axis := Vector3.RIGHT
@export var positive: float = 1.0
@export var negative: float = 0.0
@export var min_angle_deg: float = -90.0
@export var max_angle_deg: float = 90.0
