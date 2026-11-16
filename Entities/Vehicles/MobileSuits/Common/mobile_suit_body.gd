class_name MobileSuitBody
extends VehicleBase

## Generic mobile suit root. Attach to a RigidBody3D (VehicleBase only requires
## Node3D) so the whole suit — cockpit, sensor head, thrusters — is simulated.
## Expects children: Model (GLB), CockpitMount, SensorHeadMount.

## A shot landed on the suit: `direction` is the way it was flying.
signal hit_taken(damage: float, position: Vector3, direction: Vector3)

## Model meshes the pilot sees from inside through the open hatch (cavity + flaps).
@export var first_person_parts: Array[StringName] = [&"Chest", &"HatchUpper", &"HatchLower"]
## Model meshes the sensor head never sees, even with the body shown on the panoramic
## screen in a weapons mode: the head it sits in would wall it in.
@export var sensor_hidden_parts: Array[StringName] = [&"Head"]


func _ready() -> void:
	for mesh in get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var layers := Layers.VEHICLE_EXT
		if mesh.name in first_person_parts:
			layers |= Layers.VEHICLE_FP
		if not mesh.name in sensor_hidden_parts:
			layers |= Layers.SENSOR_BODY_PARTS
		(mesh as MeshInstance3D).layers = layers


func get_cockpit_mount() -> Marker3D:
	return get_node("CockpitMount") as Marker3D


func get_sensor_head_mount() -> Marker3D:
	return get_node("SensorHeadMount") as Marker3D


func get_body() -> RigidBody3D:
	return self as Node as RigidBody3D


## Called by ProjectileManager when a shot lands on the suit. No damage model yet: the
## fire control decides whether the shield took it and the HUD shows the hit.
func apply_hit(damage: float, position: Vector3, direction: Vector3, _source: Node) -> void:
	hit_taken.emit(damage, position, direction)
