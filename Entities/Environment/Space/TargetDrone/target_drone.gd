class_name TargetDrone
extends AnimatableBody3D

## A practice target: a ball of armour plate that shows as a hostile HUD contact, takes
## hits (`apply_hit`) and blows up when its hit points run out. Builds its own model and
## collision shape, so it can be made from code: TargetDrone.new().
##
##   STATIC   holds still (relative to the velocity it was given)
##   DRIFT    coasts in a straight line
##   JINK     changes its acceleration every second or two, like a suit dodging; stays
##            within `leash` of where it started
##   TURRET   jinks gently and shoots back at `quarry` with slow beams, to practise
##            dodging and the shield
##
## A turret fights like a suit with a rifle arm: its body turns at a limited rate, its gun
## arm points only within `arm_cone_deg` of where the body faces and slews at a limited
## rate, and it spools only once the barrel is on the lead. Circling it faster than it
## turns gets you out of its arc. Its E-cap holds `magazine` shots; empty, it ejects the
## pack (you see it fly off), drops the arm and reloads for `reload_time`. Each shot holds
## the barrel where it left for the pour and `recover_time` after (recoil): the punish window.
##
## Higher specs, for testing both sides of a fight:
##   dodge     with a `threat` (the shooter's FireControl), it watches the barrel: when the
##             selected weapon spools while locked on it, it thrusts hard across the line of
##             sight after `dodge_reaction`, like a pilot reading the cue.
##   tracking  with `use_track`, a TURRET aims from its own sensor track of the quarry
##             (delayed, noisy angles and range through a SensorTrack, leading with the
##             estimated acceleration) instead of the quarry's true state.

## Beams drill it (Docs/Damage): a thin shell (`shell_areal` kg/m² per wall), a light interior
## and a dense core (its reactor) at the centre. A beam through the core breaches it (a small
## flash, the drone gone); through the gun arm, the gun is gone; any other hole has a chance
## to cut its control (it goes dead and drifts); enough holes break it apart.

enum Behaviour { STATIC, DRIFT, JINK, TURRET }

signal destroyed(drone: TargetDrone)

@export var behaviour := Behaviour.STATIC
@export var label: String = "DRONE"
@export var radius: float = 7.0
@export var hit_points: float = 300.0
## Velocity it starts with (give it the player's, so it keeps station).
@export var velocity := Vector3.ZERO
@export_group("Structure")
@export var shell_areal: float = 80.0
@export var interior_density: float = 15.0
@export var core_radius: float = 1.6
@export var core_density: float = 300.0
## Chance a hole through it cuts its control.
@export_group("Jink")
@export var jink_accel_g: float = 3.0
@export var jink_interval := Vector2(0.8, 2.2)
@export var leash: float = 400.0
@export_group("Turret")
@export var quarry: Node3D
@export var shot: ProjectileSpec
@export var fire_interval := Vector2(1.6, 3.2)
@export var fire_range: float = 6000.0
@export var aim_error_deg: float = 0.25
@export_group("Gun arm")
## Body turn: rate deg/s and its acceleration deg/s² (0 rate = turns at once).
@export var turn_rate_deg: float = 20.0
@export var turn_accel_deg: float = 60.0
## The arm reaches this far off the body's facing, deg.
@export var arm_cone_deg: float = 45.0
@export var arm_slew_deg: float = 60.0
@export var arm_accel_deg: float = 400.0
## Extra aim error per deg/s the barrel is slewing when the shot leaves, deg.
@export var slew_error: float = 0.02
## The barrel must be this close to the lead to start a spool, deg (plus the quarry's size).
@export var aim_tolerance_deg: float = 1.0
## Shots in one E-cap, and the time to swap it (arm down, pack ejected). 0 = unlimited.
@export var magazine: int = 6:
	set(value):
		magazine = value
		rounds = value
@export var reload_time: float = 4.0
## After a beam has poured out the barrel stays put this long (recoil), s.
@export var recover_time: float = 0.5
@export_group("Dodge")
## The shooter whose barrel it watches; empty = no dodging.
@export var threat: FireControl
@export var dodge_accel_g: float = 6.0
@export var dodge_reaction: float = 0.25
@export var dodge_hold := Vector2(0.6, 1.0)
@export_group("Tracking")
@export var use_track: bool = false
@export var track_sigma_mrad: float = 0.1
@export var track_range_sigma: float = 1.0
@export var track_latency: float = 0.05
@export var track_interval: float = 1.0 / 30.0

