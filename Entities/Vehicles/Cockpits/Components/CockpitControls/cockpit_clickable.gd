class_name CockpitClickable
extends Node3D

## Something in the cockpit the pilot can click in click mode (CockpitClickMode):
## a switch, a guard, a button. Picked by the cursor ray passing within pick_radius
## of this node; left click = direction −1, right click = +1.

const GROUP := &"cockpit_clickables"

signal clicked(direction: int)

@export var pick_radius: float = 0.02
## Shown next to the cursor while hovered.
@export var tooltip: String = ""

var hovered := false


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## Override to react; default emits `clicked`.
func click(direction: int) -> void:
	clicked.emit(direction)


func set_hover(value: bool) -> void:
	hovered = value
	_on_hover_changed()


## Override: show the hover state (e.g. light the lever).
func _on_hover_changed() -> void:
	pass


## Where the cursor ray is measured to (interpolated, so it matches what's drawn).
func get_pick_position() -> Vector3:
	return get_global_transform_interpolated().origin
