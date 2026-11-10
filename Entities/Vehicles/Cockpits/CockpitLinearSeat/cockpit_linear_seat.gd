class_name CockpitLinearSeat
extends CockpitBase

## Late-UC linear seat cockpit: the seat floats on a boom at the centre of the
## all-round panoramic screen, with the controls on the armrests. Only essential
## inputs are physical (two grips, pedals, a few switches); everything else lives
## on the HUD and touch panels, in line with modern fighter cockpit philosophy.
##
## get_node() is used (no @onready) so the mount getters work when called from a
## sibling's _ready() via VehicleBase — before this node's own _ready().


func _ready() -> void:
	# Interior is drawn for the pilot and for outside cameras looking in through
	# the open hatch, but never for the sensor (which would see it on the screen).
	_set_layers(get_node("Model"), Layers.COCKPIT | Layers.VEHICLE_EXT)


func get_camera_mount() -> Marker3D:
	return get_node("CameraMount") as Marker3D


func get_display_mount() -> Marker3D:
	return get_node("PanoramicDisplayMount") as Marker3D


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)