var _accel := Vector3.ZERO
var _jink_due := 0.0
var _fire_due := 2.0
## Where it would be without jinking: the jink is leashed to this drifting point.
var _anchor := Vector3.ZERO
var _base_velocity := Vector3.ZERO
var _material: StandardMaterial3D
var _flash := 0.0
## Seconds spooling the next shot (TURRET), -1 = not spooling.
var _spool := -1.0
## Where the shot leaves: on the hull, facing the quarry.
var _muzzle: Marker3D
## The beam pouring out, along the barrel held where it left.
var _beam: ProjectileManager.Shot
var _beam_dir := Vector3.ZERO
## Gun arm: barrel in the body frame, its slew speed (deg/s), the body's turn speed.
var _barrel_local := Vector3.FORWARD
var _arm_speed := 0.0
var _turn_speed := 0.0
var _gun: Node3D
var _pack: MeshInstance3D
var rounds := 0
var _reload_left := 0.0
## Barrel held (pour and recoil), s.
var _hold_left := 0.0
var reloads := 0
## Shots fired and dodges started (probes).
var shots_fired := 0
var dodges := 0
var _cue_seen := false
var _dodge_in := -1.0
var _speed_limit_g := 0.0
var _ball: MeshInstance3D
var _holes: HoleSet
var _drills := {}   ## shot → [kg per STEP, pos, spare, hole, chord, entry, core t, gun t, through, last, direction]
var _tumble := Vector3.ZERO   ## disabled: its spin, rad/s about this axis
var _spark_due := 0.0
var _spark_until := 0.0
var _clock := 0.0
var _left := 1.0
var _dead := false
var _gun_dead := false
var _track: SensorTrack
var _track_due := 0.0
var _track_queue: Array = []
var _time := 0.0


func _ready() -> void:
	sync_to_physics = false
	add_to_group(&"hud_contacts")
	add_to_group(ProjectileManager.DAMAGEABLE)
	set_meta(&"hud_label", label)
	set_meta(&"hud_radius", radius)
	set_meta(&"hud_hostile", true)
	_build()
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	add_child(_muzzle)
	_anchor = global_position
	_base_velocity = velocity
	if behaviour == Behaviour.TURRET:
		if shot == null:
			shot = load("res://Entities/Projectiles/Specs/drone_shot.tres")
		_build_gun()
		_face_quarry.call_deferred()


func get_velocity() -> Vector3:
	return velocity


## Whether its next shot is charging (the cue the quarry dodges on).
func is_spooling() -> bool:
	return _spool >= 0.0


func apply_hit(damage: float, _at: Vector3, _direction: Vector3, _source: Node) -> void:
	if hit_points <= 0.0:
		return
	hit_points -= damage
	_flash = 1.0
	if hit_points <= 0.0:
		ProjectileManager.of(self).explode(global_position, velocity, radius * 3.0)
		destroyed.emit(self)
		queue_free()


## One tick of a beam on it (ProjectileManager).
func beam_contact(contact: ProjectileManager.BeamContact) -> void:
	var d: Array = _drills.get(contact.key, [])
	if d.is_empty():
		d = _start_drill(contact)
		_drills[contact.key] = d
		# Still counted as a hit (tools count hits by hit points); hit points of 1e9 and more
		# make it a target that can't be destroyed (probes).
		hit_points -= contact.spec.damage
	if hit_points >= 1e8:
		contact.absorbed = contact.energy
		contact.front = contact.point
		return
	d[9] = _clock
	var kgs: PackedFloat32Array = d[0]
	var kg_left := contact.energy * DamageModel.COUPLING / DamageModel.REMOVAL_ENERGY
	var pos: int = d[1]
	var spare: float = d[2]
	while pos < kgs.size():
		var need := kgs[pos] - spare
		if kg_left < need:
			spare += kg_left
			kg_left = 0.0
			break
		kg_left -= need
		spare = 0.0
		pos += 1
	d[1] = pos
	d[2] = spare
	var t := pos * DamageModel.STEP
	var chord: float = d[4]
	var hole := d[3] as HoleSet.Hole
	if hole != null:
		hole.s_drill = chord if pos >= kgs.size() else t
	if float(d[6]) >= 0.0 and t >= float(d[6]):
		d[6] = -1.0
		_breach_core()
	if float(d[7]) >= 0.0 and t >= float(d[7]):
		d[7] = -1.0
		_lose_gun()
	if pos < kgs.size():
		contact.absorbed = contact.energy
		contact.front = contact.point + contact.direction * t
		return
	contact.through = true
	contact.absorbed = contact.energy - kg_left * DamageModel.REMOVAL_ENERGY / DamageModel.COUPLING
	contact.exit_point = contact.point + contact.direction * (chord + 0.05)
	if not d[8]:
		d[8] = true
		var fx := DamageFx.of(self)
		if fx != null:
			fx.blow_out(contact.point + contact.direction * chord, contact.direction, velocity, contact.radius, self)
		_left -= 2.0 * contact.radius / (2.0 * radius) * 2.2
		# A rifle beam straight through cuts its power and control: it goes dead.
		_disable(contact.point + contact.direction * chord, contact.direction)


