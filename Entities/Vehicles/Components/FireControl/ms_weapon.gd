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

enum State { STOWED, READYING, READY, STOWING }

@export var weapon_id: StringName = &""
@export var display_name: String = ""
## Short name for the HUD and the weapon ring.
@export var hud_name: String = ""
@export var projectile: ProjectileSpec
## Rounds carried; 0 = this isn't a gun (the shield guard).
@export var max_ammo: int = 0
## Seconds between shots while the fire button is held.
@export var cycle_time: float = 1.0
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
var ammo := 0
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
var _cooldown := 0.0
var _next_muzzle := 0


func _ready() -> void:
	ammo = max_ammo
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
	ammo = max_ammo


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

	while triggered and can_fire():
		_fire(fcs)


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
	return state == State.READY and _cooldown <= 0.0 and ammo > 0 and projectile != null


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
	# A rocket speeds up on the way: solve with its average speed, a few rounds.
	var t := target_range / maxf(projectile.speed, 1.0)
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
	manager.spawn(projectile, at, own_velocity + dir * projectile.speed, dir, fcs.get_own_rids(), fcs.get_body())
	manager.muzzle_flash(projectile, at, own_velocity)
	ammo -= 1
	_cooldown += cycle_time
	fcs.shot_fired.emit(self)
