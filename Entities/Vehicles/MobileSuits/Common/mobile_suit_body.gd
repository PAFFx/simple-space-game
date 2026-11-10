class_name MobileSuitBody
extends VehicleBase

## Generic mobile suit root. Attach to a RigidBody3D (VehicleBase only requires
## Node3D) so the whole suit — cockpit, sensor head, thrusters — is simulated.
## Expects children: Model (GLB), CockpitMount, SensorHeadMount.

## Model meshes the pilot sees from inside through the open hatch (cavity + flaps).
@export var first_person_parts: Array[StringName] = [&"Chest", &"HatchUpper", &"HatchLower"]


func _ready() -> void:
	for mesh in get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var layers := Layers.VEHICLE_EXT
		if mesh.name in first_person_parts:
			layers |= Layers.VEHICLE_FP
		(mesh as MeshInstance3D).layers = layers


func get_cockpit_mount() -> Marker3D:
	return get_node("CockpitMount") as Marker3D


func get_sensor_head_mount() -> Marker3D:
	return get_node("SensorHeadMount") as Marker3D


func get_body() -> RigidBody3D:
	return self as Node as RigidBody3D
