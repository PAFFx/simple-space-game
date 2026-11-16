@abstract
class_name MfdPage
extends Control

## One page of a cockpit display, drawn into the display's SubViewport. Styled after
## modern fighter large-area displays: dark field, thin outlines, boxed values, one
## colour per kind of information. Pages read the suit through `fc` / `vehicle`.

const BACKGROUND := Color(0.012, 0.02, 0.03)
const FRAME := Color(0.32, 0.42, 0.5)
const TEXT := Color(0.86, 0.92, 0.96)
const DIM := Color(0.5, 0.58, 0.64)
const GOOD := Color(0.35, 1.0, 0.55)
const INFO := Color(0.4, 0.82, 1.0)
const CAUTION := Color(1.0, 0.75, 0.2)
const WARNING := Color(1.0, 0.28, 0.22)
## The SOI border: the panoramic HUD's lock red (PanoramicHud.hostile_color).
const SOI := Color(0.96, 0.42, 0.4)

## Redraws per second. The page is drawn again only this often (CockpitDisplays
## schedules it), not every rendered frame: like a real display's own refresh rate.
var refresh_hz: float = 20.0

## The page has a cursor, so it can be the sensor of interest (FireControl.cycle_soi). Such
## a page overrides soi_slew, soi_candidate and soi_reset.
var has_cursor := false
## Set by the FireControl: this page is the SOI, so it gets the border and the cursor slew.
var is_soi := false

var fc: FlightComputer
var vehicle: VehicleBase
var font: Font


func setup(p_vehicle: VehicleBase) -> void:
	vehicle = p_vehicle
	fc = vehicle.find_component(FlightComputer) as FlightComputer if vehicle != null else null


func _ready() -> void:
	font = ThemeDB.fallback_font


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
	if fc != null:
		draw_page()
	_frame_corners()
	if is_soi:
		draw_rect(Rect2(Vector2.ONE * 3.0, size - Vector2.ONE * 6.0), SOI, false, 4.0)


## Override: draw the page (the field is already cleared).
@abstract func draw_page() -> void


## The cursor slew while this page is the SOI, each axis in [-1, 1] (x right, y up).
func soi_slew(_slew: Vector2, _delta: float) -> void:
	pass


## The contact under the page's cursor, or null.
func soi_candidate() -> Node3D:
	return null


## Back to its default place (after an unlock).
func soi_reset() -> void:
	pass


func label(pos: Vector2, value: String, color: Color = TEXT, font_size: int = 18,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var offset := 0.0
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		offset = w * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	draw_string(font, pos - Vector2(offset, 0.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Outlined box with a title tab, like a fighter display's format windows.
func window(rect: Rect2, title: String, color: Color = FRAME) -> void:
	draw_rect(rect, color, false, 1.5)
	if title != "":
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
		draw_rect(Rect2(rect.position + Vector2(10, -9), Vector2(w, 18)), BACKGROUND, true)
		label(rect.position + Vector2(17, 5), title, color, 14)


## Horizontal fill bar, `fraction` 0..1.
func hbar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect, Color(color, 0.12), true)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color, true)
	draw_rect(rect, Color(color, 0.6), false, 1.0)


## Vertical fill bar, filling up from the bottom.
func vbar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect, Color(color, 0.12), true)
	var h := rect.size.y * clampf(fraction, 0.0, 1.0)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - h), Vector2(rect.size.x, h)), color, true)
	draw_rect(rect, Color(color, 0.6), false, 1.0)


func _frame_corners() -> void:
	var k := 22.0
	var s := size - Vector2.ONE * 4.0
	for c in [Vector2(4, 4), Vector2(s.x, 4), Vector2(4, s.y), s]:
		var dx := k if c.x < size.x * 0.5 else -k
		var dy := k if c.y < size.y * 0.5 else -k
		draw_line(c, c + Vector2(dx, 0), FRAME, 2.0)
		draw_line(c, c + Vector2(0, dy), FRAME, 2.0)
