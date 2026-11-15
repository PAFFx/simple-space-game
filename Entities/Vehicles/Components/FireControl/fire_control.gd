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
##   lock         the contact nearest the designation direction (the HUD cursor, or where
##                the pilot looks, by the sensor of interest) is the candidate while lock
##                preview is held; lock commit locks it, or unlocks if it already is (or
##                nothing is designated).
##   shield       held up toward where the pilot looks while block is held; block wins
##                over the shield's missiles, which can't launch meanwhile.
##
## A weapon points at the lead on the locked target if that is inside its envelope, else
## as near as the envelope allows; with no lock it sits on its boresight. The suit never
## turns itself: bringing a target into the envelope is flying.

enum MasterMode { NAV, DGFT, BVR }
enum Soi { HUD_CURSOR, HMCS }
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
	[&"beam_rifle", &"shield_missile"],
	[&"fin_funnel"],
	[&"bazooka_back", &"bazooka_hand"],
	[],
	[&"beam_saber"],
]
## Names for the weapon ring, including weapons that aren't fitted yet.
@export var weapon_labels := {
	&"beam_rifle": "RIFLE", &"shield_missile": "MISSILE", &"fin_funnel": "FUNNEL",
	&"bazooka_back": "BZK-B", &"bazooka_hand": "BZK-H", &"beam_saber": "SABER",
}
## Selected on entering DGFT.
@export var dgft_weapon: StringName = &"beam_rifle"
## Weapon that holds the shield up (not a gun; aimed where the pilot looks).
@export var guard_weapon: StringName = &"shield_guard"
@export var torso_bone: StringName = &"spine"
@export var master_arm: bool = false
@export var mode := MasterMode.NAV
@export var soi := Soi.HUD_CURSOR

@export_group("Lock")
@export var lock_range: float = 20000.0
## A contact is designated within this angle of the cursor / the pilot's look, deg
## (plus its own apparent size).
@export var cursor_cone_deg: float = 5.0
@export var hmcs_cone_deg: float = 9.0
## HUD cursor slew at full deflection, deg/s, and how far from straight ahead it goes.
@export var cursor_rate_deg: float = 45.0
@export var cursor_limits_deg := Vector2(70.0, 45.0)
## The shield stops hits arriving within this angle of where it faces, deg.
@export var shield_cover_deg: float = 50.0

var weapons := {}                     ## id → MsWeapon
var selected: MsWeapon
var locked: Node3D
var candidate: Node3D
## HUD cursor, azimuth / elevation in the display's frame, deg.
var cursor := Vector2.ZERO
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
var _target_velocity := Vector3.ZERO
var _target_last := Vector3.ZERO
var _target_tracked := false


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
	loadout = vehicle.find_component(MsLoadout) as MsLoadout
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
	if skeleton != null and not _aimed.is_empty():
		var modifier := WeaponAimModifier.new()
		modifier.name = "WeaponAimModifier"
		modifier.fire_control = self
		skeleton.add_child(modifier)
	_apply_mode()


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


func get_target_position() -> Vector3:
	return locked.global_position if locked != null else Vector3.ZERO


func get_target_velocity() -> Vector3:
	return _target_velocity


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
	selected = weapon
	selection_changed.emit(weapon)


func lock(target: Node3D) -> void:
	if target == locked:
		return
	if is_instance_valid(locked) and locked.tree_exiting.is_connected(_on_target_gone):
		locked.tree_exiting.disconnect(_on_target_gone)
	locked = target
	if target != null:
		# Destroyed or despawned: drop the lock at once, before anything draws it.
		target.tree_exiting.connect(_on_target_gone)
	_target_tracked = false
	_target_velocity = Vector3.ZERO
	locked_changed.emit(target)


func _on_target_gone() -> void:
	locked = null
	candidate = null
	_target_tracked = false
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
		soi = Soi.HMCS if soi == Soi.HUD_CURSOR else Soi.HUD_CURSOR
		cursor = Vector2.ZERO
	cursor = (cursor + cmd.cursor_slew * cursor_rate_deg * delta).clamp(-cursor_limits_deg, cursor_limits_deg)

	_update_lock(cmd)
	_track_target(delta)

	blocking = cmd.shield_block
	var guard := get_weapon(guard_weapon)
	for weapon: MsWeapon in weapons.values():
		if weapon == guard:
			weapon.wanted = blocking
			weapon.aim_override = _look_angles() if blocking else null
		elif weapon.always_on:
			weapon.wanted = is_weapons_mode() and cmd.vulcan_ready
			weapon.triggered = master_arm and is_weapons_mode() and cmd.vulcan_fire
		else:
			# The shield can't fire its missiles while it is held up.
			var held := blocking and guard != null and weapon.equipment == guard.equipment
			weapon.wanted = weapon == selected and is_weapons_mode() and not held
			weapon.triggered = master_arm and weapon.wanted and cmd.fire_main
	_apply_poses(guard)
	for weapon: MsWeapon in weapons.values():
		weapon.update(delta, self)


func _apply_mode() -> void:
	if mode == MasterMode.NAV:
		select(null)
	elif mode == MasterMode.DGFT:
		select(get_weapon(dgft_weapon))


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
		select(pick)
	hat_pressed.emit(direction)


func _update_lock(cmd: PilotCommand) -> void:
	candidate = _find_candidate() if cmd.lock_preview or cmd.lock_commit else null
	if cmd.lock_commit:
		lock(null if candidate == locked else candidate)


## The contact nearest the designation, within the designation cone and lock range.
func _find_candidate() -> Node3D:
	var origin := get_view_origin()
	var dir := get_designation()
	var cone := hmcs_cone_deg if soi == Soi.HMCS else cursor_cone_deg
	var best: Node3D = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(CONTACT_GROUP):
		var contact := node as Node3D
		if contact == null or contact == vehicle:
			continue
		var rel := contact.global_position - origin
		var dist := rel.length()
		if dist < 1.0 or dist > lock_range:
			continue
		var radius: float = contact.get_meta(&"hud_radius", 10.0)
		var off := rad_to_deg(dir.angle_to(rel)) - rad_to_deg(atan(radius / dist))
		if off <= cone and off < best_score:
			best_score = off
			best = contact
	return best


## The locked target's velocity: its own if it reports one, else from its motion.
func _track_target(delta: float) -> void:
	if locked == null:
		return
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


## Where the pilot looks, as azimuth / elevation in the body frame.
func _look_angles() -> Vector2:
	var camera := _pilot_camera()
	var dir := -camera.global_basis.z if camera != null else -get_body_basis().z
	return SpatialMath.direction_to_angles(get_body_basis().inverse() * dir)


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


func _on_vehicle_hit(_damage: float, _at: Vector3, direction: Vector3) -> void:
	var guard := get_weapon(guard_weapon)
	var blocked := false
	if blocking and guard != null and guard.readiness > 0.5:
		var facing := get_body_basis() * SpatialMath.angles_to_direction(guard.aim)
		blocked = rad_to_deg(facing.angle_to(-direction)) <= shield_cover_deg
	since_hit = 0.0
	last_hit_blocked = blocked
	hit_taken.emit(blocked)
