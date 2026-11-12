class_name FlightDataWidget
extends HudWidget

## A flight data column left of centre (G / rotation / AMBAC, then speed and Mach),
## the non-default modes just inside the right pitch ladder column, and the caution list
## below — kept small and out of the central view.

const MACH_1 := 340.3

## Right edge of the left data column, deg; it sits above the suit line.
@export var data_azimuth_deg: float = -20.0
@export var data_width_deg: float = 6.8
@export var data_elevation_deg: float = 14.0
## Right edge of the mode list, deg: just inside the right pitch ladder column.
@export var modes_azimuth_deg: float = 25.5
@export var modes_elevation_deg: float = 7.5
@export var caution_elevation_deg: float = -11.0
@export var low_propellant_fraction: float = 0.2
@export var high_g_caution: float = 6.0


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var line_h := float(hud.font_size) + 8.0
	_draw_data_column(fc)
	_draw_modes(fc)
	_draw_cautions(fc, line_h)


## Small rows on top, then the boxed speed and Mach under them, in the dim text colour;
## only the speed and its box are bright, as the number to read at a glance.
func _draw_data_column(fc: FlightComputer) -> void:
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	begin_local(data_azimuth_deg, data_elevation_deg)
	var w := px(data_width_deg)
	var rows := [["G MS", "%.1f" % fc.acceleration_g]]
	rows.append(["ROT", "%.0f" % rad_to_deg(fc.state.angular_velocity.length())])
	if hud.ambac != null:
		rows.append(["AMBAC", "%d%%" % roundi(hud.ambac.get_usage() * 100.0)])
	var row_h := 18.0
	for k in rows.size():
		var y := k * row_h
		text(Vector2(-w, y), rows[k][0], dim, HORIZONTAL_ALIGNMENT_LEFT, 13)
		text(Vector2(0, y), rows[k][1], dim, HORIZONTAL_ALIGNMENT_RIGHT, 14)

	var speed := fc.state.linear_velocity.length()
	var top := rows.size() * row_h + 14.0
	text(Vector2(-w, top), "SPD m/s", dim, HORIZONTAL_ALIGNMENT_LEFT, 13)
	var h := 32.0
	var y0 := top + 6.0
	var y1 := y0 + h
	for pt in [[Vector2(-w, y0), Vector2(0, y0)], [Vector2(-w, y1), Vector2(0, y1)],
			[Vector2(-w, y0), Vector2(-w, y1)], [Vector2(0, y0), Vector2(0, y1)]]:
		line(pt[0], pt[1], c, 1.5)
	text(Vector2(-6.0, y1 - 7.0), "%.0f" % speed if speed >= 100.0 else "%.1f" % speed, c,
			HORIZONTAL_ALIGNMENT_RIGHT, 26)
	# Mach against sea-level air (340.3 m/s): a familiar scale until there's an atmosphere.
	text(Vector2(0, y1 + 20.0), "M %.2f" % (speed / MACH_1), dim, HORIZONTAL_ALIGNMENT_RIGHT, 16)
	end_local()


## Non-default modes, right-aligned against the right pitch ladder column, each bright in
## its own box so a mode change stands out.
func _draw_modes(fc: FlightComputer) -> void:
	var c := hud.primary_color
	var size := 14
	var pad := Vector2(6.0, 4.0)
	var row_h := 26.0
	begin_local(modes_azimuth_deg, modes_elevation_deg)
	# Engines and fuel are on the cockpit's left display; only non-default modes here.
	var modes := fc.get_mode_labels()
	for i in modes.size():
		var y := row_h * i
		var tw := hud.font.get_string_size(modes[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var top := y - hud.font.get_ascent(size) - pad.y + 2.0
		var bottom := y + pad.y
		var left := -tw - pad.x
		var right := pad.x
		for pt in [[Vector2(left, top), Vector2(right, top)], [Vector2(left, bottom), Vector2(right, bottom)],
				[Vector2(left, top), Vector2(left, bottom)], [Vector2(right, top), Vector2(right, bottom)]]:
			line(pt[0], pt[1], c, 1.5)
		text(Vector2(0, y), modes[i], c, HORIZONTAL_ALIGNMENT_RIGHT, size)
	end_local()


func _draw_cautions(fc: FlightComputer, line_h: float) -> void:
	var items: Array[Array] = []
	if not fc.fcs_enabled:
		items.append(["FCS OFF", hud.warning_color])
	if fc.propellant <= 0.0:
		items.append(["PROPELLANT DEPLETED", hud.warning_color])
	elif fc.get_propellant_fraction() < low_propellant_fraction:
		items.append(["PROPELLANT LOW", hud.caution_color])
	if fc.acceleration_g > high_g_caution:
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
