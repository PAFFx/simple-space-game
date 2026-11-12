class_name ThrusterGuard
extends Resource

## One movable thruster part: a nozzle that turns with its thruster's gimbal (full
## rotation), or a guard plate that swings about `axis` to follow its nozzle.

@export var bone_name: StringName = &""
## Thruster node names whose (averaged) deflection the guard follows.
@export var thrusters: PackedStringArray = []
## Follow the nozzle's full aim (a nozzle on a ball joint) instead of one hinge axis.
@export var full_rotation: bool = false
## Thrust direction the modelled nozzle points at rest (skeleton space), if it differs
## from its thruster's nominal direction. Zero = the same.
@export var rest_thrust := Vector3.ZERO
## Hinge axis in skeleton space at rest (hinge mode).
@export var axis := Vector3.RIGHT
## Share of the nozzle deflection the guard follows (1 = moves with the nozzle).
@export var follow: float = 1.0
@export var min_angle_deg: float = -40.0
@export var max_angle_deg: float = 40.0
