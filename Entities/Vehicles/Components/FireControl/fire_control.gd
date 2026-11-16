class_name FireControl
extends Node

## The suit's fire control: master arm, master mode, target lock, weapon selection and
## firing. Reads the weapon fields of the PilotCommand the FlightComputer polled this
## tick, and drives the MsWeapons found anywhere under the vehicle.
##
##   master arm   SAFE keeps every trigger dead; symbology stays live.
##   master mode  NAV: weapons stowed. DGFT: weapons out, the beam rifle selected on
##                entry (never the last weapon, which might have been a saber).
##                BVR: reserved; selecting a weapon there doesn't drop to DGFT.
##   two channels the vulcans on their own trigger (always available in a weapons
##                mode), and the selected weapon on weapon release.
##   weapon hat   each direction holds up to two weapons: a press selects the first, a
##                press again while it is selected swaps to the other.
##   lock         with nothing locked, the contact nearest the designation direction (the
##                HUD cursor, or where the pilot looks, by the sensor of interest) is the
##                candidate; lock locks it. Locking never unlocks: unlock does (closing the
##                zoom window first, if it is open). Target cycle steps the lock to the next
##                contact by azimuth. While locked there is no cursor; on unlock it is
##                back straight ahead.
##   shield       while block is held the suit digs in behind it (one fixed guard pose: left
##                side forward, shield upright, knee up). The shield is solid: shots that
##                hit it (the suit's own included) stop there and count as blocked; shots
##                that reach the body are hits. Block wins over the shield's missiles,
##                which can't launch meanwhile.
##
## A weapon points at the lead on the locked target if that is inside its envelope, else
## as near as the envelope allows; with no lock it sits on its boresight. The suit never
## turns itself: bringing a target into the envelope is flying.
##
## With a SensorSuite on the vehicle the lock starts a sensor track, and everything here
## works from the track's estimate (position, velocity, acceleration), never the target
## itself: no solution until the track is firm, and the lock drops when the track is lost.
## Without one, the target's own state is used (a perfect track).

enum MasterMode { NAV, DGFT, BVR }
## Sensor of interest: what the cursor slew and lock act through. MFD = a cockpit display
## page with its own cursor (soi_display), F-16 style.
enum Soi { HUD_CURSOR, HMCS, MFD }
enum Hat { FORWARD, RIGHT, AFT, LEFT, DEPRESS }

## A weapon was selected, or a hat press found nothing to select.
signal hat_pressed(direction: int)
signal selection_changed(weapon: MsWeapon)
signal locked_changed(target: Node3D)
signal shot_fired(weapon: MsWeapon)
## The suit was hit; `blocked` if the shield took it.
signal hit_taken(blocked: bool)

const CONTACT_GROUP := &"hud_contacts"

## Weapon ids on each hat direction (Hat order), first press then second.
@export var hat_layout: Array[Array] = [
	[&"beam_rifle"],
	[&"fin_funnel"],
	[&"bazooka_back", &"bazooka_hand"],
	[&"shield_missile"],
	[&"beam_saber"],
]
## Names for the weapon ring, including weapons that aren't fitted yet.
@export var weapon_labels := {
	&"beam_rifle": "PULSE", &"shield_missile": "MISSILE", &"fin_funnel": "FUNNEL",
	&"bazooka_back": "BZK-B", &"bazooka_hand": "BZK-H", &"beam_saber": "SABER",
}
## Selected on entering DGFT.
@export var dgft_weapon: StringName = &"beam_rifle"
## Weapon that holds the shield up (not a gun; a fixed pose, its muzzle marks the face).
@export var guard_weapon: StringName = &"shield_guard"
@export var torso_bone: StringName = &"spine"
## AMBAC group of the waist. Held while an arm weapon is up: a balancing waist swing makes
## the aimed arm swing back to stay on target, which needs countering again (the thrusters
## kept pulsing while just holding a lock). The legs balance instead.
@export var torso_group: StringName = &"torso"
## Show the suit's own body and weapons on the panoramic screen in a weapons mode (for
## close combat later). Off: the arms and the gun are outlines (SENSOR_COMBAT) instead.
@export var show_body_in_weapons_mode: bool = false
@export var master_arm: bool = false
@export var mode := MasterMode.NAV
@export var soi := Soi.HUD_CURSOR