## What lies on the beam's line through it: [kg per STEP, 0, 0, hole, chord, entry, core t, gun t, done, last].
func _start_drill(contact: ProjectileManager.BeamContact) -> Array:
	var dir := contact.direction.normalized()
	var to_centre := global_position - contact.point
	var along := to_centre.dot(dir)
	var b := (to_centre - dir * along).length()
	var chord := 2.0 * sqrt(maxf(radius * radius - b * b, 0.01))
	var area := PI * contact.radius * contact.radius
	var n := maxi(ceili(chord / DamageModel.STEP), 1)
	var kgs := PackedFloat32Array()
	kgs.resize(n)
	var core_t := -1.0
	if b < core_radius + contact.radius * 0.5:
		core_t = along - sqrt(maxf(core_radius * core_radius - b * b, 0.0))
	for i in n:
		var tc := (i + 0.5) * DamageModel.STEP
		var kg := interior_density * DamageModel.STEP * area
		if i == 0 or i == n - 1:
			kg += shell_areal * area
		if core_t >= 0.0 and absf(tc - along) < sqrt(maxf(core_radius * core_radius - b * b, 0.0)):
			kg += core_density * DamageModel.STEP * area
		kgs[i] = kg
	var gun_t := -1.0
	if _gun != null and not _gun_dead:
		var pivot := _gun.global_position + _gun.global_basis.z * -GUN_LENGTH * 0.4
		var t := (pivot - contact.point).dot(dir)
		if (contact.point + dir * t).distance_to(pivot) < 1.2 + contact.radius:
			gun_t = maxf(t, 0.0)
	var hole: HoleSet.Hole = null
	if _ball != null:
		if _holes == null:
			_holes = HoleSet.new()
			_holes.name = "Holes"
			add_child(_holes)
		hole = _holes.add_hole(_ball, null, -1, contact.point, dir, contact.radius, chord)
		var fx := DamageFx.of(self)
		if fx != null:
			fx.drill_in(contact.point, dir, velocity, contact.radius, self)
	_flash = 1.0
	return [kgs, 0, 0.0, hole, chord, contact.point, core_t, gun_t, false, _clock, dir]


## A flash's radiant fluence, J/m² (a suit's reactor going up nearby).
func apply_radiation(fluence: float, _from: Vector3) -> void:
	if fluence > 5e6:
		_breach_core()
	elif fluence > 1e6:
		_lose_control()


func _breach_core() -> void:
	if hit_points <= -1e8 or hit_points >= 1e8:
		return
	hit_points = -1e9
	var fx := DamageFx.of(self)
	if fx != null:
		fx.reactor_flash_small(global_position, velocity, radius * 8.0)
	destroyed.emit(self)
	queue_free()


func _lose_gun() -> void:
	if _gun_dead or _gun == null:
		return
	_gun_dead = true
	_spool = -1.0
	ProjectileManager.of(self).set_charge(self, _muzzle, shot, 0.0)
	var fx := DamageFx.of(self)
	if fx != null:
		fx.burst(_gun.global_position, velocity, 1.2, &"electronics")
	_gun.visible = false


func _lose_control() -> void:
	if _dead or hit_points >= 1e8:
		return
	_dead = true
	_spool = -1.0
	if shot != null:
		ProjectileManager.of(self).set_charge(self, _muzzle, shot, 0.0)
	_material.emission_energy_multiplier = 0.0
	var fx := DamageFx.of(self)
	if fx != null:
		fx.burst(global_position, velocity, 1.5, &"electronics")


