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
## Pages a screen switches to: after each new damage for `damage_page_time` s, and on the
## `mfd_left_page` action (P) until pressed again.
@export var alternates := {
	"ScreenLeft": preload("res://Entities/Vehicles/Cockpits/Components/CockpitDisplays/damage_page.gd"),
}
@export var damage_page_time: float = 10.0
## Where to look for the screen meshes (the cockpit model). Default: the parent.
@export var model_root: Node
@export var brightness: float = 1.15

var pages := {}
var _primary := {}      ## mesh name → its own page
var _alternate := {}    ## mesh name → its alternate page
var _alt_until := {}    ## mesh name → time the alternate shows until (INF: held by the key)
var _time := 0.0

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
		var fcs := vehicle.find_component(FireControl) as FireControl if vehicle != null else null
		if fcs != null:
			fcs.register_soi_display(page, StringName(mesh_name.trim_prefix("Screen").to_lower()))
		pages[mesh_name] = page
		_primary[mesh_name] = page
		if alternates.has(mesh_name):
			var alt: MfdPage = (alternates[mesh_name] as GDScript).new()
			alt.name = mesh_name.trim_prefix("Screen") + "AltPage"
			alt.size = Vector2(spec[1])
			alt.visible = false
			vp.add_child(alt)
			alt.setup(vehicle)
			_alternate[mesh_name] = alt
			_alt_until[mesh_name] = -1.0
			_hook_damage.call_deferred(vehicle, mesh_name)
		_viewports[mesh_name] = vp
		_due[mesh_name] = 0.0
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://Entities/Vehicles/Cockpits/Components/CockpitDisplays/mfd_screen.gdshader")
		mat.set_shader_parameter(&"page", vp.get_texture())
		mat.set_shader_parameter(&"brightness", brightness)
		mesh.material_override = mat


## The suit makes its damage model after its cockpit is ready: hook up then.
func _hook_damage(vehicle: VehicleBase, mesh_name: String) -> void:
	var damage := vehicle.find_component(DamageModel) as DamageModel if vehicle != null else null
	if damage == null:
		return
	var show := func(_a = null, _b = null) -> void: _flash_alternate(mesh_name)
	damage.component_destroyed.connect(show)
	damage.part_severed.connect(show)
	damage.cockpit_holed.connect(show)


const PAGE_ACTION := &"mfd_left_page"


func _input(event: InputEvent) -> void:
	if not InputMap.has_action(PAGE_ACTION):
		InputMap.add_action(PAGE_ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_P
		InputMap.action_add_event(PAGE_ACTION, key)
	if event.is_action_pressed(PAGE_ACTION):
		for mesh_name: String in _alternate:
			_alt_until[mesh_name] = -1.0 if float(_alt_until[mesh_name]) == INF else INF
			_show(mesh_name)


func _flash_alternate(mesh_name: String) -> void:
	if float(_alt_until[mesh_name]) != INF:
		_alt_until[mesh_name] = _time + damage_page_time
	_show(mesh_name)


func _show(mesh_name: String) -> void:
	var alt_on := _time < float(_alt_until[mesh_name])
	var want: MfdPage = _alternate[mesh_name] if alt_on else _primary[mesh_name]
	if pages[mesh_name] != want:
		(pages[mesh_name] as MfdPage).visible = false
		want.visible = true
		pages[mesh_name] = want
		_due[mesh_name] = 0.0


func _process(delta: float) -> void:
	_time += delta
	for mesh_name: String in _alternate:
		_show(mesh_name)
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
