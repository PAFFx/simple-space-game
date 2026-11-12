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
@export var primary_color := Color(0.62, 1.0, 0.9, 0.92)
@export var dim_color := Color(0.62, 1.0, 0.9, 0.45)
@export var caution_color := Color(1.0, 0.72, 0.2, 0.95)
@export var warning_color := Color(1.0, 0.25, 0.2, 0.95)
@export var line_width: float = 2.0
@export var font_size: int = 18

var projector: HudProjector
var vehicle: VehicleBase
var hatch: CockpitHatch
var seat: SeatDampener
var ambac: AmbacController
var font: Font

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


func is_live() -> bool:
	return projector != null and sensor_head != null


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
	seat = vehicle.find_component(SeatDampener) as SeatDampener
	ambac = vehicle.find_component(AmbacController) as AmbacController
