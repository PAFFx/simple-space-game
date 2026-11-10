class_name HudSilhouette
extends Node3D

## Outline of a nearby object drawn on the panoramic HUD instead of the object
## itself, e.g. a shield the sensor sees "through" (SilhouetteWidget draws it).

const GROUP := &"hud_silhouettes"

## Outline points in this node's local space.
@export var outline := PackedVector3Array()
@export var closed: bool = true
@export var label: String = ""


func _ready() -> void:
	add_to_group(GROUP)


func get_world_outline() -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in outline:
		out.append(global_transform * p)
	return out
