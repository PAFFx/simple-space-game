class_name LimbSegment
extends Resource

## One moving mass tracked by LimbReaction: a bone and how heavy it is. Its centre and
## size come from the model's mesh for that part (a solid box of the mesh's bounds).

@export var bone_name: StringName
@export var mass: float = 1000.0   ## kg
## Skinned mesh of this part under the skeleton. Empty = bone name in PascalCase
## without dots ("upper_arm.R" → "UpperArmR").
@export var mesh_name: StringName = &""
