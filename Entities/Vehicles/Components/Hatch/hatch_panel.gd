class_name HatchPanel
extends Resource

## One moving hatch panel driven by a skeleton bone.

@export var bone_name: StringName
## Hinge axis in SKELETON space (independent of the bone's own local axes).
@export var hinge_axis := Vector3.RIGHT
@export var open_angle_deg: float = 100.0
## Slide when open, in SKELETON space (m), on top of the hinge (0 angle = slide only),
## e.g. a door that slides up behind the armour.
@export var slide := Vector3.ZERO
## Portion of the hatch timeline [0, 1] during which this panel moves.
@export var window := Vector2(0.0, 1.0)