## Its power and control lines are cut (`at`, `dir`: where a beam left it, which way): no thrust,
## no gun; it drifts and tumbles, smoking from the wound, its cut lines arcing. Only a core
## hit makes it explode.
func _disable(at: Vector3, dir: Vector3) -> void:
	if _dead or hit_points >= 1e8:
		return
	_lose_control()
	_tumble = Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized() * randf_range(0.4, 1.2)
	_spark_due = _clock + 0.3
	_spark_until = _clock + 12.0
	var fx := DamageFx.of(self)
	if fx != null:
		fx.smoke_leak(self, to_local(at), (global_basis.inverse() * dir).normalized(), randf_range(6.0, 10.0))


## A beam that stopped inside (not through, not the core): deep, it still cut the lines; shallow,
## it wrecked the thrusters near the hole (jinks and dodges at half strength).
func _drill_ended(d: Array) -> void:
	if bool(d[8]) or _dead or hit_points >= 1e8 or not is_inside_tree():
		return
	var depth := int(d[1]) * DamageModel.STEP
	var entry: Vector3 = d[5]
	var dir: Vector3 = d[10]
	if depth >= 1.0:
		_disable(entry + dir * depth, -dir)
	elif depth > 0.05:
		jink_accel_g *= 0.5
		dodge_accel_g *= 0.5
		var fx := DamageFx.of(self)
		if fx != null:
			fx.creak(entry, velocity, radius * 0.3)


func _physics_process(delta: float) -> void:
	_time += delta
	_clock += delta
	for key in _drills.keys():
		if _clock - float(_drills[key][9]) > 0.3:
			_drill_ended(_drills[key])
			_drills.erase(key)
	if _dead:
		global_position += velocity * delta
		if _tumble != Vector3.ZERO:
			global_basis = Basis(_tumble.normalized(), _tumble.length() * delta) * global_basis
		else:
			rotate(Vector3.UP, delta * 0.3)
		# Cut lines arcing for a while.
		if _clock < _spark_until and _clock >= _spark_due:
			_spark_due = _clock + randf_range(0.4, 1.6)
			var fx := DamageFx.of(self)
			if fx != null:
				var at := global_position + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized() * radius * 0.9
				fx.creak(at, velocity, radius * 0.4)
		return
	_anchor += _base_velocity * delta
	_speed_limit_g = jink_accel_g
	if threat != null:
		_speed_limit_g = maxf(_speed_limit_g, dodge_accel_g)
		_watch_threat(delta)
	match behaviour:
		Behaviour.JINK:
			_jink(delta, jink_accel_g)
		Behaviour.TURRET:
			_jink(delta, jink_accel_g * 0.3)
			if use_track:
				_update_track(delta)
			if not _gun_dead:
				_shoot(delta)
	global_position += velocity * delta
	if _gun_dead:
		_spool = -1.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		_material.emission_energy_multiplier = 0.4 + _flash * 6.0


func _jink(delta: float, accel_g: float) -> void:
	_jink_due -= delta
	if _jink_due <= 0.0:
		_jink_due = randf_range(jink_interval.x, jink_interval.y)
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		# Pulled back toward its station, harder the farther it has strayed.
		var stray := _anchor - global_position
		dir = (dir + stray / maxf(leash, 1.0) * 1.5).normalized()
		_accel = dir * accel_g * 9.81 * randf_range(0.5, 1.0)
	velocity += _accel * delta
	# Its speed about the station stays bounded.
	var rel := velocity - _base_velocity
	var limit := maxf(accel_g, _speed_limit_g) * 9.81 * 4.0
	if rel.length() > limit:
		velocity = _base_velocity + rel.normalized() * limit


