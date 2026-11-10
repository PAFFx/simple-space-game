class_name MsEquipment
extends Node3D

## Hand-held or arm-mounted mobile suit equipment (rifle, shield, ...).
##
## Equipment is modelled and stored separately from the suit. An MsLoadout on
## the suit mounts it on a skeleton bone and toggles it with `input_action`.
## While active it plays `active_pose` on the suit and occupies `ambac_group`,
## so that limb is not used for AMBAC balancing.

signal active_changed(is_active: bool)

@export var equipment_name: String = ""
@export var mass: float = 2000.0                   ## kg, added to the suit
@export_group("Mount")
@export var mount_bone: StringName = &""
## Equipment transform in the suit's body frame with the skeleton at rest.
@export var mount_transform := Transform3D.IDENTITY
@export_group("Use")
## Toggles active (e.g. rifle ready / shield guard). Empty = never active.
@export var input_action: StringName = &""
## Pose (MsPoseAnimator layer) played while active.
@export var active_pose: StringName = &""
## AMBAC joint group this equipment occupies while active.
@export var ambac_group: StringName = &""
@export var start_active: bool = false

var active: bool = false


func _ready() -> void:
	active = start_active
	_set_layers(self, Layers.VEHICLE_EXT)


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	active_changed.emit(active)


func toggle() -> void:
	set_active(not active)


func get_display_name() -> String:
	return equipment_name if equipment_name != "" else String(name)


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)
