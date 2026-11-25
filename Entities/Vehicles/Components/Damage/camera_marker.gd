@tool
class_name CameraMarker
extends Marker3D

## Where one of the suit's cameras sits and where it looks (−Z), riding the bone of the
## BoneAttachment3D it is under. Move it in the editor; DamageModel puts the camera there.
## A camera without a painted lens shows a small green light here (in the editor too); a
## painted one (the eyes, the chest sensor) makes its green paint glow instead.

const LIVE := Color(0.35, 1.0, 0.5)

## The DamageModel camera this places: "main camera", "rear head camera", "camera 0".. "camera 5"
## (SensorSuite's body cameras), "skirt_rear.R camera", "foot.L camera", "forearm.R camera"...
@export var camera: StringName
## Only glows (a second lens of `camera`, e.g. the forehead telescope); doesn't move it.
@export var glow_only := false
## Light brightness (emission energy).
@export_range(0.0, 16.0, 0.1) var brightness := 1.5
## The lens is painted on the armour: these atlas UV rects of the part's mesh glow (only their
## green), no light is added.
@export var painted_uv: Array[Rect2] = []

var _lens: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	if painted_uv.is_empty():
		_make_lens()


func is_painted() -> bool:
	return not painted_uv.is_empty()


## Lit while the camera works, dark once it is shot out.
func set_alive(alive: bool) -> void:
	if _material == null:
		return
	_material.emission_enabled = alive
	_material.albedo_color = LIVE if alive else Color(0.03, 0.05, 0.035)


func _make_lens() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = LIVE
	_material.emission_enabled = true
	_material.emission = LIVE
	_material.emission_energy_multiplier = brightness
	_material.roughness = 0.2
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	sphere.radial_segments = 10
	sphere.rings = 5
	sphere.material = _material
	_lens = MeshInstance3D.new()
	_lens.name = "Lens"
	_lens.mesh = sphere
	_lens.layers = Layers.VEHICLE_EXT if not Engine.is_editor_hint() else 1
	_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lens, false, Node.INTERNAL_MODE_BACK)
