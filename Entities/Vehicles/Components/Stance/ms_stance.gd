class_name MsStance
extends Resource

## A committed limb pose for a kind of movement (e.g. climbing: legs forward, knees
## bent, so the soles balance the backpack). Chosen while the suit pushes along
## `direction`; poses only the AMBAC joints listed here, and only in free groups.

@export var stance_name: StringName = &""
## Movement direction this stance is for, pilot frame (+X right, +Y up, −Z forward).
@export var direction := Vector3.UP
## Chosen while the push is within this angle of `direction`, deg.
@export var cone_deg: float = 45.0
## Joint targets: bones[k] rotated about axes[k] (skeleton space, as in AmbacJoint) by
## angles_deg[k], relative to the animated pose.
@export var bones: PackedStringArray = []
@export var axes: PackedVector3Array = []
@export var angles_deg: PackedFloat32Array = []
## Pose change time for this stance, s (0 = the controller's transition_time). A quick
## swing kicks the body harder (the limbs' reaction).
@export var transition_time: float = 0.0
