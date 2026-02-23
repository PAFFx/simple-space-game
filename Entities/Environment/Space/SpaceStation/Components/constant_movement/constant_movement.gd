class_name ConstantMovement
extends Node

@export var move_direction: Vector3 = Vector3(0, 0, 0)
@export var move_speed: float = 1.0

@onready var target_component : Node3D = get_parent()

func _process(delta: float) -> void:
	var move_dir := move_direction.normalized()
	var step := move_speed * move_dir * delta

	target_component.translate(step)