func _shoot(delta: float) -> void:
	var manager := ProjectileManager.of(self)
	if quarry == null or not is_instance_valid(quarry) or shot == null:
		_spool = -1.0
		manager.set_charge(self, _muzzle, shot, 0.0)
		return
	var lead := _lead(0.0)
	_turn_body(lead, delta)
	_hold_left = maxf(_hold_left - delta, 0.0)
	var pouring := _beam != null and _beam.emitting
	if pouring or _hold_left > 0.0:
		# Pour and recoil: the barrel stays where the shot left, the arm countering the body.
		_barrel_local = _clamp_to_cone(global_basis.inverse() * _beam_dir)
		_arm_speed = 0.0
		_place_gun()
		return
	if _reload_left > 0.0:
		_reload_left -= delta
		_slew_arm(Vector3(0.0, -0.8, -0.6).normalized(), delta)
		if _reload_left <= 0.0:
			rounds = magazine
			_pack.visible = true
		_place_gun()
		return
	if magazine > 0 and rounds <= 0:
		_start_reload()
		_place_gun()
		return
	var want := global_basis.inverse() * lead if lead != Vector3.ZERO else Vector3.FORWARD
	_slew_arm(_clamp_to_cone(want), delta)
	_place_gun()
	var barrel := get_barrel_direction()
	var in_arc := lead != Vector3.ZERO and _in_cone(want)
	if _spool < 0.0:
		_fire_due -= delta
		var tolerance := aim_tolerance_deg + rad_to_deg(atan(_quarry_radius() / maxf(_range_to_quarry(), 1.0)))
		if _fire_due > 0.0 or not in_arc or rad_to_deg(barrel.angle_to(lead)) > tolerance:
			return
		_fire_due = randf_range(fire_interval.x, fire_interval.y)
		_spool = 0.0
	elif not in_arc:
		# Out of its arc mid-spool: it lets go and waits for a new chance.
		_spool = -1.0
		_fire_due = 0.3
		manager.set_charge(self, _muzzle, shot, 0.0)
		return
	_spool += delta
	var level := _spool / maxf(shot.spool_time, 0.01)
	if level < 1.0:
		manager.set_charge(self, _muzzle, shot, level)
		return
	_spool = -1.0
	manager.set_charge(self, _muzzle, shot, 0.0)
	var error := deg_to_rad(aim_error_deg + slew_error * _arm_speed)
	var dir := (barrel + Vector3(randfn(0.0, error), randfn(0.0, error), randfn(0.0, error))).normalized()
	_beam_dir = dir
	_barrel_local = global_basis.inverse() * dir
	_place_gun()
	var muzzle := _muzzle.global_position
	shots_fired += 1
	rounds -= 1
	var fired := manager.spawn(shot, muzzle, velocity + dir * shot.speed, dir, [get_rid()], self)
	if shot.kind == ProjectileSpec.Kind.BEAM:
		_beam = fired
		manager.stream_from(fired, _muzzle, _beam_state)
		_hold_left = shot.emit_time + recover_time
	else:
		_hold_left = recover_time
	manager.muzzle_flash(shot, muzzle, velocity, _muzzle)


## Where the barrel points, world.
func get_barrel_direction() -> Vector3:
	return (global_basis * _barrel_local).normalized()


## Out of shots: the pack flies off, the arm drops, a new one goes in.
func is_reloading() -> bool:
	return _reload_left > 0.0


func _start_reload() -> void:
	_reload_left = reload_time
	reloads += 1
	_pack.visible = false
	var spent := MeshInstance3D.new()
	spent.mesh = _pack.mesh
	get_parent().add_child(spent)
	spent.global_transform = _pack.global_transform
	var from := spent.global_transform
	var drift := velocity + (global_basis * Vector3(1.0, 0.4, 0.3)).normalized() * 18.0
	var spin := Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	var tween := spent.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(func(t: float) -> void:
		spent.global_transform = Transform3D(from.basis.rotated(spin.normalized(), spin.length() * t), from.origin + drift * t),
		0.0, 6.0, 6.0)
	tween.tween_callback(spent.queue_free)


## Turns the body toward `lead` (or the quarry) at turn_rate_deg, easing in and out.
func _turn_body(lead: Vector3, delta: float) -> void:
	var want := lead if lead != Vector3.ZERO else (_quarry_centre() - global_position).normalized()
	var forward := -global_basis.z
	var angle := forward.angle_to(want)
	if turn_rate_deg <= 0.0:
		_turn_speed = 0.0
		_rotate_toward(forward, want, angle)
		return
	var target := minf(deg_to_rad(turn_rate_deg), sqrt(2.0 * deg_to_rad(turn_accel_deg) * angle))
	_turn_speed = move_toward(_turn_speed, target, deg_to_rad(turn_accel_deg) * delta)
	_rotate_toward(forward, want, minf(_turn_speed * delta, angle))


func _rotate_toward(from: Vector3, to: Vector3, step: float) -> void:
	if step < 1e-6:
		return
	var axis := from.cross(to)
	if axis.length_squared() < 1e-10:
		axis = global_basis.y
	global_basis = Basis(axis.normalized(), step) * global_basis.orthonormalized()


