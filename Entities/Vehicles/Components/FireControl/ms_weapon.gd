class_name MsWeapon
extends Node3D

## One weapon of a mobile suit, driven by the suit's FireControl: readying, aiming
## inside its envelope, lead on the locked target, ammunition and firing.
##
## Put it under the MsEquipment that carries it (rifle, shield) with one or more
## Marker3D children named Muzzle* (-Z = along the barrel); or set `mount_bone` and it
## rides that bone itself (head vulcans).
##
## Aim is logical: `aim` (azimuth / elevation in the suit's body frame, degrees) slews
## toward the lead direction at `slew_rate_deg`, clamped to the envelope, and shots
## leave along it. WeaponAimModifier turns `aim_bone` so the model points the same way.
##
## A beam (projectile.spool_time > 0) fires once per pull: the trigger is held while the
## barrel spools up, the shot leaves when it is spooled, and letting go early drops it.
## Two weapons can draw on one magazine (`ammo_from`): the rifle's pulse and linear beams
## share the E-pack and its cooldown.

enum State { STOWED, READYING, READY, STOWING }

@export var weapon_id: StringName = &""
@export var display_name: String = ""
## Short name for the HUD and the weapon ring.
@export var hud_name: String = ""
@export var projectile: ProjectileSpec
## Rounds carried; 0 = this isn't a gun (the shield guard).
@export var max_ammo: int = 0
## Seconds between shots while the fire button is held (a beam: before the next pull).
@export var cycle_time: float = 1.0
## Another weapon whose rounds (and cooldown) this one uses.
@export var ammo_from: NodePath
## Rounds one shot uses.
@export var ammo_cost: int = 1
## Rounds leave the muzzles in turn (twin vulcans, missile tubes).
@export var dispersion_deg: float = 0.0
## Not picked with the weapon select hat: ready whenever a weapons mode is on (vulcans).
@export var always_on: bool = false

@export_group("Readying")
## Seconds to bring it to bear (raising the arm, spinning up the barrels).
@export var ready_time: float = 0.8
## Pose the carrying equipment takes while this weapon is wanted (MsPoseAnimator layer).
@export var pose: StringName = &""
## Bone it rides when it isn't under an MsEquipment, and where on that bone (body frame
## with the skeleton at rest).
@export var mount_bone: StringName = &""
@export var mount_position := Vector3.ZERO

@export_group("Aim")
## Bone turned to point the weapon. Empty = it points where the suit does.
@export var aim_bone: StringName = &""
## Share of the aim's azimuth the torso takes by twisting, and its limit, deg.
@export_range(0.0, 1.0) var torso_share: float = 0.0
@export var torso_limit_deg: float = 10.0
## Envelope in the suit's body frame, deg: azimuth (+ = right) and elevation (+ = up)
## as (min, max). The weapon can't point outside it.
@export var az_limits := Vector2(-30.0, 30.0)
@export var el_limits := Vector2(-30.0, 30.0)
## Where it points with no target locked.
@export var boresight := Vector2.ZERO
@export var slew_rate_deg: float = 90.0
## How fast the slew speeds up and slows down, deg/s² (0 = instant). A limb jumping to
## full speed would kick the suit with its whole momentum in one tick (LimbReaction).
@export var slew_accel_deg: float = 600.0
## How close the barrel must be to the lead direction to call the shot good, deg.
@export var on_target_deg: float = 0.35

var state := State.STOWED
var ammo: int:
	get:
		return _magazine()._rounds
	set(value):
		_magazine()._rounds = value
## Seconds the trigger has been held spooling the next beam.
var spool := 0.0
## FireControl sets these each tick.
var wanted := false
var triggered := false
## Point at this instead of the lead direction (azimuth / elevation, deg), or null.
var aim_override: Variant = null

## 0 = stowed, 1 = ready.
var readiness := 0.0
## How much the model follows the aim, 0..1 (WeaponAimModifier).
var aim_weight := 0.0
var aim := Vector2.ZERO
var aim_rate := Vector2.ZERO   ## deg/s
var torso_yaw := 0.0
## Fire solution on the locked target.
var solution_valid := false
var lead_angles := Vector2.ZERO
var lead_point := Vector3.ZERO
var time_of_flight := 0.0
var target_range := 0.0
var target_in_envelope := false
var on_target := false

var equipment: MsEquipment
var muzzles: Array[Node3D] = []
var _rounds := 0
var _cooldown := 0.0
var _next_muzzle := 0
var _ammo_source: MsWeapon
## A beam fired: wait for the trigger to be let go before spooling the next.
var _awaiting_release := false
var _stream_muzzle: Node3D
var _stream_fcs: FireControl
var _stream: ProjectileManager.Shot


