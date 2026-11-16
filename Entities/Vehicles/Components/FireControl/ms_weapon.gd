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
## Joints that help `aim_bone` (collarbone, wrist), in the order they turn: each takes
## `aim_assist_shares` of what is left of the turn (at most `aim_assist_limits_deg`),
## then `aim_bone` takes the rest. A share of the reach spread down the limb keeps the
## big joint inside its range and the arm off the body.
@export var aim_assist_bones: Array[StringName] = []
@export var aim_assist_shares := PackedFloat32Array()
@export var aim_assist_limits_deg := PackedFloat32Array()
## Elbow that straightens as the aim swings away from the boresight: the ready pose holds
## the weapon low with a bent arm (out of the pilot's view), the reach to the envelope's
## edges comes from extending it. `elbow_axis` is the bend axis (skeleton space at rest, +
## bends); it opens by up to `elbow_extend_deg`, from `elbow_extend_from_deg` off the
## boresight to all of it at `elbow_extend_full_deg`.
@export var elbow_bone: StringName = &""
@export var elbow_axis := Vector3.RIGHT
@export var elbow_extend_deg: float = 0.0
@export var elbow_extend_from_deg: float = 25.0
@export var elbow_extend_full_deg: float = 70.0
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
## Jitter filter on the lead it follows (a "1 euro" filter): the track's noise moves the
## lead a little every tick, and a limb chasing it shakes. Slow wander is smoothed with
## `aim_smoothing_hz`; the cutoff rises by `aim_smoothing_beta` per deg/s the lead really
## moves, so a crossing target isn't lagged. 0 Hz = off.
@export var aim_smoothing_hz: float = 1.0
@export var aim_smoothing_beta: float = 0.5
## While the suit holds its shield up the weapon can't point into it: this envelope
## replaces az_limits / el_limits then (zero size = no change).
@export var guard_az_limits := Vector2.ZERO
@export var guard_el_limits := Vector2.ZERO
## How close the barrel must be to the lead direction to call the shot good, deg.
@export var on_target_deg: float = 0.35
## The lock lost (target destroyed, unlocked): keep pointing where it was this long before
## going back to the boresight, s. A linear beam still coming out holds it until it ends.
@export var lock_loss_hold: float = 0.8

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
## The suit holds its shield up (set by FireControl): the guard envelope applies.
var guarded := false
## The line of fire runs into the suit itself (its shield, its body): it holds fire.
var masked := false
## How far along the line of fire the suit looks for itself, m.
const MASK_CHECK_DISTANCE := 40.0
var _lead_smooth := Vector2.ZERO
var _lead_rate := Vector2.ZERO
var _lead_smoothed := false

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
var _held_aim := Vector2.ZERO
var _hold_left := 0.0


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


## Azimuth limits now: reduced while the shield is up (guard_az_limits).
func get_az_limits() -> Vector2:
	return guard_az_limits if guarded and guard_az_limits != Vector2.ZERO else az_limits


func get_el_limits() -> Vector2:
	return guard_el_limits if guarded and guard_el_limits != Vector2.ZERO else el_limits


func is_inside_envelope(angles: Vector2) -> bool:
	var az := get_az_limits()
	var el := get_el_limits()
	return angles.x >= az.x and angles.x <= az.y and angles.y >= el.x and angles.y <= el.y


func clamp_to_envelope(angles: Vector2) -> Vector2:
	var az := get_az_limits()
	var el := get_el_limits()
	return Vector2(clampf(angles.x, az.x, az.y), clampf(angles.y, el.x, el.y))


