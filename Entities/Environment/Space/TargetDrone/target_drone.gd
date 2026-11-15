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
	_anchor += _base_velocity * delta
	match behaviour:
		Behaviour.JINK:
			_jink(delta, jink_accel_g)
		Behaviour.TURRET:
			_jink(delta, jink_accel_g * 0.3)
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
	var limit := accel_g * 9.81 * 4.0
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
	manager.spawn(shot, muzzle, velocity + dir * shot.speed, dir, [get_rid()], self)
	manager.muzzle_flash(shot, muzzle, velocity, _muzzle)


## Lead direction on the quarry (with the aim error), or zero if out of reach.
func _aim() -> Vector3:
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
