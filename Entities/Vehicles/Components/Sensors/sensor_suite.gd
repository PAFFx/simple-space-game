class_name SensorSuite
extends Node

## The suit's targeting sensors and the track on the locked target (see
## Docs/PhysicsAndSensors/sensors.md). Under Minovsky interference DGFT targeting is
## optical: cameras for angles, a laser rangefinder for range. The pilot only locks; from
## then on the head's main camera follows the track, the rangefinder lases (DGFT) and the
## filter tracks. FireControl reads the estimate, never the target itself.
##
##   main camera   in the head: a telescope (narrow field, ~20 µrad) and a wide field on
##                 one gimbal with the neck's limits and slew. Points at the track's
##                 prediction (or the pilot's designation before there is one).
##   stereo        the twin eyes' baseline gives a range, good only close in.
##   rangefinder   boresighted to the telescope: needs the target in the narrow field.
##                 On in DGFT only; the target can tell it is being lased.
##   body cameras  fixed, wide and coarse, all around the suit: a degraded track (and
##                 reacquire) when the head can't see the target.
##   known size    the target's apparent size, once it's identified: a last resort range.
##
## Each measurement is the direction to the target's visible centroid (which wanders
## about its centre as its limbs move and its plumes flare), plus noise, delivered after
## the sensor's processing latency.

enum Source { NONE, NARROW, WIDE, BODY }
enum RangeSource { NONE, LASER, STEREO, SIZE }

## Laser on/off follows the master mode: DGFT on, NAV and BVR off.
@export var enabled: bool = true

@export_group("Main camera")
@export var narrow_half_fov_deg: float = 1.0
@export var wide_half_fov_deg: float = 30.0
@export var narrow_sigma_mrad: float = 0.02
@export var wide_sigma_mrad: float = 0.3
@export var camera_latency: float = 0.04
## Head gimbal, body frame: azimuth ± and elevation range, deg; slew rate and acceleration.
@export var head_az_limit_deg: float = 100.0
@export var head_el_limits_deg := Vector2(-40.0, 50.0)
@export var head_slew_deg: float = 220.0
@export var head_accel_deg: float = 1500.0
@export var stereo_baseline: float = 0.4

@export_group("Laser rangefinder")
@export var laser_sigma: float = 0.5
@export var laser_interval: float = 0.1
@export var laser_latency: float = 0.02
@export var laser_range: float = 15000.0

@export_group("Body cameras")
@export var body_sigma_mrad: float = 1.0
@export var body_interval: float = 1.0 / 30.0
@export var body_latency: float = 0.06
## Camera positions (body frame, m) and the way each faces; each sees a hemisphere.
@export var body_camera_positions: PackedVector3Array = [
	Vector3(0, 17.0, -2.4), Vector3(0, 18.5, 5.5), Vector3(4.9, 19.0, 0.4), Vector3(-4.9, 19.0, 0.4),
	Vector3(0, 12.0, -2.0), Vector3(0, 12.0, 2.2)]
@export var body_camera_facings: PackedVector3Array = [
	Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, -0.5, -1), Vector3(0, -0.5, 1)]

@export_group("Target")
## Visible centroid wander: share of the target's radius, and how fast it changes, s.
@export var centroid_wander: float = 0.04
@export var centroid_time: float = 0.3
## Range from the identified target's apparent size: relative error.
@export var size_range_error: float = 0.1

var target: Node3D
var track: SensorTrack
## Telemetry: what measured last, where the range came from, whether the laser is on it.
var source := Source.NONE
var range_source := RangeSource.NONE
var lasing := false
## Head gimbal, body frame az / el and their rates, deg.
var head_aim := Vector2.ZERO
var head_rate := Vector2.ZERO

var _vehicle: VehicleBase
var _body: RigidBody3D
var _fcs: FireControl
var _time := 0.0
var _queue: Array = []          ## [deliver, capture, position, covariance]
var _wander := Vector3.ZERO
var _laser_due := 0.0
var _body_due := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_vehicle = VehicleBase.find_vehicle(self)
	_body = _vehicle as Node as RigidBody3D
	_fcs = _vehicle.find_component(FireControl) as FireControl if _vehicle != null else null


## Starts tracking `node` (null stops). Called by FireControl on lock.
func set_target(node: Node3D) -> void:
	if node == target:
		return
	target = node
	track = SensorTrack.new() if node != null else null
	_queue.clear()
	_wander = Vector3.ZERO
	_laser_due = 0.0
	source = Source.NONE
	range_source = RangeSource.NONE
	lasing = false


func get_time() -> float:
	return _time


## The head's main camera boresight, world.
func get_head_direction() -> Vector3:
	return _body_basis() * SpatialMath.angles_to_direction(head_aim)


func get_eye() -> Vector3:
	return _fcs.get_view_origin() if _fcs != null else _vehicle.global_position


## One physics tick. FireControl calls it between reading the lock and the weapons
## solving, so they shoot from this tick's estimate.
func step(delta: float) -> void:
	_time += delta
	if not enabled or _body == null:
		return
	if target != null and not is_instance_valid(target):
		set_target(null)
	_slew_head(delta)
	lasing = false
	if target == null:
		source = Source.NONE
		return
	_update_wander(delta)
	_measure(delta)
	_deliver()
	track.tick(_time)


