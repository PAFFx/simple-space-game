class_name FlightDataWidget
extends HudWidget

## Numeric flight data blocks either side of the boresight, an attitude readout
## above it and the caution list below — kept small and out of the central view.

const MACH_1 := 340.3

@export var side_azimuth_deg: float = 11.0
## The small G / rotation / AMBAC column sits this much further out than the speed.
@export var secondary_offset_deg: float = 9.0
@export var block_elevation_deg: float = 3.0
@export var caution_elevation_deg: float = -11.0
@export var low_propellant_fraction: float = 0.2
@export var high_g_caution: float = 6.0


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var line_h := float(hud.font_size) + 8.0
	_draw_left_block(fc, line_h)
	_draw_right_block(fc, line_h)
	_draw_cautions(fc, line_h)


func _draw_left_block(fc: FlightComputer, line_h: float) -> void:
	var speed := fc.state.linear_velocity.length()
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	# Speed: the main number, boxed, nearest the centre.
	begin_local(-side_azimuth_deg, block_elevation_deg)
	var w := px(8.0)
	var h := 44.0
	for pt in [[Vector2(-w, -h * 0.5), Vector2(0, -h * 0.5)], [Vector2(-w, h * 0.5), Vector2(0, h * 0.5)],
			[Vector2(-w, -h * 0.5), Vector2(-w, h * 0.5)], [Vector2(0, -h * 0.5), Vector2(0, h * 0.5)]]:
		line(pt[0], pt[1], c)
	text(Vector2(-8.0, 14.0), "%.0f" % speed if speed >= 100.0 else "%.1f" % speed, c,
			HORIZONTAL_ALIGNMENT_RIGHT, 38)
	text(Vector2(-w, -h * 0.5 - 6.0), "SPD m/s", dim, HORIZONTAL_ALIGNMENT_LEFT, 14)
	# Mach against sea-level air (340.3 m/s): a familiar scale until there's an atmosphere.
	text(Vector2(-8.0, h * 0.5 + 26.0), "M %.2f" % (speed / MACH_1), c, HORIZONTAL_ALIGNMENT_RIGHT, 22)
	end_local()

	# Secondary data, small and further out.
	begin_local(-side_azimuth_deg - secondary_offset_deg, block_elevation_deg + 1.0)
	var rows := [["G MS", "%.1f" % fc.acceleration_g]]
	if hud.seat != null:
		rows.append(["G PLT", "%.1f" % hud.seat.pilot_g])
	rows.append(["ROT", "%.0f" % rad_to_deg(fc.state.angular_velocity.length())])
	if hud.ambac != null:
		rows.append(["AMBAC", "%d%%" % roundi(hud.ambac.get_usage() * 100.0)])
	var small_h := 18.0
	for k in rows.size():
		var y := k * small_h
		text(Vector2(-px(5.5), y), rows[k][0], dim, HORIZONTAL_ALIGNMENT_LEFT, 13)
		text(Vector2(0, y), rows[k][1], dim, HORIZONTAL_ALIGNMENT_RIGHT, 14)
	end_local()


func _draw_right_block(fc: FlightComputer, line_h: float) -> void:
	begin_local(side_azimuth_deg, block_elevation_deg)
	var prop := fc.get_propellant_fraction()
	var thr := fc.get_thrust_fraction()
	var prop_color := hud.caution_color if prop < low_propellant_fraction else hud.primary_color
	_bar_row(0.0, "PROP", prop, prop_color)
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
	var pct := "%3d%%" % roundi(fraction * 100.0)
	text(Vector2(x0 + w + 6.0, y), pct, color, HORIZONTAL_ALIGNMENT_LEFT, 15)


func _draw_cautions(fc: FlightComputer, line_h: float) -> void:
	var items: Array[Array] = []
	if not fc.fcs_enabled:
		items.append(["FCS OFF", hud.warning_color])
	if fc.propellant <= 0.0:
		items.append(["PROPELLANT DEPLETED", hud.warning_color])
	elif fc.get_propellant_fraction() < low_propellant_fraction:
		items.append(["PROPELLANT LOW", hud.caution_color])
	if hud.seat != null and hud.seat.pilot_g > high_g_caution:
		items.append(["HIGH G", hud.warning_color])
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
