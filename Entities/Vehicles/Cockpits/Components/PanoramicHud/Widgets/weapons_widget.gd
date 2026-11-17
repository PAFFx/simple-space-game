class_name WeaponsWidget
extends HudWidget

## Weapons symbology, from the suit's FireControl. Built to keep the target in plain view:
## nothing is drawn over it but its own contact triangle (ContactsWidget).
##
##   status        master mode and ARM / SAFE in boxes, the selected weapon with its rounds
##                 and RDY, the vulcans
##   cursor        while nothing is locked: the TMS cursor (three double-railed arms round
##                 an empty middle) or the HMCS ring (where the pilot looks), by the sensor
##                 of interest. The HMCS ring closes while a contact is under it. With a
##                 display page as the SOI the TMS cursor drops to one dim rail and holds;
##                 taking the SOI back, a ring sweeps out from the cursor once
##   tail          the locked target's own motion (its estimated velocity, not relative to
##                 the suit, so our own flying doesn't draw one): a fine accent line from its
##                 triangle's edge toward where it will be in `tail_time`
##   gun circle    the shoot cue. It sits where a shot would go relative to the target (the
##                 target's sensor estimate, turned by the barrel's error from the lead) and
##                 its size is how sure that is (the predicted impact error at the time of
##                 flight), never smaller than the target's mark. On the target = a shot;
##                 the smaller, the surer. Dim while the weapon isn't ready
##   vulcan ring   the head guns' aim, while they are spun up
##   zoom window   (FireControl.get_zoom) the sensor head's zoom camera on the locked target
##                 in a framed inset over it, with its level. Only while the head's gimbal
##                 can reach the target (SensorSuite head limits); else GIMBAL under it

@export var status_azimuth_deg: float = 20.0
@export var status_elevation_deg: float = -5.5
@export var cue_elevation_deg: float = -15.0
@export var hit_cue_time: float = 0.9
## Debug: HIT / BLOCK when a shot lands on the suit or on the shield.
@export var show_hit_cue: bool = false

@export_group("Cursors")
@export var cursor_color := Color(0.74, 0.7, 0.86, 0.85)
## TMS arms: from / to this far out, deg; the rails' spacing, deg.
@export var tms_inner_deg: float = 1.3
@export var tms_outer_deg: float = 4.6
@export var tms_rail_gap_deg: float = 0.36
@export var hmcs_radius_deg: float = 4.5
## The SOI take-over sweep: how long, s, and how far out it runs, deg.
@export var soi_sweep_time: float = 0.45
@export var soi_sweep_deg: float = 14.0

@export_group("Target")
## The tail shows where the target goes in this long (relative to the suit), s.
@export var tail_time: float = 2.0
@export var tail_max_deg: float = 10.0
## Below this the target barely moves across the view: no tail, deg.
@export var tail_min_deg: float = 0.25
## The gun circle's least radius, as a share of the target triangle's half side (its
## corners and lock dashes reach ~1.6), plus a margin, deg.
@export var circle_min_share: float = 1.85
@export var circle_margin_deg: float = 0.4
@export var circle_max_deg: float = 25.0

var _fcs: FireControl
var _contacts: ContactsWidget
var _body := Basis.IDENTITY


func draw_widget() -> void:
	if _fcs == null:
		if hud.vehicle == null:
			return
		_fcs = hud.vehicle.find_component(FireControl) as FireControl
		for sibling in get_parent().get_children():
			if sibling is ContactsWidget:
				_contacts = sibling
		if _fcs == null:
			return
	_body = hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	if _contacts != null:
		_contacts.locked_label_x = 0.0
	_draw_status()
	if _fcs.is_cursor_shown():
		_draw_cursor()
	var locked := _fcs.locked != null and is_instance_valid(_fcs.locked)
	if show_hit_cue:
		_draw_hit_cue()
	if _fcs.is_weapons_mode():
		var vulcan := _fcs.get_vulcan()
		if vulcan != null and vulcan.readiness > 0.0:
			_draw_vulcan(vulcan)
		var weapon := _fcs.selected
		if weapon != null:
			if locked and weapon.solution_valid:
				_draw_gun_circle(weapon)
	if locked:
		_draw_tail()
	_update_zoom(locked)


# --- Status block ---

