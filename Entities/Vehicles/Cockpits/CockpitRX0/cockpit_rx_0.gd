class_name CockpitRX0
extends CockpitBase

## RX-0 cockpit interior.
## Implements the CockpitBase interface by pointing to the two mount markers
## placed in this scene. No manual export wiring required.
##
## get_node() is used directly (no @onready) so these getters work even when
## called from a sibling's _ready() via VehicleBase — before this node's _ready().


func get_camera_mount() -> Marker3D:
	return get_node("CameraMount") as Marker3D


func get_display_mount() -> Marker3D:
	return get_node("PanoramicDisplayMount") as Marker3D
