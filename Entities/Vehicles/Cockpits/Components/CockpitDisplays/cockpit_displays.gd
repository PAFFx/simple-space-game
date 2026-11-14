class_name CockpitDisplays
extends Node

## Paints the cockpit's displays: each screen mesh in the cockpit model gets a page
## (an MfdPage) rendered into its own SubViewport. The screens are flat panels in the
## cockpit, not part of the panoramic monitor, so detail pages (engines, map, target)
## live here instead of cluttering the view outside.
##
## A page is drawn again at its own refresh rate (MfdPage.refresh_hz), not every rendered
## frame, and its viewport renders only then. The pages take turns, so two never redraw
## in the same frame.

## Screen mesh name in the cockpit model → page script, and the page's pixel size
## (matching the screen's aspect).
@export var screens := {
	"ScreenCentre": [preload("res://Entities/Vehicles/Cockpits/Components/CockpitDisplays/sa_page.gd"), Vector2i(1024, 716)],
	"ScreenLeft": [preload("res://Entities/Vehicles/Cockpits/Components/CockpitDisplays/engine_page.gd"), Vector2i(704, 512)],
	"ScreenRight": [preload("res://Entities/Vehicles/Cockpits/Components/CockpitDisplays/target_page.gd"), Vector2i(704, 512)],
}
## Where to look for the screen meshes (the cockpit model). Default: the parent.
@export var model_root: Node
@export var brightness: float = 1.15

var pages := {}

var _viewports := {}
# Seconds until each page is due, by mesh name.
var _due := {}


func _ready() -> void:
	var root := model_root if model_root != null else get_parent()
	var vehicle := VehicleBase.find_vehicle(self)
	for mesh_name: String in screens:
		var mesh := root.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh == null:
			push_warning("CockpitDisplays: no screen mesh '%s'" % mesh_name)
			continue
		var spec: Array = screens[mesh_name]
		var vp := SubViewport.new()
		vp.name = mesh_name + "Viewport"
		vp.size = spec[1]
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var page: MfdPage = (spec[0] as GDScript).new()
		page.name = mesh_name.trim_prefix("Screen") + "Page"
		page.size = Vector2(spec[1])
		vp.add_child(page)
		page.setup(vehicle)
		pages[mesh_name] = page
		_viewports[mesh_name] = vp
		_due[mesh_name] = 0.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = vp.get_texture()
		mat.albedo_color = Color(brightness, brightness, brightness)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		# The panels are turned past 90° to face the eye, which puts the model's "up"
		# edge at the bottom: flip the page vertically to read upright.
		mat.uv1_scale = Vector3(1, -1, 1)
		mat.uv1_offset = Vector3(0, 1, 0)
		mesh.material_override = mat


func _process(delta: float) -> void:
	# At most one page per frame: the most overdue one.
	var next := ""
	for mesh_name: String in _due:
		_due[mesh_name] -= delta
		if _due[mesh_name] <= 0.0 and (next == "" or _due[mesh_name] < _due[next]):
			next = mesh_name
	if next == "":
		return
	var page: MfdPage = pages[next]
	_due[next] = 1.0 / maxf(page.refresh_hz, 0.1)
	page.queue_redraw()
	(_viewports[next] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