@export_group("Lock")
@export var lock_range: float = 20000.0
## A contact is designated within this angle of the cursor / the pilot's look, deg
## (plus its own apparent size).
@export var cursor_cone_deg: float = 5.0
@export var hmcs_cone_deg: float = 9.0
## HUD cursor slew at full deflection, deg/s; it wraps round in azimuth and stops short of
## straight up / down.
@export var cursor_rate_deg: float = 45.0
@export var cursor_elevation_limit_deg: float = 85.0
## The locked target as shown on the HUD: the track's estimate, dead-reckoned between
## ticks and low-passed so its noise doesn't shake the symbols. Cutoff, Hz, rising by
## `shown_beta` per degree the estimate is away from what is shown (a real jump catches up).
@export var shown_cutoff_hz: float = 1.5
@export var shown_beta: float = 4.0
## Line-of-sight checks to every contact, per second: one hidden behind something
## (not the suit itself) isn't shown and can't be designated.
@export var line_of_sight_hz: float = 10.0
## Zoom window levels (magnification), cycled by the zoom control.
@export var zoom_levels := PackedFloat32Array([2.0, 4.0, 8.0])

var weapons := {}                     ## id → MsWeapon
var selected: MsWeapon
var locked: Node3D
var candidate: Node3D
## HUD cursor, azimuth / elevation in the display's frame, deg.
var cursor := Vector2.ZERO
## The display page that is the SOI when soi is MFD (an MfdPage with has_cursor).
var soi_display: Object
## Time.get_ticks_msec() / 1000 when the SOI last changed (the HUD's take-over sweep).
var soi_changed_at := -INF
var _soi_displays: Array[Object] = []
## Zoom window: 0 = closed, else an index + 1 into zoom_levels.
var zoom_level := 0
var blocking := false
## Seconds since the suit was last hit, and whether the shield took it.
var since_hit := INF
var last_hit_blocked := false

var vehicle: VehicleBase
var flight_computer: FlightComputer
var loadout: MsLoadout
var _body: RigidBody3D
var _rids: Array[RID] = []
var _aimed: Array[MsWeapon] = []
var _stowed := {}                     ## MsEquipment taken off → its weapons
var _ambac: AmbacController
var _torso_held := false
var _target_velocity := Vector3.ZERO
var _target_last := Vector3.ZERO
var _target_tracked := false
var sensors: SensorSuite
var _target_position := Vector3.ZERO
var _target_acceleration := Vector3.ZERO
var _shown := Vector3.ZERO
var _shown_valid := false
var _hidden := {}                     ## instance id of a contact out of sight → true
var _los_due := 0.0

## Track quality on the HUD (the lock's corner dashes).
enum TrackMark { NONE, COAST, POOR, GOOD }


func _ready() -> void:
	# After the FlightComputer has polled this tick's command.
	process_physics_priority = 5
	vehicle = VehicleBase.find_vehicle(self)
	if vehicle == null:
		push_error("FireControl: not inside a vehicle")
		return
	_body = vehicle as Node as RigidBody3D
	if _body != null:
		_rids = [_body.get_rid()]
	flight_computer = vehicle.find_component(FlightComputer) as FlightComputer
	_ambac = vehicle.find_component(AmbacController) as AmbacController
	loadout = vehicle.find_component(MsLoadout) as MsLoadout
	sensors = vehicle.find_component(SensorSuite) as SensorSuite
	if loadout != null:
		loadout.listen_for_input = false   # equipment is raised by weapon selection instead
	if vehicle.has_signal(&"hit_taken"):
		vehicle.connect(&"hit_taken", _on_vehicle_hit)
	_setup.call_deferred()


