class_name MobileSuitRX0
extends VehicleBase

## RX-0 Full Armor Unicorn Gundam mobile suit.
## Implements the VehicleBase interface by pointing to the two mount markers
## placed in this scene. No manual export wiring required.
##
## get_node() is used directly (no @onready) so these getters work even when
## called from a child's _ready() — which fires before this node's _ready().


func get_cockpit_mount() -> Marker3D:
	return get_node("CockpitMount") as Marker3D


func get_sensor_head_mount() -> Marker3D:
	return get_node("SensorHeadMount") as Marker3D
