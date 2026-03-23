class_name CockpitDisplayController
extends Node

## Wires the PanoramicScreen in the cockpit to the SensorHead on the mech.
## Assign all three exports in the Inspector after placing this node in the
## assembled vehicle scene (where both the cockpit and mech are present).

@export var cockpit: CockpitRX0
@export var sensor_head: SensorHead
@export var viewer_camera: Camera3D


func _ready() -> void:
	if cockpit == null or sensor_head == null or viewer_camera == null:
		push_warning("CockpitDisplayController: one or more exports are not set.")
		return
	sensor_head.panoramic_screen = cockpit.panoramic_screen
	cockpit.panoramic_screen.sensor_head = sensor_head
	sensor_head.viewer_camera = viewer_camera