func _ready() -> void:
	if not ammo_from.is_empty():
		_ammo_source = get_node_or_null(ammo_from) as MsWeapon
	if _ammo_source == null:
		_rounds = max_ammo
	aim = boresight
	equipment = get_parent() as MsEquipment
	for child in get_children():
		if child is Node3D and String(child.name).begins_with("Muzzle"):
			muzzles.append(child)
	if muzzles.is_empty():
		muzzles.append(self)


func get_hud_name() -> String:
	return hud_name if hud_name != "" else display_name


func is_gun() -> bool:
	return projectile != null and max_ammo > 0


func rearm() -> void:
	if _ammo_source == null:
		ammo = max_ammo


func _magazine() -> MsWeapon:
	return _ammo_source if _ammo_source != null else self


## 0..1, how far the next beam has spooled.
func get_spool_fraction() -> float:
	return clampf(spool / projectile.spool_time, 0.0, 1.0) if projectile != null and projectile.spool_time > 0.0 else 0.0


func is_spooling() -> bool:
	return spool > 0.0


## Taking over from another weapon on the same equipment and pose (pulse ↔ linear): the arm
## stays up and on its aim instead of lowering and raising again.
func take_over(other: MsWeapon) -> void:
	readiness = other.readiness
	state = other.state
	aim = other.aim
	aim_rate = other.aim_rate
	aim_weight = other.aim_weight
	torso_yaw = other.torso_yaw
	other.readiness = 0.0
	other.state = State.STOWED
	other.aim_weight = 0.0
	other.torso_yaw = 0.0
	other.spool = 0.0


func get_muzzle() -> Node3D:
	return muzzles[_next_muzzle % muzzles.size()]


## Mean of the muzzles, global.
func get_muzzle_position() -> Vector3:
	var sum := Vector3.ZERO
	for m in muzzles:
		sum += m.global_position
	return sum / muzzles.size()


func is_inside_envelope(angles: Vector2) -> bool:
	return angles.x >= az_limits.x and angles.x <= az_limits.y \
			and angles.y >= el_limits.x and angles.y <= el_limits.y


func clamp_to_envelope(angles: Vector2) -> Vector2:
	return Vector2(clampf(angles.x, az_limits.x, az_limits.y), clampf(angles.y, el_limits.x, el_limits.y))


