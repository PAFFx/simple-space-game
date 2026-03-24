class_name VehicleBase
extends Node3D

## Abstract base for all pilotable vehicles (mobile suits, ships, fighters, etc.).
## Extend this in every vehicle root script and implement the two mount getters.
## Components such as SensorHead and PanoramicScreen call VehicleBase.find_vehicle(self)
## to locate their vehicle context and discover sibling components automatically.


## Walk up the scene tree from any node to the nearest VehicleBase ancestor.
## Returns null if no VehicleBase is found (e.g. the node is not inside a vehicle).
static func find_vehicle(from: Node) -> VehicleBase:
	var node := from.get_parent()
	while node != null:
		if node is VehicleBase:
			return node as VehicleBase
		node = node.get_parent()
	return null


## Override: return the Marker3D under which the cockpit scene is placed as a child.
func get_cockpit_mount() -> Marker3D:
	push_error(name + ": get_cockpit_mount() not implemented")
	return null


## Override: return the Marker3D under which SensorHead is placed as a child.
func get_sensor_head_mount() -> Marker3D:
	push_error(name + ": get_sensor_head_mount() not implemented")
	return null


## Returns the first CockpitBase child found under the cockpit mount.
func get_cockpit() -> CockpitBase:
	var mount := get_cockpit_mount()
	if mount == null:
		return null
	for child in mount.get_children():
		if child is CockpitBase:
			return child as CockpitBase
	push_error(name + ": no CockpitBase found under cockpit mount")
	return null


## Returns the first SensorHead child found under the sensor head mount.
func get_sensor_head() -> SensorHead:
	var mount := get_sensor_head_mount()
	if mount == null:
		return null
	for child in mount.get_children():
		if child is SensorHead:
			return child as SensorHead
	push_error(name + ": no SensorHead found under sensor head mount")
	return null