func _draw_status() -> void:
	var c := hud.primary_color
	var dim := PanoramicHud.dimmed(c)
	begin_local(status_azimuth_deg, status_elevation_deg)
	var mode: String = ["NAV", "DGFT", "BVR"][_fcs.mode]
	var x := _boxed(Vector2.ZERO, mode, c)
	if _fcs.master_arm:
		_boxed(Vector2(x + 10.0, 0.0), "ARM", hud.warning_color)
	else:
		text(Vector2(x + 16.0, 0.0), "SAFE", dim, HORIZONTAL_ALIGNMENT_LEFT, 14)
	var y := 30.0
	var weapon := _fcs.selected
	if weapon != null:
		text(Vector2(0, y), weapon.get_hud_name(), hud.equipment_color, HORIZONTAL_ALIGNMENT_LEFT, 16)
		text(Vector2(96, y), "%d" % weapon.ammo, c if weapon.ammo > 0 else hud.warning_color, HORIZONTAL_ALIGNMENT_RIGHT, 18)
		text(Vector2(106, y), _state_label(weapon), _state_color(weapon), HORIZONTAL_ALIGNMENT_LEFT, 13)
		y += 22.0
	var vulcan := _fcs.get_vulcan()
	if vulcan != null and _fcs.is_weapons_mode():
		text(Vector2(0, y), vulcan.get_hud_name(), dim, HORIZONTAL_ALIGNMENT_LEFT, 13)
		text(Vector2(96, y), "%d" % vulcan.ammo, dim if vulcan.ammo > 0 else hud.warning_color, HORIZONTAL_ALIGNMENT_RIGHT, 14)
		if vulcan.readiness > 0.0:
			text(Vector2(106, y), "RDY" if vulcan.state == MsWeapon.State.READY else "SPIN", _state_color(vulcan),
					HORIZONTAL_ALIGNMENT_LEFT, 12)
	end_local()


func _state_label(weapon: MsWeapon) -> String:
	if weapon.ammo <= 0:
		return "EMPTY"
	if not weapon.wanted:
		return "HOLD"
	return "RDY" if weapon.state == MsWeapon.State.READY else "- - -"


func _state_color(weapon: MsWeapon) -> Color:
	if weapon.ammo <= 0:
		return hud.warning_color
	return hud.primary_color if weapon.state == MsWeapon.State.READY else hud.caution_color


## Text in a box, its left edge at `pos`; returns the box's right edge.
func _boxed(pos: Vector2, value: String, color: Color) -> float:
	var size := 15
	var pad := Vector2(6.0, 4.0)
	var w := hud.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var top := pos.y - hud.font.get_ascent(size) - pad.y + 2.0
	var bottom := pos.y + pad.y
	var left := pos.x
	var right := pos.x + w + pad.x * 2.0
	for pt in [[Vector2(left, top), Vector2(right, top)], [Vector2(left, bottom), Vector2(right, bottom)],
			[Vector2(left, top), Vector2(left, bottom)], [Vector2(right, top), Vector2(right, bottom)]]:
		line(pt[0], pt[1], color, 1.5)
	text(Vector2(left + pad.x, pos.y), value, color, HORIZONTAL_ALIGNMENT_LEFT, size)
	return right


# --- Cursors ---

func _draw_cursor() -> void:
	var at := patch(hud.world_to_display(_fcs.get_designation()), Vector3.UP)
	if _fcs.soi == FireControl.Soi.HMCS:
		_draw_hmcs(at, _fcs.candidate != null)
	else:
		_draw_tms(at, _fcs.soi == FireControl.Soi.HUD_CURSOR)
	var since := Time.get_ticks_msec() / 1000.0 - _fcs.soi_changed_at
	if _fcs.soi != FireControl.Soi.MFD and since < soi_sweep_time:
		var u := since / soi_sweep_time
		var c := hud.suit_accent_color
		c.a *= (1.0 - u) * (1.0 - u)
		patch_arc(at, Vector2.ZERO, lerpf(2.0, soi_sweep_deg, sqrt(u)), 0.0, TAU, c, 2.2, 48)


## Three double-railed arms (up-left, up-right, down) pointing at an empty middle, a faint
## fill between the rails, and a small faint Y in the middle. Out of SOI: one dim rail.
func _draw_tms(at: Patch, is_soi: bool) -> void:
	var c := cursor_color
	if not is_soi:
		c = PanoramicHud.dimmed(c)
		for angle in [deg_to_rad(150.0), deg_to_rad(30.0), deg_to_rad(-90.0)]:
			var along := Vector2(cos(angle), sin(angle))
			patch_line(at, along * tms_inner_deg, along * tms_outer_deg, c, 1.4, 2)
		return
	var fill := Color(c, c.a * 0.4)
	var faint := Color(c, c.a * 0.45)
	for angle in [deg_to_rad(150.0), deg_to_rad(30.0), deg_to_rad(-90.0)]:
		var along := Vector2(cos(angle), sin(angle))
		var across := Vector2(-along.y, along.x) * tms_rail_gap_deg * 0.5
		var a := along * tms_inner_deg
		var b := along * tms_outer_deg
		patch_polygon(at, PackedVector2Array([a - across, b - across, b + across, a + across]), fill)
		patch_line(at, a - across, b - across, c, 1.6, 2)
		patch_line(at, a + across, b + across, c, 1.6, 2)
		patch_line(at, along * 0.15, along * 0.55, faint, 1.2, 1)