## The envelope's edge as azimuth / elevation points, `step` degrees apart.
func get_envelope_outline(step := 4.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(az_limits.x, el_limits.x), Vector2(az_limits.y, el_limits.x),
			Vector2(az_limits.y, el_limits.y), Vector2(az_limits.x, el_limits.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := maxi(ceili(a.distance_to(b) / step), 1)
		for i in n:
			pts.append(a.lerp(b, float(i) / n))
	pts.append(corners[0])
	return pts


## Advances readying, the fire solution and the aim. Called by FireControl every tick.
func update(delta: float, fcs: FireControl) -> void:
	readiness = move_toward(readiness, 1.0 if wanted else 0.0, delta / maxf(ready_time, 0.01))
	if readiness >= 1.0:
		state = State.READY
	elif readiness <= 0.0:
		state = State.STOWED
	else:
		state = State.READYING if wanted else State.STOWING
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not triggered:
		_awaiting_release = false

	_solve(fcs)
	var desired := boresight
	if aim_override != null:
		desired = clamp_to_envelope(aim_override)
	elif solution_valid:
		desired = clamp_to_envelope(lead_angles)
	_slew(desired, delta)
	on_target = solution_valid and target_in_envelope and aim.distance_to(lead_angles) <= _tolerance(fcs)
	var twist := clampf(aim.x * torso_share, -torso_limit_deg, torso_limit_deg) * readiness
	torso_yaw = move_toward(torso_yaw, twist, 40.0 * delta)
	# A weapon that is always on follows the target with the model as soon as there is
	# one; the others only once they are brought to bear.
	var follow := readiness
	if always_on:
		follow = 1.0 if fcs.is_weapons_mode() and (solution_valid or wanted) else 0.0
	aim_weight = move_toward(aim_weight, follow, delta / 0.35) if always_on else follow

	if projectile != null and projectile.spool_time > 0.0:
		_update_spool(delta, fcs)
	else:
		while triggered and can_fire():
			_fire(fcs)


func _update_spool(delta: float, fcs: FireControl) -> void:
	if triggered and not _awaiting_release and can_fire():
		spool += delta
		if spool >= projectile.spool_time:
			spool = 0.0
			_awaiting_release = true
			_fire(fcs)
	else:
		spool = 0.0
	ProjectileManager.of(self).set_charge(self, get_muzzle(), projectile, get_spool_fraction())


## Moves the aim toward `desired` at up to slew_rate_deg, accelerating and braking at
## slew_accel_deg so it arrives without overshoot.
func _slew(desired: Vector2, delta: float) -> void:
	if slew_accel_deg <= 0.0:
		aim = aim.move_toward(desired, slew_rate_deg * delta)
		aim_rate = Vector2.ZERO
		return
	var to := desired - aim
	var dist := to.length()
	if dist < 0.01 and aim_rate.length() < slew_accel_deg * delta:
		aim = desired
		aim_rate = Vector2.ZERO
		return
	var speed := minf(slew_rate_deg, sqrt(2.0 * slew_accel_deg * dist))
	var want := to / maxf(dist, 1e-6) * speed
	aim_rate = aim_rate.move_toward(want, slew_accel_deg * delta)
	var step := aim_rate * delta
	aim = desired if step.length() >= dist and to.dot(step) > 0.0 else aim + step


func can_fire() -> bool:
	return state == State.READY and _magazine()._cooldown <= 0.0 and ammo >= ammo_cost and projectile != null


## World direction the barrel points along.
func get_aim_direction(fcs: FireControl) -> Vector3:
	return fcs.get_body_basis() * SpatialMath.angles_to_direction(aim)


func _solve(fcs: FireControl) -> void:
	solution_valid = false
	target_in_envelope = false
	if projectile == null or fcs.locked == null:
		return
	var muzzle := get_muzzle_position()
	var rel_pos := fcs.get_target_position() - muzzle
	var rel_vel := fcs.get_target_velocity() - fcs.get_own_velocity()
	target_range = rel_pos.length()
	var t := target_range / maxf(projectile.speed, 1.0)
	if _stream != null and _stream.emitting:
		# A linear beam already out: its front is `reach` along, so lead only by what is
		# left to cover; once past the target it points straight at it, like a laser.
		t = _lead_with_head_start(rel_pos, rel_vel, projectile.speed, _stream.reach)
		if t < 0.0:
			return
	else:
		# A rocket speeds up on the way: solve with its average speed, a few rounds.
		for i in 4:
			var speed := projectile.distance_at(maxf(t, 0.01)) / maxf(t, 0.01)
			t = SpatialMath.intercept_time(rel_pos, rel_vel, speed)
			if t <= 0.0:
				return
	if t > projectile.lifetime:
		return
	var aim_vec := rel_pos + rel_vel * t
	time_of_flight = t
	lead_point = muzzle + aim_vec
	lead_angles = SpatialMath.direction_to_angles(fcs.get_body_basis().inverse() * aim_vec)
	target_in_envelope = is_inside_envelope(lead_angles)
	solution_valid = true


## Time t when |rel_pos + rel_vel·t| = reach + speed·t (0 if already within reach,
## -1 if never).
static func _lead_with_head_start(rel_pos: Vector3, rel_vel: Vector3, speed: float, reach: float) -> float:
	if rel_pos.length() <= reach:
		return 0.0
	var a := rel_vel.dot(rel_vel) - speed * speed
	var b := 2.0 * (rel_pos.dot(rel_vel) - reach * speed)
	var c := rel_pos.dot(rel_pos) - reach * reach
	if absf(a) < 1e-6:
		return -c / b if b < 0.0 else -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var r := sqrt(disc)
	var t1 := (-b - r) / (2.0 * a)
	var t2 := (-b + r) / (2.0 * a)
	var t := minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	return t if t > 0.0 else -1.0


func _tolerance(fcs: FireControl) -> float:
	var radius := fcs.get_target_radius() * 0.6
	return maxf(on_target_deg, rad_to_deg(atan(radius / maxf(target_range, 1.0))))


func _fire(fcs: FireControl) -> void:
	var muzzle := get_muzzle()
	_next_muzzle += 1
	var angles := aim
	if dispersion_deg > 0.0:
		angles += Vector2(randfn(0.0, dispersion_deg), randfn(0.0, dispersion_deg))
	var dir := fcs.get_body_basis() * SpatialMath.angles_to_direction(angles)
	var own_velocity := fcs.get_own_velocity()
	var manager := ProjectileManager.of(self)
	var at := muzzle.global_position
	var shot := manager.spawn(projectile, at, own_velocity + dir * projectile.speed, dir, fcs.get_own_rids(), fcs.get_body())
	if projectile.kind == ProjectileSpec.Kind.LINEAR:
		_stream = shot
		_stream_muzzle = muzzle
		_stream_fcs = fcs
		manager.stream_from(shot, muzzle, _stream_state)
	manager.muzzle_flash(projectile, at, own_velocity, muzzle)
	ammo -= ammo_cost
	_magazine()._cooldown += cycle_time
	fcs.shot_fired.emit(self)


## Where a linear beam leaves the barrel this tick: [position, velocity, direction].
func _stream_state() -> Array:
	var dir := get_aim_direction(_stream_fcs)
	var own_velocity := _stream_fcs.get_own_velocity()
	return [_stream_muzzle.global_position, own_velocity + dir * projectile.speed, dir]