## Once the loadout has mounted its equipment: find the weapons, hook up the aim.
func _setup() -> void:
	var skeleton := loadout.skeleton if loadout != null else null
	for node in vehicle.find_children("*", "Node3D", true, false):
		var weapon := node as MsWeapon
		if weapon == null:
			continue
		if weapon.mount_bone != &"" and skeleton != null:
			_mount(weapon, skeleton)
		weapons[weapon.weapon_id] = weapon
		if weapon.aim_bone != &"":
			_aimed.append(weapon)
	if loadout != null:
		loadout.equipment_fitted.connect(_on_equipment_fitted)
	if skeleton != null and not _aimed.is_empty():
		var modifier := WeaponAimModifier.new()
		modifier.name = "WeaponAimModifier"
		modifier.fire_control = self
		skeleton.add_child(modifier)
	_apply_mode()


## Equipment taken off (test range): its weapons leave the fire control until it is back.
func _on_equipment_fitted(eq: MsEquipment, on: bool) -> void:
	if on:
		for weapon: MsWeapon in _stowed.get(eq, []):
			weapons[weapon.weapon_id] = weapon
			if weapon.aim_bone != &"":
				_aimed.append(weapon)
		_stowed.erase(eq)
		if selected == null and mode == MasterMode.DGFT:
			select(get_weapon(dgft_weapon))
		return
	var gone: Array[MsWeapon] = []
	for weapon: MsWeapon in weapons.values():
		if weapon.equipment == eq:
			gone.append(weapon)
	for weapon in gone:
		weapon.wanted = false
		weapon.triggered = false
		weapon.readiness = 0.0
		weapon.update(0.0, self)
		weapons.erase(weapon.weapon_id)
		_aimed.erase(weapon)
		if weapon == selected:
			select(null)
	_stowed[eq] = gone


func is_weapons_mode() -> bool:
	return mode != MasterMode.NAV


func get_body() -> RigidBody3D:
	return _body


func get_own_rids() -> Array[RID]:
	return _rids


func get_body_basis() -> Basis:
	return _body.global_basis.orthonormalized() if _body != null else vehicle.global_basis.orthonormalized()


func get_own_velocity() -> Vector3:
	return _body.linear_velocity if _body != null else Vector3.ZERO


## Where the fire control believes the locked target is (the track's estimate).
func get_target_position() -> Vector3:
	if locked == null:
		return Vector3.ZERO
	return _target_position if _has_track() else locked.global_position


func get_target_velocity() -> Vector3:
	return _target_velocity


func get_target_acceleration() -> Vector3:
	return _target_acceleration


## Whether the target is known well enough to shoot at.
func has_target_solution() -> bool:
	if locked == null:
		return false
	return sensors.track.has_solution() if _has_track() else true


## Covariance (m²) of where the target will be `ahead` s from now (zero without sensors).
func get_target_covariance_ahead(ahead: float) -> Basis:
	if not _has_track():
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	return sensors.track.get_position_covariance_ahead(sensors.get_time(), ahead)


## "" with a firm track (or none needed), else what the track is doing.
func get_track_label() -> String:
	if locked == null or not _has_track():
		return ""
	match sensors.track.state:
		SensorTrack.State.TENTATIVE:
			return "ACQUIRING"
		SensorTrack.State.COAST:
			return "COAST"
		SensorTrack.State.LOST:
			return "LOST"
	return ""


## Where the HUD draws the locked target: the estimate, smoothed (see shown_cutoff_hz).
func get_shown_target_position() -> Vector3:
	return _shown if _shown_valid else get_target_position()


## Two-sigma angular error of the target's position across the line of sight, deg (0
## without sensors).
func get_target_angular_error_deg() -> float:
	if locked == null or not _has_track():
		return 0.0
	var est := sensors.track.get_estimate(sensors.get_time())
	var rel: Vector3 = est[0] - get_view_origin()
	var dist := rel.length()
	if dist < 1.0:
		return 0.0
	var cov: Basis = est[3]
	var los := rel / dist
	var along := los.dot(cov * los)
	var trace := cov.x.x + cov.y.y + cov.z.z
	var lateral := sqrt(maxf((trace - along) * 0.5, 0.0))
	return rad_to_deg(atan(2.0 * lateral / dist))


func get_track_mark() -> TrackMark:
	if locked == null:
		return TrackMark.NONE
	if not _has_track():
		return TrackMark.GOOD
	match sensors.track.state:
		SensorTrack.State.COAST, SensorTrack.State.LOST:
			return TrackMark.COAST
		SensorTrack.State.TENTATIVE:
			return TrackMark.POOR
	var cov: Basis = sensors.track.get_estimate(sensors.get_time())[3]
	var sigma := sqrt(maxf((cov.x.x + cov.y.y + cov.z.z) / 3.0, 0.0))
	return TrackMark.GOOD if sigma < get_target_radius() else TrackMark.POOR


