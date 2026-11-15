class_name WeaponRing

## Draws the weapon select hat as two rings of four segments round a hub: the inner ring
## is each direction's first press, the outer ring the press again, the hub the depress.
## Up = hat forward. The selected weapon's segment is filled; weapons not fitted are dim.

const INNER := Vector2(0.27, 0.6)    # ring radii as shares of the ring's radius
const OUTER := Vector2(0.65, 1.0)
const HUB := 0.2
const GAP_DEG := 9.0
## Segment centre angles in FireControl.Hat order (forward, right, aft, left), screen rad.
const ANGLES := [-PI * 0.5, 0.0, PI * 0.5, PI]


## `pressed`: the hat direction to flash (-1 = none), `flash` its strength 0..1.
static func draw(ci: CanvasItem, font: Font, centre: Vector2, radius: float, fcs: FireControl,
		palette: Dictionary, pressed := -1, flash := 0.0) -> void:
	var frame: Color = palette.frame
	# Bezel: a fine circle with a tick at each diagonal, where the gaps are.
	ci.draw_arc(centre, radius * 1.08, 0.0, TAU, 96, Color(frame, 0.6), 1.0, true)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		ci.draw_line(centre + dir * radius * HUB * 1.5, centre + dir * radius * 1.14, Color(frame, 0.8), 1.5, true)
	for direction in 4:
		var slot: Array = fcs.hat_layout[direction] if direction < fcs.hat_layout.size() else []
		for ring in 2:
			var id: StringName = slot[ring] if ring < slot.size() else &""
			var radii := (INNER if ring == 0 else OUTER) * radius
			_segment(ci, font, centre, radii, ANGLES[direction], id, fcs, palette,
					flash if direction == pressed else 0.0, radius)
	# Hub: the depress.
	var hub_slot: Array = fcs.hat_layout[FireControl.Hat.DEPRESS] if fcs.hat_layout.size() > FireControl.Hat.DEPRESS else []
	var hub_id: StringName = hub_slot[0] if not hub_slot.is_empty() else &""
	var pts := PackedVector2Array()
	for k in 9:
		var a := k * TAU / 8.0 + PI / 8.0
		pts.append(centre + Vector2(cos(a), sin(a)) * radius * HUB)
	var hub_color := _color(hub_id, fcs, palette)
	if fcs.selected != null and fcs.selected.weapon_id == hub_id and hub_id != &"":
		ci.draw_colored_polygon(pts.slice(0, 8), hub_color)
	elif pressed == FireControl.Hat.DEPRESS and flash > 0.0:
		ci.draw_colored_polygon(pts.slice(0, 8), Color(hub_color, 0.5 * flash))
	ci.draw_polyline(pts, hub_color, 1.5, true)
	if hub_id != &"":
		_centred(ci, font, centre + Vector2(0, radius * 0.035), String(fcs.weapon_labels.get(hub_id, hub_id)),
				hub_color, roundi(radius * 0.075))


static func _segment(ci: CanvasItem, font: Font, centre: Vector2, radii: Vector2, angle: float,
		id: StringName, fcs: FireControl, palette: Dictionary, flash: float, radius: float) -> void:
	var weapon := fcs.get_weapon(id) if id != &"" else null
	var color := _color(id, fcs, palette)
	var selected := weapon != null and weapon == fcs.selected
	# The gap between segments is as wide in pixels on both rings.
	var gap := radius * deg_to_rad(GAP_DEG) * 0.55
	var pts := PackedVector2Array()
	var steps := 14
	for k in steps + 1:
		var half := PI * 0.25 - gap / radii.y
		var a := angle + lerpf(-half, half, float(k) / steps)
		pts.append(centre + Vector2(cos(a), sin(a)) * radii.y)
	for k in steps + 1:
		var half := PI * 0.25 - gap / radii.x
		var a := angle + lerpf(half, -half, float(k) / steps)
		pts.append(centre + Vector2(cos(a), sin(a)) * radii.x)
	if selected:
		ci.draw_colored_polygon(pts, color)
	elif weapon != null:
		ci.draw_colored_polygon(pts, Color(color, 0.1 + 0.35 * flash))
	elif flash > 0.0:
		ci.draw_colored_polygon(pts, Color(palette.warning, 0.25 * flash))
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, color, 2.0 if weapon != null else 1.0, true)
	if id == &"":
		return
	var mid := centre + Vector2(cos(angle), sin(angle)) * (radii.x + radii.y) * 0.5
	var ink: Color = palette.background if selected else color
	var size := roundi(radius * 0.085)
	if weapon == null:
		_centred(ci, font, mid + Vector2(0, size * 0.35), String(fcs.weapon_labels.get(id, id)), ink, size)
		return
	_centred(ci, font, mid + Vector2(0, -size * 0.1), String(fcs.weapon_labels.get(id, weapon.get_hud_name())), ink, size)
	var rounds_color: Color = ink if weapon.ammo > 0 or selected else palette.warning
	_centred(ci, font, mid + Vector2(0, size * 1.05), "%d" % weapon.ammo, rounds_color, roundi(size * 0.95))
	# Readiness: a bar growing along the segment's outer edge.
	if selected and weapon.readiness < 1.0:
		var half := (PI * 0.25 - gap / radii.y) * weapon.readiness
		ci.draw_arc(centre, radii.y + 5.0, angle - half, angle + half, 16, palette.caution, 3.0, true)


static func _color(id: StringName, fcs: FireControl, palette: Dictionary) -> Color:
	if id == &"":
		return Color(palette.frame, 0.45)
	if fcs.get_weapon(id) == null:
		return Color(palette.dim, 0.75)
	return palette.accent if fcs.selected != null and fcs.selected.weapon_id == id else palette.text


static func _centred(ci: CanvasItem, font: Font, pos: Vector2, value: String, color: Color, size: int) -> void:
	var w := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, pos - Vector2(w * 0.5, 0.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
