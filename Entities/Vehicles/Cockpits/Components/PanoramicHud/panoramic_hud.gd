class_name PanoramicHud
extends Node

## Head-up display painted onto the panoramic screen.
##
## Owns a transparent 2D SubViewport laid out as an equirectangular canvas (see
## HudProjector) and hands its texture to the PanoramicScreen shader. Instruments
## are HudWidget nodes placed under HudViewport — add, remove or reorder them in
## the scene to change the HUD layout.
##
## Dependencies are discovered through the parent VehicleBase; the exports are
## optional overrides for standalone testing.

@export var panoramic_screen: PanoramicScreen
@export var sensor_head: SensorHead
@export var flight_computer: FlightComputer

@export var canvas_size := Vector2i(4096, 2048)

@export_group("Style")
## One colour per kind of information, so each reads apart at a glance:
## flight symbology (horizon, flight path, speed)...
@export var primary_color := Color(0.88, 0.91, 0.93, 0.92)
@export var dim_color := Color(0.68, 0.72, 0.76, 0.7)
## ...the pitch ladder, a pale steel blue kept quieter than the symbols over it...
@export var ladder_color := Color(0.58, 0.72, 0.82, 0.8)
## ...the suit's orientation against the cockpit (suit line, side rings)...
@export var suit_color := Color(0.84, 0.87, 0.9, 0.55)
## ...its accent: the arrowheads that mark where the suit points...
@export var suit_accent_color := Color(0.9, 0.42, 0.66, 0.9)
## ...the suit's own equipment (shield and weapon outlines)...
@export var equipment_color := Color(0.74, 0.7, 0.86, 0.85)
## ...and other objects (contacts).
@export var contact_color := Color(1.0, 0.62, 0.22, 0.95)
@export var caution_color := Color(1.0, 0.86, 0.3, 0.95)
@export var warning_color := Color(1.0, 0.25, 0.2, 0.95)
## Dark edge under every line and label, so symbols read against bright backgrounds
## (a sunlit planet) without being made brighter or thicker.
@export var halo_color := Color(0.0, 0.0, 0.0, 0.55)
@export var halo_width: float = 3.0
@export var line_width: float = 2.5
@export var font_size: int = 18

var projector: HudProjector
var vehicle: VehicleBase
var hatch: CockpitHatch
var ambac: AmbacController
var font: Font

## Fixed layers (see add_layer_drawer) and the screen shader texture each one feeds.
const _LAYER_TEXTURES := {
	&"static": &"hud_static_texture",
	&"heading": &"hud_heading_texture",
	&"ladder": &"hud_ladder_texture",
	&"suit": &"hud_suit_texture",
}

var _layers := {}

@onready var viewport: SubViewport = $HudViewport


func _ready() -> void:
	font = ThemeDB.fallback_font
	viewport.size = canvas_size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_auto_discover()
	var elevation_range := panoramic_screen.elevation_range if panoramic_screen != null else PI
	projector = HudProjector.new(Vector2(canvas_size), elevation_range)
	if panoramic_screen != null:
		panoramic_screen.set_hud_texture(viewport.get_texture())
	for widget in viewport.get_children():
		if widget is HudWidget:
			widget.setup_layers()


func is_live() -> bool:
	return projector != null and sensor_head != null


## Draws `draw_fn(canvas: HudWidget)` into a fixed layer, once: content that only turns
## with the attitude is drawn in the layer's own frame and turned into place by the
## screen shader (a `hud_<layer>_frame` uniform), instead of being redrawn every frame.
## Layers: static (display frame), heading, ladder (coverage, `additive`), suit.
func add_layer_drawer(layer: StringName, draw_fn: Callable, additive := false) -> void:
	var layer_viewport: SubViewport = _layers.get(layer)
	if layer_viewport == null:
		layer_viewport = SubViewport.new()
		layer_viewport.name = "Layer_%s" % layer
		layer_viewport.size = canvas_size
		layer_viewport.transparent_bg = true
		layer_viewport.disable_3d = true
		layer_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(layer_viewport)
		_layers[layer] = layer_viewport
		set_hud_parameter(_LAYER_TEXTURES[layer], layer_viewport.get_texture())
	var canvas := HudLayerCanvas.new()
	canvas.draw_fn = draw_fn
	if additive:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		canvas.material = material
	layer_viewport.add_child(canvas)


## Draws every layer again (after changing what they show).
func redraw_layers() -> void:
	for layer_viewport: SubViewport in _layers.values():
		for canvas in layer_viewport.get_children():
			canvas.queue_redraw()
		layer_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## A HUD uniform of the screen shader (layer frames, ladder state).
func set_hud_parameter(param: StringName, value: Variant) -> void:
	if panoramic_screen != null:
		panoramic_screen.set_hud_parameter(param, value)


## A role colour toned down for secondary marks (scales, labels).
static func dimmed(c: Color) -> Color:
	return Color(c, c.a * 0.7)


## World direction → canvas position (through the screen's panoramic frame).
func world_dir_to_canvas(world_dir: Vector3) -> Vector2:
	return projector.direction_to_canvas(world_to_display(world_dir))


## World direction → display-local direction (the frame the canvas is laid out in).
func world_to_display(world_dir: Vector3) -> Vector3:
	return get_display_basis().inverse() * world_dir


## Orientation of the display (the cockpit), which may differ from the suit's body.
func get_display_basis() -> Basis:
	if panoramic_screen != null:
		return panoramic_screen.get_display_basis()
	return sensor_head.global_basis.orthonormalized()


## The frame the attitude symbols and readouts are shown against (y = up, -z = north):
## up from the flight computer (the horizon lock's, or the reference frame's), north
## from the reference frame's -Z, flattened onto the horizon.
func get_attitude_basis() -> Basis:
	return flight_computer.get_attitude_basis() if flight_computer != null else Basis.IDENTITY


## Where the screen's image is seen from: the sensor head (the suit's head camera),
## not the pilot's seat. World-anchored symbols are projected from here so they line
## up with the image; near objects (the suit's own shield) would sit off otherwise.
func get_view_origin() -> Vector3:
	if sensor_head != null:
		return sensor_head.get_global_transform_interpolated().origin
	return panoramic_screen.get_display_transform().origin


func _auto_discover() -> void:
	vehicle = VehicleBase.find_vehicle(self)
	if vehicle == null:
		push_warning("PanoramicHud: no VehicleBase in parent chain; using manual exports only")
		return
	if panoramic_screen == null and vehicle.get_cockpit() != null:
		panoramic_screen = vehicle.get_cockpit().get_panoramic_screen()
	if sensor_head == null:
		sensor_head = vehicle.get_sensor_head()
	if flight_computer == null:
		flight_computer = vehicle.find_component(FlightComputer) as FlightComputer
	hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
	ambac = vehicle.find_component(AmbacController) as AmbacController
