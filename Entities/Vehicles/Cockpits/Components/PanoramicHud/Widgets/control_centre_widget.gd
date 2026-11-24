class_name ControlCentreWidget
extends HudWidget

## Where the controls are centred: the direction fly-by-wire pushes for "forward"
## (the control law's pilot frame; the suit's body when the law has none). Wide chevrons
## above and below, pointing in, with an empty middle: a V above, a ^ and an accent ^
## below, each a band with a bright border and a fainter fill. Rolls with the pilot frame's up.
##
## With a kick tank (FlightComputer.burst_reserve_capacity), the two ^s below are its
## halves: the white ^ the first 50%, the accent ^ the rest. Each band's fill fades with its
## half (hollow when spent), the white ^'s border dims while no kick is ready, and a ^ that
## fills back up brightens briefly.
##
## Nothing is drawn on the canvas: the screen shader draws the chevrons around the
## frame given here (hud_layers.gdshaderinc), so they stay sharp and cost no redraw.

@export var alpha: float = 0.95
## How solid the inside of each chevron is, as a share of its border (a full kick tank half).
@export var fill: float = 0.75
## 1 = chevrons 2° wide, their points 1.7° above and below the centre (1.4: 2.8° wide, 2.4°).
@export var symbol_scale: float = 1.4
## The white ^'s border while the kick tank holds less than a kick needs, share of its alpha.
@export var not_ready_border: float = 0.4
## How long a ^ stays brightened after its half of the kick tank fills back up, s.
@export var pop_time: float = 0.35

var _halves := Vector2(-1.0, -1.0)      ## Fill of each half last frame (-1 = none yet)
var _pop := Vector2.ZERO
var _sent_fill := Vector3(-1.0, -1.0, -1.0)
var _sent_border := Vector3(-1.0, -1.0, -1.0)
var _sent_pop := Vector2(-1.0, -1.0)


func setup_layers() -> void:
	hud.set_hud_parameter(&"hud_control_color", Color(hud.primary_color, hud.primary_color.a * alpha))
	hud.set_hud_parameter(&"hud_control_accent_color",
			Color(hud.suit_accent_color, hud.suit_accent_color.a * alpha))
	hud.set_hud_parameter(&"hud_control_scale", symbol_scale)
	_send(Vector3.ONE * fill, Vector3.ONE, Vector2.ZERO)


func _process(delta: float) -> void:
	if hud == null or not hud.is_live() or hud.vehicle == null:
		return
	var fc := hud.flight_computer
	var frame := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	var pilot: Variant = fc.control_law.get_pilot_orientation() if fc != null and fc.control_law != null else null
	if pilot != null:
		frame = Basis(pilot as Quaternion)
	hud.set_hud_parameter(&"hud_control_frame", (hud.get_display_basis().inverse() * frame).inverse())
	_kick_tank(fc, delta)


## The ^s as the kick tank's halves; as they always were without one.
func _kick_tank(fc: FlightComputer, delta: float) -> void:
	if fc == null or fc.burst_reserve_capacity <= 0.0:
		_send(Vector3.ONE * fill, Vector3.ONE, Vector2.ZERO)
		return
	var r := fc.get_burst_reserve_fraction()
	var halves := Vector2(clampf(r * 2.0, 0.0, 1.0), clampf(r * 2.0 - 1.0, 0.0, 1.0))
	for k in 2:
		if _halves[k] >= 0.0 and _halves[k] < 1.0 and halves[k] >= 1.0:
			_pop[k] = 1.0
		_pop[k] = move_toward(_pop[k], 0.0, delta / maxf(pop_time, 0.01))
	_halves = halves
	var ready := fc.burst_reserve >= fc.burst_min_reserve
	_send(Vector3(fill, fill * halves.x, fill * halves.y),
			Vector3(1.0, 1.0 if ready else not_ready_border, 1.0), _pop)


func _send(fill_v: Vector3, border: Vector3, pop: Vector2) -> void:
	if fill_v != _sent_fill:
		_sent_fill = fill_v
		hud.set_hud_parameter(&"hud_control_fill", fill_v)
	if border != _sent_border:
		_sent_border = border
		hud.set_hud_parameter(&"hud_control_border", border)
	if pop != _sent_pop:
		_sent_pop = pop
		hud.set_hud_parameter(&"hud_control_pop", pop)


func draw_widget() -> void:
	pass
