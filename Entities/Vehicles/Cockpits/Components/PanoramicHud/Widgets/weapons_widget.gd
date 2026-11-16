class_name WeaponsWidget
extends HudWidget

## Weapons symbology, from the suit's FireControl:
##
##   status        master mode and ARM / SAFE in boxes, the selected weapon with its rounds
##                 and RDY, the vulcans, the sensor of interest
##   envelope      where the selected weapon can point (fixed to the suit's body): a faint
##                 outline with a bold bracket at each corner. Outside it, no shot
##   gun cross     where the barrel points right now (it takes time to swing)
##   lead diamond  where to shoot to hit the locked target; a line joins the gun cross to
##                 it until they meet, then SHOOT. Amber with OUT when the lead is outside
##                 the envelope: turn the suit
##   vulcan ring   the head guns' aim and envelope, while they are spun up
##   designation   the HUD cursor (open cross) or the pilot's line of sight (ring), by the
##                 sensor of interest; brackets pulse on the lock candidate and sit solid
##                 on the locked target
##   HIT / BLOCK   when a shot lands on the suit or on the shield

@export var status_azimuth_deg: float = 20.0
@export var status_elevation_deg: float = -5.5
@export var cue_elevation_deg: float = -15.0
@export var envelope_step_deg: float = 4.0
@export var corner_deg: float = 4.0
@export var hit_cue_time: float = 0.9

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
	if _contacts != null:
		_contacts.selected = _fcs.locked
	_body = hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	_draw_status()
	_draw_designation()
	_draw_lock_marks()
	_draw_hit_cue()
	if not _fcs.is_weapons_mode():
		return
	var vulcan := _fcs.get_vulcan()
	if vulcan != null and vulcan.readiness > 0.0:
		_draw_vulcan(vulcan)
	if _fcs.selected != null:
		_draw_envelope(_fcs.selected, 1.0)
		_draw_solution(_fcs.selected)


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
		y += 20.0
	text(Vector2(0, y), "SOI %s" % ("HMCS" if _fcs.soi == FireControl.Soi.HMCS else "HUD"), dim, HORIZONTAL_ALIGNMENT_LEFT, 12)
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


# --- Envelope, gun cross, lead ---

func _draw_envelope(weapon: MsWeapon, strength: float) -> void:
	var color := hud.equipment_color
	var faint := Color(color, color.a * 0.4 * strength)
	var pts := PackedVector2Array()
	for angles in weapon.get_envelope_outline(envelope_step_deg):
		pts.append(_canvas(angles))
	seam_safe_polyline(pts, faint, 1.5, false)
	# A bold bracket at each corner.
	var az := weapon.az_limits
	var el := weapon.el_limits
	for corner in [Vector2(az.x, el.x), Vector2(az.y, el.x), Vector2(az.y, el.y), Vector2(az.x, el.y)]:
		var inward := Vector2(1.0 if corner.x == az.x else -1.0, 1.0 if corner.y == el.x else -1.0)
		for leg in [Vector2(inward.x * corner_deg, 0.0), Vector2(0.0, inward.y * corner_deg)]:
			var run := PackedVector2Array()
			for k in 5:
				run.append(_canvas(corner + leg * (k / 4.0)))
			seam_safe_polyline(run, Color(color, color.a * strength), 2.5)