## The envelope's edge as azimuth / elevation points, `step` degrees apart.
func get_envelope_outline(step := 4.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var az := get_az_limits()
	var el := get_el_limits()
	var corners := [Vector2(az.x, el.x), Vector2(az.y, el.x), Vector2(az.y, el.y), Vector2(az.x, el.y)]
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
	var streaming := _stream != null and _stream.emitting
	if aim_override != null:
		desired = clamp_to_envelope(aim_override)
	elif solution_valid:
		desired = clamp_to_envelope(_smooth_lead(lead_angles, delta))
		_held_aim = desired
		_hold_left = lock_loss_hold
	elif _hold_left > 0.0 or streaming:
		desired = _held_aim
		_hold_left = maxf(_hold_left - delta, 0.0)
	if not solution_valid:
		_lead_smoothed = false
	_slew(desired, delta)
	masked = readiness > 0.0 and _line_masked(fcs)
	on_target = solution_valid and target_in_envelope and not masked \
			and aim.distance_to(lead_angles) <= _tolerance(fcs)
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


## The lead with the track's tick-to-tick noise filtered out (see aim_smoothing_hz).
func _smooth_lead(lead: Vector2, delta: float) -> Vector2:
	if aim_smoothing_hz <= 0.0 or delta <= 0.0:
		return lead
	if not _lead_smoothed:
		_lead_smoothed = true
		_lead_smooth = lead
		_lead_rate = Vector2.ZERO
		return lead
	var rate := (lead - _lead_smooth) / delta
	_lead_rate = _lead_rate.lerp(rate, _alpha(1.0, delta))
	var cutoff := aim_smoothing_hz + aim_smoothing_beta * _lead_rate.length()
	_lead_smooth = _lead_smooth.lerp(lead, _alpha(cutoff, delta))
	return _lead_smooth


static func _alpha(cutoff_hz: float, delta: float) -> float:
	var tau := 1.0 / (TAU * cutoff_hz)
	return 1.0 / (1.0 + tau / delta)


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
	return state == State.READY and not masked and _magazine()._cooldown <= 0.0 \
			and ammo >= ammo_cost and projectile != null


## Whether the first thing along the line of fire is the suit itself. Its own shots skip
## its hull (they start inside it), so this is what keeps it from shooting itself.
func _line_masked(fcs: FireControl) -> bool:
	if muzzles.is_empty() or projectile == null:
		return false
	var body := fcs.get_body()
	if body == null:
		return false
	var from := get_muzzle_position()
	var dir := fcs.get_body_basis() * SpatialMath.angles_to_direction(aim)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * MASK_CHECK_DISTANCE)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.collider as Node
	return collider == body or VehicleBase.find_vehicle(collider) == fcs.vehicle


## World direction the barrel points along.
func get_aim_direction(fcs: FireControl) -> Vector3:
	return fcs.get_body_basis() * SpatialMath.angles_to_direction(aim)


func _solve(fcs: FireControl) -> void:
	solution_valid = false
	target_in_envelope = false
	if projectile == null or fcs.locked == null or not fcs.has_target_solution():
		return
	var muzzle := get_muzzle_position()
	var rel_pos := fcs.get_target_position() - muzzle
	var rel_vel := fcs.get_target_velocity() - fcs.get_own_velocity()
	# The track's acceleration: a target holding a burn is led along its curve. The shot
	# keeps the suit's velocity at launch, not its acceleration.
	var acc := fcs.get_target_acceleration()
	target_range = rel_pos.length()
	var t := target_range / maxf(projectile.speed, 1.0)
	if _stream != null and _stream.emitting:
		# A linear beam already out: its front is `reach` along, so lead only by what is
		# left to cover; once past the target it points straight at it, like a laser.
		t = _lead_with_head_start(rel_pos, rel_vel, projectile.speed, _stream.reach)
		if t < 0.0:
			return
		t = maxf(_lead_with_head_start(rel_pos + acc * (0.5 * t * t), rel_vel, projectile.speed, _stream.reach), 0.0)
	else:
		# A rocket speeds up on the way: solve with its average speed, a few rounds.
		for i in 4:
			var speed := projectile.distance_at(maxf(t, 0.01)) / maxf(t, 0.01)
			t = SpatialMath.intercept_time(rel_pos + acc * (0.5 * t * t), rel_vel, speed)
			if t <= 0.0:
				return
	if t > projectile.lifetime:
		return
	var aim_vec := rel_pos + rel_vel * t + acc * (0.5 * t * t)
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
