class_name ThrusterGuard
extends Resource

## One movable thruster part: a nozzle or pod that turns with its thruster's gimbal (full
## rotation), a plate that swings about `axis` to follow it, or a cover that opens out of
## the way while its nozzle is swung and closes when it's back (open_angle_deg != 0).

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
## Full rotation: low-pass on the followed aim, s, so a pod carrying several nozzles
## moves steadily instead of flapping with every small re-aim.
@export var smoothing_time: float = 0.15
@export var min_angle_deg: float = -40.0
@export var max_angle_deg: float = 40.0

@export_group("Cover")
## Cover mode when non-zero: opens to this angle about `axis` (its sign is the outward
## side) while the nozzle is swung more than open_above_deg, and closes once the nozzle has
## been back under close_below_deg for close_delay seconds. Never moves the other way.
@export var open_angle_deg: float = 0.0
@export var open_above_deg: float = 3.0
@export var close_below_deg: float = 1.5
@export var close_delay: float = 0.6
@export var open_rate_deg: float = 150.0
@export var close_rate_deg: float = 60.0