func _draw_solution(weapon: MsWeapon) -> void:
	var ready := weapon.state == MsWeapon.State.READY
	var c := hud.primary_color if ready else PanoramicHud.dimmed(hud.primary_color)
	# The gun line, at the target's range when there is one (the arm sits off the sensor).
	var gun_dir := _body * SpatialMath.angles_to_direction(weapon.aim)
	var gun_world := gun_dir
	if weapon.solution_valid:
		gun_world = weapon.get_muzzle_position() + gun_dir * (weapon.time_of_flight * maxf(weapon.projectile.speed, 1.0)) \
				- hud.get_view_origin()
	var gun := patch(hud.world_to_display(gun_world), Vector3.UP)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		patch_line(gun, d * 0.55, d * 1.5, c, 2.0, 1)

	if _fcs.locked == null:
		return
	if not weapon.solution_valid:
		var at := patch(hud.world_to_display(_fcs.get_target_position() - hud.get_view_origin()), Vector3.UP)
		var why := _fcs.get_track_label()
		patch_text(at, Vector2(0.0, -4.2), why if why != "" else "NO SOLUTION", hud.caution_color, HORIZONTAL_ALIGNMENT_CENTER, 13)
		return
	var lead_world := weapon.lead_point - hud.get_view_origin()
	var lead := patch(hud.world_to_display(lead_world), Vector3.UP)
	var shoot := weapon.on_target and ready
	var color := hud.primary_color
	if not weapon.target_in_envelope:
		color = hud.caution_color
	elif not shoot:
		color = PanoramicHud.dimmed(hud.primary_color)
	var k := 1.05
	var diamond := PackedVector2Array([Vector2(0, k), Vector2(k, 0), Vector2(0, -k), Vector2(-k, 0), Vector2(0, k)])
	for i in 4:
		patch_line(lead, diamond[i], diamond[i + 1], color, 2.5 if shoot else 1.8, 1)
	if shoot:
		patch_polygon(lead, PackedVector2Array([Vector2(0, 0.35), Vector2(0.35, 0), Vector2(0, -0.35), Vector2(-0.35, 0)]), color)
	else:
		# How far the barrel still has to swing.
		var a := hud.world_to_display(gun_world).normalized()
		var b := hud.world_to_display(lead_world).normalized()
		if a.angle_to(b) > deg_to_rad(2.2):
			var run := PackedVector2Array()
			for i in 9:
				var u := lerpf(0.12, 0.88, i / 8.0)
				run.append(hud.projector.direction_to_canvas(a.slerp(b, u)))
			seam_safe_polyline(run, Color(color, color.a * 0.6), 1.2, false)
	var cue := ""
	if not weapon.target_in_envelope:
		cue = "OUT"
	elif shoot:
		cue = "SHOOT" if _fcs.master_arm else "SAFE"
	if cue != "":
		patch_text(lead, Vector2(0.0, 1.9), cue, hud.suit_accent_color if cue == "SHOOT" else color,
				HORIZONTAL_ALIGNMENT_CENTER, 16 if cue == "SHOOT" else 13)
	patch_text(lead, Vector2(-1.6, -0.3), "%.1fs" % weapon.time_of_flight, PanoramicHud.dimmed(color), HORIZONTAL_ALIGNMENT_RIGHT, 12)


func _draw_vulcan(weapon: MsWeapon) -> void:
	_draw_envelope(weapon, 0.55 * weapon.readiness)
	var c := hud.primary_color if weapon.state == MsWeapon.State.READY else PanoramicHud.dimmed(hud.primary_color)
	var gun := patch(hud.world_to_display(_body * SpatialMath.angles_to_direction(weapon.aim)), Vector3.UP)
	patch_arc(gun, Vector2.ZERO, 0.8, 0.0, TAU, c, 1.8, 20)
	if weapon.on_target:
		patch_polygon(gun, PackedVector2Array([Vector2(0, 0.22), Vector2(0.22, 0), Vector2(0, -0.22), Vector2(-0.22, 0)]), c)


# --- Designation and lock ---

func _draw_designation() -> void:
	var c := Color(hud.selected_color, hud.selected_color.a * 0.75)
	var at := patch(hud.world_to_display(_fcs.get_designation()), Vector3.UP)
	if _fcs.soi == FireControl.Soi.HUD_CURSOR:
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			patch_line(at, d * 0.9, d * 2.3, c, 1.8, 1)
			var across := Vector2(d.y, d.x) * 0.35
			patch_line(at, d * 2.3 - across, d * 2.3 + across, c, 1.8, 1)
	else:
		patch_arc(at, Vector2.ZERO, 1.5, 0.0, TAU, c, 1.5, 24)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			patch_line(at, d * 1.5, d * 2.1, c, 1.5, 1)


func _draw_lock_marks() -> void:
	if _fcs.candidate != null and is_instance_valid(_fcs.candidate) and _fcs.candidate != _fcs.locked:
		var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.018)
		_bracket(_fcs.candidate, Color(hud.selected_color, hud.selected_color.a * pulse), 1.8, 1.25)
	if _fcs.locked != null and is_instance_valid(_fcs.locked):
		_bracket(_fcs.locked, hud.selected_color, 2.6, 1.45)


## Corner brackets of a square around a contact.
func _bracket(contact: Node3D, color: Color, width: float, fit: float) -> void:
	var rel := contact.get_global_transform_interpolated().origin - hud.get_view_origin()
	var dist := rel.length()
	if dist < 1.0:
		return
	var radius: float = contact.get_meta(&"hud_radius", 20.0)
	var half := clampf(rad_to_deg(atan(radius / dist)) * fit, 2.6, 30.0)
	var at := patch(hud.world_to_display(rel), Vector3.UP)
	var leg := half * 0.4
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(half * sx, half * sy)
			patch_line(at, corner, corner - Vector2(leg * sx, 0.0), color, width, 2)
			patch_line(at, corner, corner - Vector2(0.0, leg * sy), color, width, 2)


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


## Canvas position of a direction given as azimuth / elevation in the suit's body frame.
func _canvas(angles: Vector2) -> Vector2:
	return hud.world_dir_to_canvas(_body * SpatialMath.angles_to_direction(angles))