func _process(delta: float) -> void:
	if locked == null:
		_shown_valid = false
		return
	# Rendering is interpolated a tick behind the physics state the estimate is at.
	var tick := 1.0 / Engine.physics_ticks_per_second
	var lag := (1.0 - Engine.get_physics_interpolation_fraction()) * tick
	var est := get_target_position() - _target_velocity * lag
	var dist := maxf(est.distance_to(get_view_origin()), 1.0)
	if not _shown_valid:
		_shown = est
		_shown_valid = true
		return
	_shown += _target_velocity * delta
	var off_deg := rad_to_deg(_shown.distance_to(est) / dist)
	if off_deg > 3.0:
		_shown = est
		return
	var cutoff := shown_cutoff_hz + shown_beta * off_deg
	_shown = _shown.lerp(est, 1.0 - exp(-delta * TAU * cutoff))


func _has_track() -> bool:
	return sensors != null and sensors.enabled and sensors.track != null and sensors.track.is_started()


func get_target_radius() -> float:
	return locked.get_meta(&"hud_radius", 10.0) if locked != null else 10.0


func get_aimed_weapons() -> Array[MsWeapon]:
	return _aimed


## Torso twist toward the selected weapon's aim, deg (+ = right).
func get_torso_yaw() -> float:
	var yaw := 0.0
	for weapon in _aimed:
		if weapon.torso_share > 0.0:
			yaw += weapon.torso_yaw
	return yaw


func get_vulcan() -> MsWeapon:
	for weapon: MsWeapon in weapons.values():
		if weapon.always_on:
			return weapon
	return null


## Weapon fitted for a hat entry, or null (not fitted yet).
func get_weapon(id: StringName) -> MsWeapon:
	return weapons.get(id)


## Where the designation points, world direction: the HUD cursor or the pilot's look.
func get_designation() -> Vector3:
	if soi == Soi.HMCS:
		var camera := _pilot_camera()
		if camera != null:
			return -camera.global_basis.z
	return _display_basis() * SpatialMath.angles_to_direction(cursor)


## Where lock directions are measured from: the suit's head sensor.
func get_view_origin() -> Vector3:
	var head := vehicle.get_sensor_head() if vehicle.get_sensor_head_mount() != null else null
	return head.global_position if head != null else vehicle.global_position


func rearm() -> void:
	for weapon: MsWeapon in weapons.values():
		weapon.rearm()


func set_mode(value: MasterMode) -> void:
	if value == mode:
		return
	mode = value
	_apply_mode()


func select(weapon: MsWeapon) -> void:
	if weapon == selected:
		return
	# Another mode of the same gun (pulse ↔ linear): it is already up.
	if selected != null and weapon != null and weapon.equipment != null \
			and weapon.equipment == selected.equipment and weapon.pose == selected.pose:
		weapon.take_over(selected)
	selected = weapon
	selection_changed.emit(weapon)


func lock(target: Node3D) -> void:
	if target == locked:
		return
	if is_instance_valid(locked) and locked.tree_exiting.is_connected(_on_target_gone):
		locked.tree_exiting.disconnect(_on_target_gone)
	locked = target
	if target == null:
		_reset_cursors()
	else:
		# Destroyed or despawned: drop the lock at once, before anything draws it.
		target.tree_exiting.connect(_on_target_gone)
	_target_tracked = false
	_target_velocity = Vector3.ZERO
	_target_acceleration = Vector3.ZERO
	if sensors != null:
		sensors.set_target(target)
	locked_changed.emit(target)


func _on_target_gone() -> void:
	locked = null
	_reset_cursors()
	candidate = null
	_target_tracked = false
	if sensors != null:
		sensors.set_target(null)
	locked_changed.emit(null)


