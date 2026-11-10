class_name MsPoseLayer
extends Resource

## One pose blended over the base animation on a subset of bones
## (e.g. "rifle_ready" on the right arm). Driven by MsLoadout's active poses.

@export var pose: StringName = &""
@export var bones := PackedStringArray()
## Seconds to blend fully in or out.
@export var blend_time: float = 0.6
