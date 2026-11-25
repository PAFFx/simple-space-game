class_name MsEquipment
extends Node3D

## Hand-held or arm-mounted mobile suit equipment (rifle, shield, ...).
##
## Equipment is modelled and stored separately from the suit. An MsLoadout on
## the suit mounts it on a skeleton bone and toggles it with `input_action`.
## While active it plays `active_pose` on the suit and occupies `ambac_group`,
## so that limb is not used for AMBAC balancing.
##
## With a `draw_motion` it lives on its stow point (rifle on the rear skirt) until drawn:
## MsLoadout moves it there and back with the arm. In the hand and not in use it takes
## `held_pose`, which leaves the limb free for AMBAC.

signal active_changed(is_active: bool)

@export var equipment_name: String = ""
@export var mass: float = 2000.0                   ## kg, added to the suit
@export_group("Mount")
@export var mount_bone: StringName = &""
## The damage part that carries it while stowed, when that isn't the mount bone's own part
## (the fin funnels hang from the backpack bone but sit on the left main pod): it goes with it.
@export var damage_part: StringName = &""
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
## Pose while in the hand and not in use (rifle held low). Its limb stays free for AMBAC.
@export var held_pose: StringName = &""
## How it is stowed on the suit and drawn from there. Null: always in the hand.
@export var draw_motion: MsDrawMotion

var active: bool = false
## False while stowed off the suit (MsLoadout.set_equipped): hidden, massless, unusable.
var equipped: bool = true
## The limb it is on can't be controlled (DamageModel: cut off, or its joint shot): it can't
## be used, raised or drawn.
var disabled := false
## Draw progress (MsLoadout): 0 = stowed, 1 = the hand takes it, 2 = held.
var draw_progress := 0.0
## Wanted in the hand (FireControl sets it); MsLoadout draws or stows it to match.
var hand_wanted := false


func _ready() -> void:
	active = start_active
	# Drawn on the panoramic screen with the body in a weapons mode, unless it is shown
	# there as an outline only (shield, funnels: the real thing would block the view).
	var outlined := find_children("*", "", true, false).any(func(n: Node) -> bool: return n is SensorOutline)
	_set_layers(self, Layers.VEHICLE_EXT | (0 if outlined else Layers.SENSOR_BODY_PARTS))


func set_active(value: bool) -> void:
	value = value and equipped and not disabled
	if value == active:
		return
	active = value
	active_changed.emit(active)


func toggle() -> void:
	set_active(not active)


## In the hand (also halfway through a draw or stow), or always for equipment without a
## stow point.
func is_in_hand() -> bool:
	return draw_motion == null or draw_progress >= 1.0


## Fully drawn: usable.
func is_drawn() -> bool:
	return draw_motion == null or draw_progress >= 2.0


func is_drawing() -> bool:
	return draw_motion != null and draw_progress > 0.0 and draw_progress < 2.0


## Whether it holds its limb (out of AMBAC): in use, or on its way in or out.
func occupies_limb() -> bool:
	if is_drawing():
		return true
	return active and (held_pose == &"" or active_pose != held_pose)


func get_display_name() -> String:
	return equipment_name if equipment_name != "" else String(name)


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)
