class_name CockpitLinearSeat
extends CockpitBase

## Late-UC linear seat cockpit: the seat floats on a boom at the centre of the
## all-round panoramic screen, with the controls on the armrests. Only essential
## inputs are physical (two grips, pedals, a few switches); everything else lives
## on the HUD and touch panels, in line with modern fighter cockpit philosophy.
##
## get_node() is used (no @onready) so the mount getters work when called from a
## sibling's _ready() via VehicleBase — before this node's own _ready().


var _hatch: CockpitHatch
var _outside_visible := false
var _gimbal: CockpitGimbal


func _ready() -> void:
	# Interior is drawn for the pilot always, for outside cameras only while the hatch is
	# unsealed (looking in through it; sealed, the gimballed capsule's hatch frame could
	# poke through the hull as it turns), and never for the sensor (which would see it on
	# the screen).
	_apply_layers()
	var gimbals := find_children("*", "CockpitGimbal", true, false)
	_gimbal = gimbals[0] as CockpitGimbal if not gimbals.is_empty() else null
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch


func _process(_delta: float) -> void:
	# Breached by a beam its gimbal is jammed (it can't turn into the hull): the wreck is
	# seen through the holes.
	var outside := (_hatch != null and _hatch.is_unsealed()) or _jammed()
	if outside != _outside_visible:
		_outside_visible = outside
		_apply_layers()


func _apply_layers() -> void:
	var layers := Layers.COCKPIT | (Layers.VEHICLE_EXT if _outside_visible else 0)
	_set_layers(get_node("Model"), layers)
	var panel := get_node_or_null("SwitchPanel")
	if panel != null:
		_set_layers(panel, layers)


func _jammed() -> bool:
	return _gimbal != null and _gimbal.jammed


func get_camera_mount() -> Marker3D:
	return get_node("CameraMount") as Marker3D


func get_display_mount() -> Marker3D:
	return get_node("PanoramicDisplayMount") as Marker3D


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)
