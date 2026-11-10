class_name HatchPanel
extends Resource

## One moving hatch panel driven by a skeleton bone.

@export var bone_name: StringName
## Hinge axis in SKELETON space (independent of the bone's own local axes).
@export var hinge_axis := Vector3.RIGHT
@export var open_angle_deg: float = 100.0
## Portion of the hatch timeline [0, 1] during which this panel moves.
@export var window := Vector2(0.0, 1.0)