func _physics_process(delta: float) -> void:
	if vehicle == null or flight_computer == null or flight_computer.input_source == null:
		return
	var cmd := flight_computer.input_source.last_command
	since_hit += delta
	if cmd.master_arm == 2:
		master_arm = not master_arm
	elif cmd.master_arm != 0:
		master_arm = cmd.master_arm > 0
	if cmd.master_mode >= 0:
		set_mode(cmd.master_mode as MasterMode)
	if cmd.weapon_select >= 0:
		_press_hat(cmd.weapon_select)
	if cmd.soi_cycle:
		cycle_soi()
	if is_cursor_shown() and soi == Soi.MFD:
		soi_display.call(&"soi_slew", cmd.cursor_slew, delta)
	elif is_cursor_shown() and soi == Soi.HUD_CURSOR:
		cursor += cmd.cursor_slew * cursor_rate_deg * delta
		cursor.x = wrapf(cursor.x, -180.0, 180.0)
		cursor.y = clampf(cursor.y, -cursor_elevation_limit_deg, cursor_elevation_limit_deg)

	_los_due -= delta
	if _los_due <= 0.0:
		_los_due = 1.0 / maxf(line_of_sight_hz, 0.1)
		_update_line_of_sight()
	_update_lock(cmd)
	if sensors != null:
		sensors.step(delta)
		if locked != null and sensors.track != null and sensors.track.state == SensorTrack.State.LOST:
			lock(null)
	_track_target(delta)

	blocking = cmd.shield_block
	var guard := get_weapon(guard_weapon)
	for weapon: MsWeapon in weapons.values():
		if weapon == guard:
			weapon.wanted = blocking
		elif weapon.always_on:
			weapon.wanted = is_weapons_mode() and cmd.vulcan_ready
			weapon.triggered = master_arm and is_weapons_mode() and cmd.vulcan_fire
		else:
			# The shield can't fire its missiles while it is held up.
			var held := blocking and guard != null and weapon.equipment == guard.equipment
			weapon.wanted = weapon == selected and is_weapons_mode() and not held
			weapon.triggered = master_arm and weapon.wanted and cmd.fire_main
	_apply_poses(guard)
	var shield_up := blocking and guard != null and guard.readiness > 0.0
	for weapon: MsWeapon in weapons.values():
		weapon.guarded = shield_up
		weapon.update(delta, self)
	_hold_torso()


func _hold_torso() -> void:
	if _ambac == null or torso_group == &"":
		return
	var held := false
	for weapon in _aimed:
		if not weapon.always_on and weapon.aim_weight > 0.0:
			held = true
	if held == _torso_held:
		return
	_torso_held = held
	if held:
		_ambac.lock_group(torso_group)
	else:
		_ambac.unlock_group(torso_group)


func _apply_mode() -> void:
	_show_body_on_screen()
	if mode == MasterMode.NAV:
		select(null)
	elif mode == MasterMode.DGFT:
		select(get_weapon(dgft_weapon))


## In a weapons mode the panoramic screen outlines the arms and the gun, so a shot is seen
## leaving the rifle (or shows the whole body, show_body_in_weapons_mode); in NAV the view
## is clear. Shield and funnels are outlines throughout.
func _show_body_on_screen() -> void:
	var sensor := vehicle.get_sensor_head() if vehicle.get_sensor_head_mount() != null else null
	if sensor != null:
		var layers := 0
		if is_weapons_mode():
			layers = Layers.SENSOR_BODY_PARTS if show_body_in_weapons_mode else Layers.SENSOR_COMBAT
		# Resolves in (and breaks up) as blue blocks: see SensorHead.set_overlay.
		sensor.set_overlay(layers)


## Each equipment takes the pose of the weapon that wants it; the guard comes first.
func _apply_poses(guard: MsWeapon) -> void:
	var poses := {}
	var carriers := {}
	for weapon: MsWeapon in weapons.values():
		if weapon.equipment == null:
			continue
		carriers[weapon.equipment] = true
		if weapon.wanted and (weapon == guard or not poses.has(weapon.equipment)):
			poses[weapon.equipment] = weapon.pose
	for eq: MsEquipment in carriers:
		if poses.has(eq):
			eq.active_pose = poses[eq]
		eq.set_active(poses.has(eq))


