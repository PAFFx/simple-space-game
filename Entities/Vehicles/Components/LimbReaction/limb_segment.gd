class_name LimbSegment
extends Resource

## One part of the suit's mass model (LimbReaction): a bone, how heavy it is, and how
## much propellant its tank holds. Its centre and size come from the model's mesh for
## that part (a solid box of the mesh's bounds); the tank's mass sits at the same centre.

@export var bone_name: StringName
@export var mass: float = 1000.0   ## Dry, kg
## Propellant this part holds when full, kg (0 = no tank). Tanks drain together, in
## proportion, as the flight computer burns propellant.
@export var propellant_capacity: float = 0.0
## Solid volume of the part, m³ (Tools/Godot/measure_part_volumes.gd); 0 = unknown. The damage
## model takes the part's mean density from it.
@export var volume: float = 0.0
## Skinned mesh of this part under the skeleton. Empty = bone name in PascalCase
## without dots ("upper_arm.R" → "UpperArmR").
@export var mesh_name: StringName = &""