## Moves the barrel (body frame) toward `want` at arm_slew_deg, easing in and out.
func _slew_arm(want: Vector3, delta: float) -> void:
	var angle := _barrel_local.angle_to(want)
	var target := minf(arm_slew_deg, sqrt(2.0 * arm_accel_deg * rad_to_deg(angle)))
	_arm_speed = move_toward(_arm_speed, target, arm_accel_deg * delta)
	var step := minf(deg_to_rad(_arm_speed) * delta, angle)
	if angle < 1e-6:
		_arm_speed = minf(_arm_speed, arm_accel_deg * delta)
		return
	var axis := _barrel_local.cross(want)
	if axis.length_squared() < 1e-10:
		return
	_barrel_local = _barrel_local.rotated(axis.normalized(), step).normalized()


func _in_cone(local_dir: Vector3) -> bool:
	return rad_to_deg(Vector3.FORWARD.angle_to(local_dir)) <= arm_cone_deg


func _clamp_to_cone(local_dir: Vector3) -> Vector3:
	var angle := Vector3.FORWARD.angle_to(local_dir)
	var cone := deg_to_rad(arm_cone_deg)
	if angle <= cone:
		return local_dir.normalized()
	var axis := Vector3.FORWARD.cross(local_dir)
	if axis.length_squared() < 1e-10:
		axis = Vector3.UP
	return Vector3.FORWARD.rotated(axis.normalized(), cone)


## The arm's shoulder on the hull's front right; the muzzle at the end of the barrel.
const GUN_LENGTH := 5.0
func _gun_pivot_local() -> Vector3:
	return Vector3(0.55, 0.0, -0.83).normalized() * radius


func _place_gun() -> void:
	if _gun == null:
		return
	var dir := get_barrel_direction()
	var pivot := global_transform * _gun_pivot_local()
	var up := global_basis.y if absf(dir.dot(global_basis.y)) < 0.98 else global_basis.x
	_gun.global_transform = Transform3D(Basis.looking_at(dir, up), pivot)
	_muzzle.global_position = pivot + dir * GUN_LENGTH


func _face_quarry() -> void:
	if quarry != null and is_instance_valid(quarry):
		var to := _quarry_centre() - global_position
		if to.length() > 1.0:
			var up := Vector3.UP if absf(to.normalized().y) < 0.98 else Vector3.RIGHT
			global_basis = Basis.looking_at(to.normalized(), up)
	_barrel_local = Vector3.FORWARD
	_place_gun()


func _quarry_radius() -> float:
	return quarry.get_meta(&"hud_radius", 8.0) if quarry != null else 8.0


func _range_to_quarry() -> float:
	return _quarry_centre().distance_to(global_position)


## Where the beam leaves the barrel this tick: [position, velocity, direction].
func _beam_state() -> Array:
	return [_muzzle.global_position, velocity + _beam_dir * shot.speed, _beam_dir]


## Lead direction on the quarry from the muzzle, or zero if out of reach. `reach`: how far
## a beam already out has got.
func _lead(reach: float) -> Vector3:
	if use_track:
		return _lead_from_track(reach)
	var quarry_velocity := (quarry as RigidBody3D).linear_velocity if quarry is RigidBody3D else Vector3.ZERO
	var rel_pos := _quarry_centre() - _muzzle.global_position
	if rel_pos.length() > fire_range:
		return Vector3.ZERO
	var rel_vel := quarry_velocity - velocity
	var t := SpatialMath.intercept_time_ahead(rel_pos, rel_vel, shot.speed, reach)
	if t < 0.0 or t > shot.lifetime:
		return Vector3.ZERO
	return (rel_pos + rel_vel * t).normalized()


## The cue: the threat's selected weapon spooling while it is locked on us. React after
## `dodge_reaction` with a hard thrust across the line of sight, held a moment.
func _watch_threat(delta: float) -> void:
	if not is_instance_valid(threat):
		threat = null
		return
	var weapon := threat.selected
	var cue := weapon != null and weapon.is_spooling() and threat.locked == self
	if cue and not _cue_seen:
		_dodge_in = dodge_reaction
	_cue_seen = cue
	if _dodge_in < 0.0:
		return
	_dodge_in -= delta
	if _dodge_in > 0.0:
		return
	_dodge_in = -1.0
	var los := (global_position - threat.get_view_origin()).normalized()
	var side := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	side = (side - los * side.dot(los)).normalized()
	_accel = side * dodge_accel_g * 9.81
	_jink_due = randf_range(dodge_hold.x, dodge_hold.y)
	dodges += 1