func _press_hat(direction: int) -> void:
	var slot: Array = hat_layout[direction] if direction < hat_layout.size() else []
	var fitted: Array[MsWeapon] = []
	for id: StringName in slot:
		if weapons.has(id):
			fitted.append(weapons[id])
	if not fitted.is_empty():
		var at := fitted.find(selected)
		var pick := fitted[(at + 1) % fitted.size()] if at >= 0 else fitted[0]
		# Selecting a weapon is asking for a fight, except in BVR.
		if mode == MasterMode.NAV:
			mode = MasterMode.DGFT
			_show_body_on_screen()
		select(pick)
	hat_pressed.emit(direction)


## A display page with a cursor that can take the SOI (MfdPage.has_cursor).
func register_soi_display(page: Object) -> void:
	if not _soi_displays.has(page):
		_soi_displays.append(page)


## Next SOI: the HUD cursor, the HMCS, then each display page with a cursor.
func cycle_soi() -> void:
	var order: Array = [Soi.HUD_CURSOR, Soi.HMCS]
	order.append_array(_soi_displays)
	var at := order.find(soi_display if soi == Soi.MFD else soi)
	var next: Variant = order[(at + 1) % order.size()]
	if next is Object:
		soi = Soi.MFD
		soi_display = next
	else:
		soi = next
		soi_display = null
	for page in _soi_displays:
		page.set(&"is_soi", page == soi_display)
	cursor = Vector2.ZERO
	soi_changed_at = Time.get_ticks_msec() / 1000.0


func _reset_cursors() -> void:
	zoom_level = 0
	cursor = Vector2.ZERO
	for page in _soi_displays:
		page.call(&"soi_reset")


## The designation cursor (TMS or HMCS) shows, and designates, only while nothing is locked.
func is_cursor_shown() -> bool:
	return locked == null


## The zoom window's magnification, or 0 when it is closed.
func get_zoom() -> float:
	return zoom_levels[zoom_level - 1] if zoom_level > 0 and locked != null else 0.0


func _update_lock(cmd: PilotCommand) -> void:
	if cmd.unlock and locked != null:
		if zoom_level > 0:
			zoom_level = 0
		else:
			lock(null)
	if cmd.target_cycle != 0:
		var next := _next_by_azimuth(cmd.target_cycle)
		if next != null:
			lock(next)
	candidate = _find_candidate() if is_cursor_shown() else null
	if cmd.lock_commit and candidate != null:
		lock(candidate)
	if cmd.zoom and locked != null:
		zoom_level = zoom_level % zoom_levels.size() + 1


## The contact next to the locked one (or the designation) by azimuth in the display
## frame: `step` 1 = the nearest further right, -1 = left, wrapping round.
func _next_by_azimuth(step: int) -> Node3D:
	var origin := get_view_origin()
	var to_display := _display_basis().inverse()
	var from := get_designation() if locked == null else get_target_position() - origin
	var from_az := SpatialMath.direction_to_angles(to_display * from).x
	var best: Node3D = null
	var best_turn := INF
	for contact in _lockable_contacts(origin):
		if contact == locked:
			continue
		var az := SpatialMath.direction_to_angles(to_display * (contact.global_position - origin)).x
		var turn := fposmod((az - from_az) * step, 360.0)
		if turn < best_turn:
			best_turn = turn
			best = contact
	return best


## False while something other than the suit itself stands between its head and `contact`.
func can_see(contact: Node3D) -> bool:
	return not _hidden.has(contact.get_instance_id())


func _update_line_of_sight() -> void:
	_hidden.clear()
	var origin := get_view_origin()
	var space := vehicle.get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group(CONTACT_GROUP):
		var contact := node as Node3D
		if contact == null or contact == vehicle:
			continue
		if not _line_clear(space, origin, contact):
			_hidden[contact.get_instance_id()] = true


func _line_clear(space: PhysicsDirectSpaceState3D, from: Vector3, contact: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, contact.global_position)
	var exclude: Array[RID] = _rids.duplicate()
	if contact is CollisionObject3D:
		exclude.append((contact as CollisionObject3D).get_rid())
	for i in 4:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider := hit.collider as Node
		if collider == null or collider == contact or contact.is_ancestor_of(collider) or collider.is_ancestor_of(contact):
			return true
		# The suit's own shield and equipment don't hide anything from the HUD.
		if not (vehicle as Node).is_ancestor_of(collider) or not (collider is CollisionObject3D):
			return false
		exclude.append((collider as CollisionObject3D).get_rid())
	return true