## A big ring broken at left and right, three short inward ticks lined up with the TMS
## arms, a dot in the middle. The breaks close while a contact is under it.
func _draw_hmcs(at: Patch, on_contact: bool) -> void:
	var c := cursor_color
	var r := hmcs_radius_deg
	if on_contact:
		patch_arc(at, Vector2.ZERO, r, 0.0, TAU, c, 1.6, 64)
	else:
		var gap := deg_to_rad(16.0)
		patch_arc(at, Vector2.ZERO, r, gap, PI - gap, c, 1.6, 28)
		patch_arc(at, Vector2.ZERO, r, PI + gap, TAU - gap, c, 1.6, 28)
	for angle in [deg_to_rad(150.0), deg_to_rad(30.0), deg_to_rad(-90.0)]:
		var along := Vector2(cos(angle), sin(angle))
		patch_line(at, along * r, along * (r - 0.8), c, 1.6, 1)
	patch_polygon(at, PackedVector2Array([Vector2(0, 0.13), Vector2(0.13, 0), Vector2(0, -0.13), Vector2(-0.13, 0)]), c)


# --- Target ---

## Patch coordinates (deg) of a display-frame direction.
func _in_patch(p: Patch, dir: Vector3) -> Vector2:
	var fwd := maxf(dir.dot(p.centre), 1e-4)
	return Vector2(rad_to_deg(atan(dir.dot(p.right) / fwd)), rad_to_deg(atan(dir.dot(p.up) / fwd)))


func _target_half() -> float:
	return _contacts.locked_half if _contacts != null and _contacts.locked_half > 0.0 else 2.0


func _draw_tail() -> void:
	var origin := hud.get_view_origin()
	var rel := _fcs.get_shown_target_position() - origin
	var motion := _fcs.get_target_velocity() * tail_time
	var now_dir := hud.world_to_display(rel).normalized()
	var at := patch(now_dir, Vector3.UP)
	var ahead := _in_patch(at, hud.world_to_display(rel + motion).normalized())
	var length := ahead.length()
	if length < tail_min_deg:
		return
	var dir := ahead / length
	var start := _target_half() * 1.25 + 0.3
	patch_line(at, dir * start, dir * (start + minf(length, tail_max_deg)), hud.suit_accent_color, 1.6, 4)


func _draw_gun_circle(weapon: MsWeapon) -> void:
	var origin := hud.get_view_origin()
	var target := _fcs.get_shown_target_position() - origin
	var dist := target.length()
	if dist < 1.0:
		return
	# Where the barrel is against where it must be, carried over onto the target.
	var gun_dir := _body * SpatialMath.angles_to_direction(weapon.aim)
	var gun_world := weapon.get_muzzle_position() + gun_dir * (weapon.time_of_flight * maxf(weapon.projectile.speed, 1.0)) - origin
	var lead_world := weapon.lead_point - origin
	var turn := Quaternion(lead_world.normalized(), gun_world.normalized())
	var centre := hud.world_to_display(turn * target).normalized()

	# How sure: the impact error across the line of sight at the time of flight (2 sigma).
	var cov := _fcs.get_target_covariance_ahead(weapon.time_of_flight)
	var los := target / dist
	var lateral := sqrt(maxf((cov.x.x + cov.y.y + cov.z.z - los.dot(cov * los)) * 0.5, 0.0))
	var spread := rad_to_deg(atan(2.0 * lateral / weapon.target_range if weapon.target_range > 1.0 else 0.0))
	var radius := clampf(maxf(spread, _target_half() * circle_min_share + circle_margin_deg), 0.5, circle_max_deg)

	var ready := weapon.state == MsWeapon.State.READY and not weapon.masked
	var c := hud.primary_color if ready else PanoramicHud.dimmed(hud.primary_color)
	var at := patch(centre, Vector3.UP)
	var off := _in_patch(patch(hud.world_to_display(target).normalized(), Vector3.UP), centre)
	if _contacts != null:
		_contacts.locked_label_x = radius + maxf(off.x, 0.0) + 0.5
	# Outer ring broken in four, an inner ring broken in two, offset.
	var gap := deg_to_rad(9.0)
	for k in 4:
		var a := k * TAU / 4.0 + deg_to_rad(20.0)
		patch_arc(at, Vector2.ZERO, radius, a + gap, a + TAU / 4.0 - gap, c, 1.5, 16)
	var inner := Color(c, c.a * 0.45)
	var r2 := radius - minf(0.6, radius * 0.08)
	for k in 2:
		var a := k * PI + deg_to_rad(65.0)
		patch_arc(at, Vector2.ZERO, r2, a + gap * 2.0, a + PI - gap * 2.0, inner, 1.0, 24)
	var cue := ""
	if weapon.masked:
		cue = "MASKED"
	elif not _fcs.master_arm:
		cue = "SAFE"
	if cue != "":
		patch_text(at, Vector2(0.0, -radius - 1.6), cue, hud.caution_color if weapon.masked else PanoramicHud.dimmed(c),
				HORIZONTAL_ALIGNMENT_CENTER, 12)


