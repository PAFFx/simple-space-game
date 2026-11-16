class_name AmbacJoint
extends Resource

## One AMBAC degree of freedom: a limb swinging about an axis.
## Accelerating the limb by α pushes the body back with torque −inertia·α·axis.

@export var bone_name: StringName = &""
## Rotation axis in skeleton space at rest (= body frame for an unrotated model).
@export var axis := Vector3.RIGHT
## Joints sharing a group are locked together, e.g. by equipment in use.
@export var group: StringName = &""
## Limb moment of inertia about the joint axis, kg·m².
@export var inertia: float = 50000.0
## Travel either side of the animated pose. Asymmetric for hinges that only bend one
## way (knees, elbows): e.g. min -35, max +8.
@export var min_angle_deg: float = -30.0
@export var max_angle_deg: float = 30.0
@export var max_rate_deg: float = 90.0
@export var max_accel_deg: float = 400.0
## Actuator torque rating, N·m (0 = only max_accel_deg limits it). A heavier limb (a full
## tank, equipment) swings slower on the same actuator: acceleration ≤ max_torque / inertia.
@export var max_torque: float = 0.0
## Relative willingness to move this joint (0 = never used for balancing).
@export_range(0.0, 1.0) var priority: float = 1.0


## Angular acceleration limit now, rad/s²: the joint's own, or what its actuator can give
## the limb's inertia, whichever is lower.
func get_max_accel() -> float:
	var a := deg_to_rad(max_accel_deg)
	if max_torque > 0.0 and inertia > 0.0:
		a = minf(a, max_torque / inertia)
	return a