## Points the head at the track's prediction, else at the pilot's designation.
func _slew_head(delta: float) -> void:
	var want_dir := -_body_basis().z
	if track != null and track.is_started():
		want_dir = (track.get_estimate(_time)[0] - get_eye()).normalized()
	elif _fcs != null:
		want_dir = _fcs.get_designation()
	var want := SpatialMath.direction_to_angles(_body_basis().inverse() * want_dir)
	want = Vector2(clampf(want.x, -head_az_limit_deg, head_az_limit_deg),
			clampf(want.y, head_el_limits_deg.x, head_el_limits_deg.y))
	var to := want - head_aim
	var dist := to.length()
	var speed := minf(head_slew_deg, sqrt(2.0 * head_accel_deg * dist))
	head_rate = head_rate.move_toward(to / maxf(dist, 1e-6) * speed, head_accel_deg * delta)
	var step := head_rate * delta
	if step.length() >= dist:
		head_aim = want
		head_rate = Vector2.ZERO
	else:
		head_aim += step


func _update_wander(delta: float) -> void:
	var radius: float = target.get_meta(&"hud_radius", 10.0)
	var sigma := radius * centroid_wander
	var k := delta / maxf(centroid_time, 1e-3)
	var kick := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * sigma * sqrt(2.0 * k)
	_wander += -_wander * k + kick


func _measure(delta: float) -> void:
	var eye := get_eye()
	var truth := target.global_position + _wander
	var rel := truth - eye
	var dist := rel.length()
	if dist < 1.0:
		return
	var dir := rel / dist
	var off := rad_to_deg(dir.angle_to(get_head_direction()))
	var clear := _line_clear(eye, truth)
	var sigma := 0.0
	var latency := camera_latency
	source = Source.NONE
	if clear and off <= narrow_half_fov_deg:
		source = Source.NARROW
		sigma = narrow_sigma_mrad * 1e-3
	elif clear and off <= wide_half_fov_deg:
		source = Source.WIDE
		sigma = wide_sigma_mrad * 1e-3
	else:
		_body_due -= delta
		if _body_due <= 0.0:
			_body_due += body_interval
			if _body_camera_sees(truth):
				source = Source.BODY
				sigma = body_sigma_mrad * 1e-3
				latency = body_latency

	# Laser: DGFT only, on a target the telescope holds. A pulse's range goes out with
	# that tick's angles; between pulses the range comes from the other sources (aging a
	# pulse with the track's own velocity fed its errors back into it).
	var laser_on := _fcs != null and _fcs.mode == FireControl.MasterMode.DGFT and source == Source.NARROW \
			and dist <= laser_range
	lasing = laser_on
	_laser_due -= delta
	var pulse := laser_on and _laser_due <= 0.0
	if pulse:
		_laser_due = laser_interval
	if source == Source.NONE:
		return

	# Range: the best source this tick.
	var r := -1.0
	var sigma_r := INF
	range_source = RangeSource.NONE
	if pulse:
		r = (target.global_position - eye).length() + _rng.randfn() * laser_sigma
		sigma_r = laser_sigma
		range_source = RangeSource.LASER
	var stereo_sigma := dist * dist * sigma / stereo_baseline
	if source != Source.BODY and stereo_sigma < sigma_r:
		r = dist + _rng.randfn() * stereo_sigma
		sigma_r = stereo_sigma
		range_source = RangeSource.STEREO
	var size_sigma := dist * size_range_error
	if size_sigma < sigma_r:
		r = dist * (1.0 + _rng.randfn() * size_range_error)
		sigma_r = size_sigma
		range_source = RangeSource.SIZE
	r = maxf(r, 1.0)

	# Angles: the true direction turned by the camera's noise.
	var basis := _los_basis(dir)
	var noisy := (dir + basis.x * _rng.randfn() * sigma + basis.y * _rng.randfn() * sigma).normalized()
	var pos := eye + noisy * r
	# The centroid's wander is part of the error: it isn't white, but leaving it out made
	# honest measurements fail the gate.
	var wander_var := pow(float(target.get_meta(&"hud_radius", 10.0)) * centroid_wander, 2.0)
	var cross2 := r * r * sigma * sigma + wander_var
	var along2 := sigma_r * sigma_r + wander_var
	var cov := basis * Basis(Vector3(cross2, 0, 0), Vector3(0, cross2, 0), Vector3(0, 0, along2)) * basis.transposed()
	_queue.append([_time + latency, _time, pos, cov])


func _deliver() -> void:
	var due: Array = []
	var keep: Array = []
	for m in _queue:
		if m[0] <= _time:
			due.append(m)
		else:
			keep.append(m)
	_queue = keep
	due.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	for m in due:
		track.add_measurement(m[1], m[2], m[3])


func _body_camera_sees(at: Vector3) -> bool:
	var basis := _body_basis()
	for i in body_camera_positions.size():
		var cam := _body.global_transform * body_camera_positions[i]
		var facing := (basis * body_camera_facings[i]).normalized()
		if facing.dot(at - cam) > 0.0 and _line_clear(cam, at):
			return true
	return false


## Nothing but the suit itself and the target between `from` and `to`.
func _line_clear(from: Vector3, to: Vector3) -> bool:
	var space := _body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = [_body.get_rid()]
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()


func _body_basis() -> Basis:
	return _body.global_basis.orthonormalized()


## x, y across the line of sight, z along it.
static func _los_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	return Basis(x, y, dir)