## Its own sensor track of the quarry: angles and range with noise, delivered late.
func _update_track(delta: float) -> void:
	if quarry == null or not is_instance_valid(quarry):
		_track = null
		return
	if _track == null:
		_track = SensorTrack.new()
	_track_due -= delta
	if _track_due <= 0.0:
		_track_due += track_interval
		var at := _quarry_centre()
		var rel := at - global_position
		var r := rel.length() + randfn(0.0, track_range_sigma)
		var sigma := track_sigma_mrad * 1e-3
		var dir := rel.normalized()
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var x := up.cross(dir).normalized()
		var y := dir.cross(x)
		var noisy := (dir + x * randfn(0.0, sigma) + y * randfn(0.0, sigma)).normalized()
		var cross := r * sigma
		var b := Basis(x, y, dir)
		var cov := b * Basis(Vector3(cross * cross + 1.0, 0, 0), Vector3(0, cross * cross + 1.0, 0),
				Vector3(0, 0, track_range_sigma * track_range_sigma + 1.0)) * b.transposed()
		_track_queue.append([_time + track_latency, _time, global_position + noisy * r, cov])
	var keep: Array = []
	for m in _track_queue:
		if m[0] <= _time:
			_track.add_measurement(m[1], m[2], m[3])
		else:
			keep.append(m)
	_track_queue = keep
	_track.tick(_time)


func _lead_from_track(reach: float) -> Vector3:
	if _track == null or not _track.has_solution():
		return Vector3.ZERO
	var est := _track.get_estimate(_time)
	var rel_pos: Vector3 = est[0] - _muzzle.global_position
	if rel_pos.length() > fire_range:
		return Vector3.ZERO
	var rel_vel: Vector3 = est[1] - velocity
	var acc: Vector3 = est[2]
	var t := SpatialMath.intercept_time_ahead(rel_pos, rel_vel, shot.speed, reach)
	for i in 3:
		if t < 0.0:
			return Vector3.ZERO
		t = SpatialMath.intercept_time_ahead(rel_pos + acc * (0.5 * t * t), rel_vel, shot.speed, reach)
	if t < 0.0 or t > shot.lifetime:
		return Vector3.ZERO
	return (rel_pos + rel_vel * t + acc * (0.5 * t * t)).normalized()


func _quarry_centre() -> Vector3:
	if quarry is RigidBody3D:
		return quarry.global_transform * (quarry as RigidBody3D).center_of_mass
	return quarry.global_position


## The gun arm: a barrel on a shoulder at the front right, with its E-cap pack on it.
func _build_gun() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.14, 0.16)
	dark.roughness = 0.7
	_gun = Node3D.new()
	_gun.name = "Gun"
	add_child(_gun)
	var barrel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, GUN_LENGTH)
	box.material = dark
	barrel.mesh = box
	barrel.position = Vector3(0.0, 0.0, -GUN_LENGTH * 0.5)
	_gun.add_child(barrel)
	_pack = MeshInstance3D.new()
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(1.4, 1.6, 1.8)
	var pack_mat := StandardMaterial3D.new()
	pack_mat.albedo_color = Color(0.5, 0.48, 0.42)
	pack_mat.roughness = 0.6
	pack_mesh.material = pack_mat
	_pack.mesh = pack_mesh
	_pack.position = Vector3(0.0, -1.1, -GUN_LENGTH * 0.35)
	_gun.add_child(_pack)
	_place_gun()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.55, 0.3, 0.12) if behaviour == Behaviour.TURRET else Color(0.6, 0.55, 0.2)
	_material.roughness = 0.6
	_material.metallic = 0.3
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.45, 0.15)
	_material.emission_energy_multiplier = 0.4
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = _material
	ball.mesh = mesh
	add_child(ball)
	_ball = ball
	# A dark band and two pods, so its spin and size read at a distance.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.roughness = 0.8
	var band := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = radius * 1.04
	ring.bottom_radius = radius * 1.04
	ring.height = radius * 0.3
	ring.radial_segments = 12
	ring.material = dark
	band.mesh = ring
	add_child(band)
	for side in [-1.0, 1.0]:
		var pod := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.9)
		box.material = dark
		pod.mesh = box
		pod.position = Vector3(side * radius * 1.05, 0.0, 0.0)
		add_child(pod)