func _update_zoom(locked: bool) -> void:
	var head := hud.sensor_head
	if head == null:
		return
	var mag := _fcs.get_zoom() if locked else 0.0
	var target := _fcs.get_shown_target_position() if locked else Vector3.ZERO
	if mag > 0.0 and not _head_reaches(target):
		mag = 0.0
		var at := patch(hud.world_to_display(target - hud.get_view_origin()).normalized(), Vector3.UP)
		patch_text(at, Vector2(0.0, -_target_half() * 1.6 - 1.6), "GIMBAL", hud.caution_color, HORIZONTAL_ALIGNMENT_CENTER, 12)
	head.set_zoom(target, mag)
	if head.zoom_reveal <= 0.0:
		return
	# The frame: a faint rim, bold corners, the level on a tab over the top left.
	var c := hud.primary_color
	c.a *= head.zoom_reveal
	var half := Vector2(rad_to_deg(atan(head.get_zoom_half_tan().x)), rad_to_deg(atan(head.get_zoom_half_tan().y)))
	var at := patch(hud.world_to_display(head.zoom_direction).normalized(), Vector3.UP)
	var rim := Color(c, c.a * 0.35)
	for e in [[Vector2(-1, -1), Vector2(1, -1)], [Vector2(1, -1), Vector2(1, 1)], [Vector2(1, 1), Vector2(-1, 1)], [Vector2(-1, 1), Vector2(-1, -1)]]:
		patch_line(at, e[0] * half, e[1] * half, rim, 1.0, 8)
	var leg := minf(half.x, half.y) * 0.25
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(half.x * sx, half.y * sy)
			patch_line(at, corner, corner - Vector2(leg * sx, 0.0), c, 2.2, 2)
			patch_line(at, corner, corner - Vector2(0.0, leg * sy), c, 2.2, 2)
	patch_text(at, Vector2(-half.x + 0.3, half.y + 0.9), "×%d" % roundi(head.zoom_magnification), c, HORIZONTAL_ALIGNMENT_LEFT, 14)


## Whether the sensor head's gimbal (the main camera) can turn to `world_point`.
func _head_reaches(world_point: Vector3) -> bool:
	var sensors := _fcs.sensors
	if sensors == null:
		return true
	var a := SpatialMath.direction_to_angles(_body.inverse() * (world_point - hud.get_view_origin()))
	return absf(a.x) <= sensors.head_az_limit_deg and a.y >= sensors.head_el_limits_deg.x and a.y <= sensors.head_el_limits_deg.y


func _draw_vulcan(weapon: MsWeapon) -> void:
	var up := weapon.state == MsWeapon.State.READY and not weapon.masked
	var c := hud.primary_color if up else PanoramicHud.dimmed(hud.primary_color)
	var gun := patch(hud.world_to_display(_body * SpatialMath.angles_to_direction(weapon.aim)), Vector3.UP)
	patch_arc(gun, Vector2.ZERO, 0.8, 0.0, TAU, c, 1.8, 20)
	if weapon.on_target:
		patch_polygon(gun, PackedVector2Array([Vector2(0, 0.22), Vector2(0.22, 0), Vector2(0, -0.22), Vector2(-0.22, 0)]), c)


func _draw_hit_cue() -> void:
	if _fcs.since_hit > hit_cue_time:
		return
	var color := hud.primary_color if _fcs.last_hit_blocked else hud.warning_color
	color.a *= 1.0 - smoothstep(0.5, 1.0, _fcs.since_hit / hit_cue_time)
	if int(Time.get_ticks_msec() / 90) % 2 == 0 and not _fcs.last_hit_blocked:
		color.a *= 0.5
	begin_local(0.0, cue_elevation_deg)
	text(Vector2.ZERO, "BLOCK" if _fcs.last_hit_blocked else "HIT", color, HORIZONTAL_ALIGNMENT_CENTER, 30)
	end_local()
