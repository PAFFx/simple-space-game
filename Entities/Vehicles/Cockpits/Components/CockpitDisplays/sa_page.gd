class_name SaPage
extends MfdPage

## Situational awareness, like a fighter's tactical situation display: a plan view
## centred on the suit, heading up, over the HUD's attitude plane (the horizon the
## flight computer holds level to). Contacts (group `hud_contacts`) are diamonds with
## range and how far above (+) or below (−) that plane they are; the suit's own velocity
## is a leader line. The range scale steps to fit the farthest contact.
##
## It has a cursor: as the sensor of interest (red border) the cursor slew moves it over
## the map and lock takes the contact under it. Hidden while a target is locked.

const RANGES := [500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0, 100000.0, 200000.0]

@export var contact_group: StringName = &"hud_contacts"
## Cursor slew at full deflection, px/s, and how near a contact it must be to pick it, px.
@export var cursor_rate: float = 260.0
@export var cursor_pick_px: float = 26.0

var _range := 5000.0
var _fcs: FireControl
## Cursor, px from the plan view's centre.
var _cursor := Vector2(0.0, -60.0)
## Contacts' places on the page as last drawn.
var _drawn := {}


func _init() -> void:
	# The compass rose turns with the suit: fast enough to follow a turn smoothly.
	refresh_hz = 30.0
	has_cursor = true


func setup(p_vehicle: VehicleBase) -> void:
	super.setup(p_vehicle)
	_fcs = vehicle.find_component(FireControl) as FireControl if vehicle != null else null


func soi_slew(slew: Vector2, delta: float) -> void:
	var half := Vector2(size.x * 0.48, size.y * 0.42)
	_cursor = (_cursor + Vector2(slew.x, -slew.y) * cursor_rate * delta).clamp(-half, half)


func soi_candidate() -> Node3D:
	var best: Node3D = null
	var best_d := cursor_pick_px
	for node: Node3D in _drawn:
		if not is_instance_valid(node):
			continue
		var d: float = (_drawn[node] as Vector2).distance_to(_cursor)
		if d < best_d:
			best_d = d
			best = node
	return best


func soi_reset() -> void:
	_cursor = Vector2(0.0, -60.0)


func draw_page() -> void:
	var hud_basis := fc.get_attitude_basis()
	var body_pos := vehicle.get_global_transform_interpolated().origin
	var fwd := -vehicle.get_global_transform_interpolated().basis.z
	var local_fwd := hud_basis.inverse() * fwd
	var heading := atan2(local_fwd.x, -local_fwd.z)  # + = right of north

	var centre := Vector2(size.x * 0.5, size.y * 0.56)
	var radius := size.y * 0.4
	var contacts: Array = []
	var farthest := 0.0
	for node in get_tree().get_nodes_in_group(contact_group):
		var n := node as Node3D
		if n == null or n == vehicle:
			continue
		var rel := hud_basis.inverse() * (n.get_global_transform_interpolated().origin - body_pos)
		contacts.append([n, rel])
		farthest = maxf(farthest, Vector2(rel.x, rel.z).length())
	_range = RANGES[-1]
	for r in RANGES:
		if r >= farthest * 1.1:
			_range = r
			break

	# Range rings and compass rose (rotating with heading, so the top is where the suit faces).
	for k in [0.5, 1.0]:
		draw_arc(centre, radius * k, 0.0, TAU, 96, Color(FRAME, 0.7 if k < 1.0 else 1.0), 1.5, true)
	label(centre + Vector2(radius * 0.5 * 0.71 + 6, -radius * 0.5 * 0.71), _fmt_range(_range * 0.5), DIM, 13)
	for deg in range(0, 360, 10):
		var a := deg_to_rad(float(deg)) - heading - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var long := deg % 30 == 0
		draw_line(centre + dir * radius, centre + dir * (radius + (14.0 if long else 7.0)), FRAME, 1.5)
		if long:
			var txt: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(deg, "%02d" % (deg / 10))
			label(centre + dir * (radius + 30.0) + Vector2(0, 6), txt, TEXT if deg % 90 == 0 else DIM, 15,
					HORIZONTAL_ALIGNMENT_CENTER)
	# Heading caret at the top.
	var top := centre + Vector2(0, -radius - 4)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(-8, -14), top + Vector2(8, -14)]), INFO)

	# Own suit and velocity leader.
	_ownship(centre)
	var v := hud_basis.inverse() * fc.state.linear_velocity
	var v2 := _to_screen(Vector2(v.x, v.z), heading)
	if v2.length() > 0.3:
		var lead := v2.normalized() * minf(radius * 0.45, 24.0 + log(v2.length() + 1.0) * 26.0)
		draw_line(centre, centre + lead, GOOD, 2.0, true)
		draw_circle(centre + lead, 4.0, GOOD, true, -1.0, true)

	_drawn.clear()
	for c in contacts:
		_contact(centre, radius, heading, c[0], c[1])
	if is_soi and (_fcs == null or _fcs.is_cursor_shown()):
		_draw_cursor(centre + _cursor)

	_data_strip(heading, fc.state.linear_velocity.length(), contacts.size())


