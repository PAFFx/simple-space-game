class_name NavBuoy
extends Node3D

## Navigation buoy with a blinking beacon. Registers itself as a HUD contact.

@export var label: String = "BUOY"
@export var blink_period: float = 1.5
@export var beacon_color := Color(1.0, 0.35, 0.2)

@onready var _light: OmniLight3D = $Beacon
@onready var _lamp: MeshInstance3D = $Lamp


func _ready() -> void:
	add_to_group(&"hud_contacts")
	set_meta(&"hud_label", label)
	set_meta(&"hud_radius", 4.0)
	_light.light_color = beacon_color
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = beacon_color
	_lamp.material_override = mat


func _process(_delta: float) -> void:
	var on := fmod(Time.get_ticks_msec() / 1000.0, blink_period) < blink_period * 0.25
	_light.visible = on
	_lamp.visible = on
