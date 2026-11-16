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
##   TURRET   jinks gently and shoots back at `quarry` with slow bolts, to practise
##            dodging and the shield
##
## Higher specs, for testing both sides of a fight:
##   dodge     with a `threat` (the shooter's FireControl), it watches the barrel: when the
##             selected weapon spools while locked on it, it thrusts hard across the line of
##             sight after `dodge_reaction`, like a pilot reading the cue.
##   tracking  with `use_track`, a TURRET aims from its own sensor track of the quarry
##             (delayed, noisy angles and range through a SensorTrack, leading with the
##             estimated acceleration) instead of the quarry's true state.

enum Behaviour { STATIC, DRIFT, JINK, TURRET }

signal destroyed(drone: TargetDrone)

@export var behaviour := Behaviour.STATIC
@export var label: String = "DRONE"
@export var radius: float = 7.0
@export var hit_points: float = 300.0
## Velocity it starts with (give it the player's, so it keeps station).
@export var velocity := Vector3.ZERO
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
## Shots fired and dodges started (probes).
var shots_fired := 0
var dodges := 0
var _cue_seen := false
var _dodge_in := -1.0
var _speed_limit_g := 0.0
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
	if behaviour == Behaviour.TURRET and shot == null:
		shot = load("res://Entities/Projectiles/Specs/drone_shot.tres")


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


func _physics_process(delta: float) -> void:
	_time += delta
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
			_shoot(delta)
	global_position += velocity * delta
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
	var dir := _aim()
	if _spool < 0.0:
		_fire_due -= delta
		if _fire_due > 0.0 or dir == Vector3.ZERO:
			return
		_fire_due = randf_range(fire_interval.x, fire_interval.y)
		_spool = 0.0
	# The muzzle glows on the side facing the quarry while it spools: the dodge cue.
	if dir != Vector3.ZERO:
		_muzzle.global_position = global_position + dir * (radius + 1.0)
	_spool += delta
	var level := _spool / maxf(shot.spool_time, 0.01)
	if level < 1.0:
		manager.set_charge(self, _muzzle, shot, level)
		return
	_spool = -1.0
	manager.set_charge(self, _muzzle, shot, 0.0)
	if dir == Vector3.ZERO:
		return
	var muzzle := global_position + dir * (radius + 1.0)
	shots_fired += 1
	manager.spawn(shot, muzzle, velocity + dir * shot.speed, dir, [get_rid()], self)
	manager.muzzle_flash(shot, muzzle, velocity, _muzzle)


## Lead direction on the quarry (with the aim error), or zero if out of reach.
func _aim() -> Vector3:
	if use_track:
		return _aim_from_track()
	var quarry_velocity := (quarry as RigidBody3D).linear_velocity if quarry is RigidBody3D else Vector3.ZERO
	var quarry_centre := quarry.global_position
	if quarry is RigidBody3D:
		quarry_centre = quarry.global_transform * (quarry as RigidBody3D).center_of_mass
	var rel_pos := quarry_centre - global_position
	if rel_pos.length() > fire_range:
		return Vector3.ZERO
	var rel_vel := quarry_velocity - velocity
	var t := SpatialMath.intercept_time(rel_pos, rel_vel, shot.speed)
	if t <= 0.0 or t > shot.lifetime:
		return Vector3.ZERO
	var dir := (rel_pos + rel_vel * t).normalized()
	var error := deg_to_rad(aim_error_deg)
	return (dir + Vector3(randfn(0.0, error), randfn(0.0, error), randfn(0.0, error))).normalized()


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


func _aim_from_track() -> Vector3:
	if _track == null or not _track.has_solution():
		return Vector3.ZERO
	var est := _track.get_estimate(_time)
	var rel_pos: Vector3 = est[0] - global_position
	if rel_pos.length() > fire_range:
		return Vector3.ZERO
	var rel_vel: Vector3 = est[1] - velocity
	var acc: Vector3 = est[2]
	var t := SpatialMath.intercept_time(rel_pos, rel_vel, shot.speed)
	for i in 3:
		if t <= 0.0:
			return Vector3.ZERO
		t = SpatialMath.intercept_time(rel_pos + acc * (0.5 * t * t), rel_vel, shot.speed)
	if t <= 0.0 or t > shot.lifetime:
		return Vector3.ZERO
	var dir := (rel_pos + rel_vel * t + acc * (0.5 * t * t)).normalized()
	var error := deg_to_rad(aim_error_deg)
	return (dir + Vector3(randfn(0.0, error), randfn(0.0, error), randfn(0.0, error))).normalized()


func _quarry_centre() -> Vector3:
	if quarry is RigidBody3D:
		return quarry.global_transform * (quarry as RigidBody3D).center_of_mass
	return quarry.global_position


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
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh.material = _material
	ball.mesh = mesh
	add_child(ball)
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
