class_name ControlCentreWidget
extends HudWidget

## Where the controls are centred: the direction fly-by-wire pushes for "forward"
## (the control law's pilot frame; the suit's body when the law has none). Wide chevrons
## above and below, pointing in, with an empty middle: a V above, a ^ and an accent ^
## below, each a band with a bright border and a fainter fill. Rolls with the pilot frame's up.
##
## Nothing is drawn on the canvas: the screen shader draws the chevrons around the
## frame given here (hud_layers.gdshaderinc), so they stay sharp and cost no redraw.

@export var alpha: float = 0.95
## How solid the inside of each chevron is, as a share of its border.
@export var fill: float = 0.75
## 1 = chevrons 2° wide, their points 1.7° above and below the centre (1.4: 2.8° wide, 2.4°).
@export var symbol_scale: float = 1.4


func setup_layers() -> void:
	hud.set_hud_parameter(&"hud_control_color", Color(hud.primary_color, hud.primary_color.a * alpha))
	hud.set_hud_parameter(&"hud_control_accent_color",
			Color(hud.suit_accent_color, hud.suit_accent_color.a * alpha))
	hud.set_hud_parameter(&"hud_control_fill", fill)
	hud.set_hud_parameter(&"hud_control_scale", symbol_scale)


func _process(_delta: float) -> void:
	if hud == null or not hud.is_live() or hud.vehicle == null:
		return
	var fc := hud.flight_computer
	var frame := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	var pilot: Variant = fc.control_law.get_pilot_orientation() if fc != null and fc.control_law != null else null
	if pilot != null:
		frame = Basis(pilot as Quaternion)
	hud.set_hud_parameter(&"hud_control_frame", (hud.get_display_basis().inverse() * frame).inverse())


func draw_widget() -> void:
	pass
