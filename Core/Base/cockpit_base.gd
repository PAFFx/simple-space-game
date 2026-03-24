class_name CockpitBase
extends Node3D

## Abstract base for all cockpit interiors.
## Extend this in every cockpit root script and implement the two mount getters.
## Components call these via VehicleBase.get_cockpit() to reach the camera and display.


## Override: return the Marker3D under which PlayerCamera3D is placed as a child.
func get_camera_mount() -> Marker3D:
	push_error(name + ": get_camera_mount() not implemented")
	return null


## Override: return the Marker3D under which PanoramicScreen is placed as a child.
func get_display_mount() -> Marker3D:
	push_error(name + ": get_display_mount() not implemented")
	return null


## Returns the first Camera3D child found under the camera mount.
func get_player_camera() -> Camera3D:
	var mount := get_camera_mount()
	if mount == null:
		return null
	for child in mount.get_children():
		if child is Camera3D:
			return child as Camera3D
	push_error(name + ": no Camera3D found under camera mount")
	return null


## Returns the first PanoramicScreen child found under the display mount.
func get_panoramic_screen() -> PanoramicScreen:
	var mount := get_display_mount()
	if mount == null:
		return null
	for child in mount.get_children():
		if child is PanoramicScreen:
			return child as PanoramicScreen
	push_error(name + ": no PanoramicScreen found under display mount")
	return null