## Contacts that can be designated: in range and in sight, not the suit itself.
func _lockable_contacts(origin: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(CONTACT_GROUP):
		var contact := node as Node3D
		if contact == null or contact == vehicle:
			continue
		var dist := contact.global_position.distance_to(origin)
		if dist >= 1.0 and dist <= lock_range and can_see(contact):
			out.append(contact)
	return out


## The contact nearest the designation, within the designation cone and lock range (or,
## with a display page as the SOI, the one under that page's cursor).
func _find_candidate() -> Node3D:
	if soi == Soi.MFD and soi_display != null:
		var picked := soi_display.call(&"soi_candidate") as Node3D
		return picked if picked != null and _lockable_contacts(get_view_origin()).has(picked) else null
	var origin := get_view_origin()
	var dir := get_designation()
	var cone := hmcs_cone_deg if soi == Soi.HMCS else cursor_cone_deg
	var best: Node3D = null
	var best_score := INF
	for contact in _lockable_contacts(origin):
		var rel := contact.global_position - origin
		var dist := rel.length()
		var radius: float = contact.get_meta(&"hud_radius", 10.0)
		var off := rad_to_deg(dir.angle_to(rel)) - rad_to_deg(atan(radius / dist))
		if off <= cone and off < best_score:
			best_score = off
			best = contact
	return best


## The locked target's state: the sensor track's estimate, or without sensors its own
## velocity if it reports one, else from its motion.
func _track_target(delta: float) -> void:
	if locked == null:
		return
	if _has_track():
		var est := sensors.track.get_estimate(sensors.get_time())
		_target_position = est[0]
		_target_velocity = est[1]
		_target_acceleration = est[2]
		return
	_target_acceleration = Vector3.ZERO
	if locked is RigidBody3D:
		_target_velocity = (locked as RigidBody3D).linear_velocity
	elif locked.has_method(&"get_velocity"):
		_target_velocity = locked.call(&"get_velocity")
	else:
		var at := locked.global_position
		if _target_tracked and delta > 0.0:
			_target_velocity = _target_velocity.lerp((at - _target_last) / delta, 0.2)
		_target_last = at
		_target_tracked = true


func _pilot_camera() -> Camera3D:
	var cockpit := vehicle.get_cockpit() if vehicle.get_cockpit_mount() != null else null
	return cockpit.get_player_camera() if cockpit != null else null


func _display_basis() -> Basis:
	var cockpit := vehicle.get_cockpit() if vehicle.get_cockpit_mount() != null else null
	var screen := cockpit.get_panoramic_screen() if cockpit != null else null
	return screen.get_display_basis() if screen != null else get_body_basis()


## Puts a self-mounting weapon (mount_bone) on its bone, at mount_position in the body frame.
func _mount(weapon: MsWeapon, skeleton: Skeleton3D) -> void:
	var bone := skeleton.find_bone(weapon.mount_bone)
	if bone < 0:
		push_error("FireControl: bone '%s' not found for %s" % [weapon.mount_bone, weapon.name])
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Mount_%s" % weapon.name
	attach.bone_name = weapon.mount_bone
	skeleton.add_child(attach)
	var skel_in_body := vehicle.global_transform.affine_inverse() * skeleton.global_transform
	var bone_in_body := skel_in_body * skeleton.get_bone_global_rest(bone)
	weapon.reparent(attach, false)
	weapon.transform = bone_in_body.affine_inverse() * Transform3D(Basis.IDENTITY, weapon.mount_position)


## A shot reached the body: the shield (MsShield.apply_hit) didn't stop it.
func _on_vehicle_hit(_damage: float, _at: Vector3, _direction: Vector3) -> void:
	register_hit(false)


## The suit was shot: on the body, or `blocked` on its shield.
func register_hit(blocked: bool) -> void:
	since_hit = 0.0
	last_hit_blocked = blocked
	hit_taken.emit(blocked)
