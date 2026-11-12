class_name ControlCentreWidget
extends HudWidget

## Where the controls are centred: the direction fly-by-wire pushes for "forward"
## (the control law's pilot frame; the suit's body when the law has none). Chevrons
## above and below, pointing in, with an empty middle.
## Rolls with the pilot frame's up.

@export var alpha: float = 0.6


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null or hud.vehicle == null:
		return
	var frame := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	var pilot: Variant = fc.control_law.get_pilot_orientation() if fc.control_law != null else null
	if pilot != null:
		frame = Basis(pilot as Quaternion)
	var p := patch(hud.world_to_display(-frame.z), hud.world_to_display(frame.y))
	var c := Color(hud.primary_color, hud.primary_color.a * alpha)
	var accent := Color(hud.suit_accent_color, hud.suit_accent_color.a * alpha)

	# V above, two ^ below (the lower one in the accent), pointing at the centre.
	_chevron(p, Vector2(0, 1.7), Vector2(0, -1), 1.0, c)
	_chevron(p, Vector2(0, -1.7), Vector2(0, 1), 1.0, c)
	_chevron(p, Vector2(0, -2.7), Vector2(0, 1), 1.0, accent)


## Chevron with its tip at `tip`, pointing along `dir` (unit, patch deg).
func _chevron(p: Patch, tip: Vector2, dir: Vector2, size: float, color: Color) -> void:
	var back := -dir * size * 0.6
	var across := Vector2(-dir.y, dir.x) * size
	patch_line(p, tip + back + across, tip, color, 2.0, 2)
	patch_line(p, tip, tip + back - across, color, 2.0, 2)