func _contact(centre: Vector2, radius: float, heading: float, node: Node3D, rel: Vector3) -> void:
	var flat := _to_screen(Vector2(rel.x, rel.z), heading)
	var dist := rel.length()
	var p := flat / _range * radius
	var clipped := p.length() > radius
	if clipped:
		p = p.normalized() * radius
	var at := centre + p
	_drawn[node] = p
	var k := 9.0
	var color := Color(CAUTION, 0.6 if clipped else 1.0)
	draw_polyline(PackedVector2Array([at + Vector2(0, -k), at + Vector2(k, 0), at + Vector2(0, k),
			at + Vector2(-k, 0), at + Vector2(0, -k)]), color, 2.0, true)
	var name := String(node.get_meta("hud_label", node.name)).to_upper()
	label(at + Vector2(14, -2), name, color, 14)
	label(at + Vector2(14, 15), "%s  %+.0f" % [_fmt_range(dist), rel.y], Color(color, 0.75), 12)


## The panoramic HUD cursor in small: three double-railed arms round an empty middle.
func _draw_cursor(at: Vector2) -> void:
	for angle in [deg_to_rad(-150.0), deg_to_rad(-30.0), deg_to_rad(90.0)]:
		var along := Vector2(cos(angle), sin(angle))
		var across := Vector2(-along.y, along.x) * 2.5
		for side in [-1.0, 1.0]:
			draw_line(at + along * 9.0 + across * side, at + along * 26.0 + across * side, TEXT, 1.6, true)


func _ownship(at: Vector2) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -13), at + Vector2(9, 10), at + Vector2(0, 5),
			at + Vector2(-9, 10), at + Vector2(0, -13)])
	draw_polyline(pts, INFO, 2.0, true)


func _data_strip(heading: float, speed: float, count: int) -> void:
	draw_rect(Rect2(0, 0, size.x, 44), Color(FRAME, 0.12), true)
	draw_line(Vector2(0, 44), Vector2(size.x, 44), FRAME, 1.0)
	label(Vector2(20, 30), "SA", INFO, 22)
	label(Vector2(size.x * 0.3, 30), "HDG %03d" % (roundi(wrapf(rad_to_deg(heading), 0.0, 360.0)) % 360), TEXT, 18,
			HORIZONTAL_ALIGNMENT_CENTER)
	label(Vector2(size.x * 0.5, 30), "SPD %.0f" % speed, TEXT, 18, HORIZONTAL_ALIGNMENT_CENTER)
	label(Vector2(size.x * 0.7, 30), "RNG %s" % _fmt_range(_range), TEXT, 18, HORIZONTAL_ALIGNMENT_CENTER)
	label(Vector2(size.x - 20, 30), "CTC %d" % count, DIM, 16, HORIZONTAL_ALIGNMENT_RIGHT)


## Plan-view offset (x right, z back in the attitude plane) → heading-up screen offset.
func _to_screen(flat: Vector2, heading: float) -> Vector2:
	# Rotate so the suit's heading points up (screen −y).
	var rotated := flat.rotated(-heading)
	return Vector2(rotated.x, rotated.y)


static func _fmt_range(m: float) -> String:
	return "%.1f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % roundi(m)
