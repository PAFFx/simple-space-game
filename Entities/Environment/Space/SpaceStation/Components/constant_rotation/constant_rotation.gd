class_name ConstantRotation
extends Node

enum Axis { X, Y, Z }
enum Direction { POSITIVE = 1, NEGATIVE = -1 }

@export var rotation_axis: Axis = Axis.Z
@export var rotation_direction: Direction = Direction.POSITIVE
@export var rotation_speed: float = 1.0 #degree/sec

@onready var target_component : Node3D = get_parent()

func _process(delta: float) -> void:
	var final_speed = deg_to_rad(rotation_speed) * rotation_direction * delta

	match rotation_axis:
		Axis.X:
			target_component.rotate_x(final_speed)
		Axis.Y:
			target_component.rotate_y(final_speed)
		Axis.Z:
			target_component.rotate_z(final_speed)
