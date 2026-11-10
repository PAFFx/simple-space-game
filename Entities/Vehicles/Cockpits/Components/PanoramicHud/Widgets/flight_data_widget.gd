class_name FlightDataWidget
extends HudWidget

## Numeric flight data blocks either side of the boresight, an attitude readout
## above it and the caution list below — kept small and out of the central view.

@export var side_azimuth_deg: float = 13.0
@export var block_elevation_deg: float = 3.0
@export var caution_elevation_deg: float = -11.0
@export var low_propellant_fraction: float = 0.2


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var line_h := float(hud.font_size) + 8.0
	_draw_left_block(fc, line_h)
	_draw_right_block(fc, line_h)
	_draw_attitude_readout()
	_draw_cautions(fc, line_h)


func _draw_left_block(fc: FlightComputer, line_h: float) -> void:
	begin_local(-side_azimuth_deg, block_elevation_deg)
	var rate := rad_to_deg(fc.state.angular_velocity.length())
	var rows := [
		["SPD", "%7.1f" % fc.state.linear_velocity.length(), "m/s"],
		["ACC", "%7.2f" % fc.acceleration_g, "G"],
		["ROT", "%7.1f" % rate, "°/s"],
	]
	for i in rows.size():
		var y := i * line_h
		text(Vector2(-px(7.5), y), rows[i][0], hud.dim_color)
		text(Vector2(0, y), rows[i][1], hud.primary_color, HORIZONTAL_ALIGNMENT_RIGHT)
		text(Vector2(4, y), rows[i][2], hud.dim_color, HORIZONTAL_ALIGNMENT_LEFT, 14)
	line(Vector2(-px(8.1), -line_h), Vector2(-px(8.1), line_h * 2.4), hud.dim_color)
	end_local()


func _draw_right_block(fc: FlightComputer, line_h: float) -> void:
	begin_local(side_azimuth_deg, block_elevation_deg)
	var prop := fc.get_propellant_fraction()
	var thr := fc.get_thrust_fraction()
	_bar_row(0.0, "PROP", prop, hud.caution_color if prop < low_propellant_fraction else hud.primary_color)
	_bar_row(line_h, "THR", thr, hud.primary_color)
	var modes := fc.get_mode_labels()
	for i in modes.size():
		text(Vector2(0, line_h * (2.2 + i)), modes[i], hud.primary_color, HORIZONTAL_ALIGNMENT_LEFT, 16)
	line(Vector2(-px(0.6), -line_h), Vector2(-px(0.6), line_h * (1.8 + modes.size())), hud.dim_color)
	end_local()


func _bar_row(y: float, label: String, fraction: float, color: Color) -> void:
	text(Vector2(0, y), label, hud.dim_color)
	var x0 := px(2.6)
	var w := px(2.6)
	var h := 8.0
	draw_rect(Rect2(x0, y - h - 2.0, w, h), hud.dim_color, false, 1.0)
	draw_rect(Rect2(x0, y - h - 2.0, w * clampf(fraction, 0.0, 1.0), h), color, true)
	text(Vector2(x0 + w + 6.0, y), "%3d%%" % roundi(fraction * 100.0), color, HORIZONTAL_ALIGNMENT_LEFT, 15)


func _draw_attitude_readout() -> void:
	var euler := hud.sensor_head.global_basis.get_euler()
	var hdg := wrapf(-rad_to_deg(euler.y), 0.0, 360.0)
	begin_local(0.0, 12.5)
	text(Vector2.ZERO, "HDG %03d   PIT %+03d   RLL %+04d" % [
		roundi(hdg), roundi(rad_to_deg(euler.x)), roundi(rad_to_deg(euler.z))
	], hud.dim_color, HORIZONTAL_ALIGNMENT_CENTER, 16)
	end_local()


func _draw_cautions(fc: FlightComputer, line_h: float) -> void:
	var items: Array[Array] = []
	if not fc.fcs_enabled:
		items.append(["FCS OFF", hud.warning_color])
	if fc.propellant <= 0.0:
		items.append(["PROPELLANT DEPLETED", hud.warning_color])
	elif fc.get_propellant_fraction() < low_propellant_fraction:
		items.append(["PROPELLANT LOW", hud.caution_color])
	if hud.hatch != null and hud.hatch.is_unsealed():
		items.append(["HATCH OPEN", hud.caution_color])
	if items.is_empty():
		return
	begin_local(0.0, caution_elevation_deg)
	# Blink cautions at 2 Hz like a master caution light.
	var on := int(Time.get_ticks_msec() / 250) % 2 == 0
	for i in items.size():
		var color: Color = items[i][1]
		if not on:
			color.a *= 0.35
		text(Vector2(0, i * line_h), items[i][0], color, HORIZONTAL_ALIGNMENT_CENTER)
	end_local()
