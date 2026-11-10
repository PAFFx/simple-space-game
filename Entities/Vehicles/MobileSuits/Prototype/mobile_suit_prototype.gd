class_name MobileSuitPrototype
extends VehicleBase

## Prototype late-UC mobile suit (MSP-01).
##
## The root node is a RigidBody3D (VehicleBase only requires Node3D), so the
## whole suit — cockpit, sensor head and thrusters — is physically simulated.
## Thrusters ride on BoneAttachment3Ds and follow limb animation; the
## FlightComputer discovers them automatically.

## Parts the pilot can see from inside once the hatch is open (cavity + hatch).
const _FIRST_PERSON_PARTS: Array[StringName] = [&"Chest", &"HatchUpper", &"HatchLower"]


func _ready() -> void:
	for mesh in get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var layers := Layers.VEHICLE_EXT
		if mesh.name in _FIRST_PERSON_PARTS:
			layers |= Layers.VEHICLE_FP
		(mesh as MeshInstance3D).layers = layers


func get_cockpit_mount() -> Marker3D:
	return get_node("CockpitMount") as Marker3D


func get_sensor_head_mount() -> Marker3D:
	return get_node("SensorHeadMount") as Marker3D


func get_body() -> RigidBody3D:
	return self as Node as RigidBody3D
