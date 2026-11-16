class_name LimbReaction
extends Node

## The suit's mass model, and Newton's third law for its moving parts. Each segment is a
## part of the model (a bone, its mesh's bounds as a solid box, a mass, optionally a
## propellant tank), plus the equipment the tracked bones carry. The last skeleton
## modifier snapshots the final pose (whatever moved it: animation, aim, AMBAC, stances);
## each physics tick take_torque() turns the change since the previous tick into the
## angular momentum of the segments relative to `reference_bone`, about the suit's centre
## of mass. Its change is the impulse the parts took from the body, so the body gets the
## opposite (applied by the FlightComputer).
##
## With `reference_bone` empty every part is measured in the body frame, waist and legs
## included, and AMBAC joints on tracked bones are marked measured: AMBAC still plans with
## them, with their inertia from this mass model, but their torque comes from here. With a
## reference bone, motion below it stays AMBAC's own joint model and the fire control's
## torso twist (which turns the reference) is added as `torso_twist_inertia`.
##
## With `drive_body_mass` the body's centre of mass and inertia follow the parts (pose and
## propellant left), and the hull moves the other way so the suit's centre of mass stays
## put: legs swung forward push the torso back.

@export var enabled: bool = true
@export var skeleton: Skeleton3D
## Bone the parts are measured against. Empty = the body frame (every part measured).
@export var reference_bone: StringName = &"chest"
@export var segments: Array[LimbSegment] = []
## Upper body about the up axis, for the fire control's torso twist (kg·m²). Only used
## with a reference bone.
@export var torso_twist_inertia: float = 1.2e5
## Time after start (or re-enabling) before motion counts: the first frames snap the
## limbs from the bind pose into the animation, which isn't a real motion.
@export var warmup_time: float = 0.3
## Low-pass on the measured momentum, s. Velocities come from poses that advance on two
## clocks (animation per frame, aim and AMBAC per tick), so a tick sees 0, 1 or 2 frames of
## motion; differencing that raw gave torque noise far above the real reaction (thrusters
## pulsing while just holding a lock). Smoothing keeps the total impulse, only spreads it.
@export var momentum_smoothing: float = 0.06

@export_group("Mass properties")
## Drive the body's centre of mass and inertia from the parts.
@export var drive_body_mass: bool = false
## Changes smaller than these aren't sent to the physics body (each one rebuilds its
## shape): m, and relative for the inertia.
@export var com_tolerance: float = 0.005
@export var inertia_tolerance: float = 0.005
## AMBAC's measured joint inertias are refreshed when the propellant fill changes by this.
@export var joint_refresh_fill: float = 0.02
## The flight computer's force capability map (torque arms about the centre of mass) is
## rebuilt when the centre has moved this far since it was built, m.
@export var map_rebuild_distance: float = 0.1

var last_momentum := Vector3.ZERO   ## Tracked limbs' angular momentum (smoothed), body frame (N·m·s)
var _raw_momentum := Vector3.ZERO
## Mass model now, body frame (telemetry, probes).
var total_mass := 0.0
var centre_of_mass := Vector3.ZERO
var inertia_tensor := Basis()       ## About centre_of_mass, body axes (kg·m²)

var _body: RigidBody3D
var _fire_control: FireControl
var _flight: FlightComputer
var _ref := -1
var _bones := PackedInt32Array()
var _mass := PackedFloat32Array()   ## Dry mass, kg
var _tank := PackedFloat32Array()   ## Propellant when full, kg
var _names: Array[StringName] = []
var _com: Array[Vector3] = []       ## Centre of mass in bone space (skeleton units)
var _inertia: Array[Basis] = []     ## Per kg, about the centre, in the bone's rest orientation (body units)
var _fill := 1.0                    ## Propellant left / capacity
var _fill_joints := 1.0             ## Fill the AMBAC joint inertias were last set for
var _residual_at := Vector3.ZERO    ## Mass the parts don't account for sits here (body frame)
var _applied := false
var _map_com := Vector3.ZERO        ## Centre of mass the capability map was built for
# Latest final pose (from the modifier pass), relative to the reference bone, and the
# one the last physics tick used. Aim, AMBAC and the pose layers advance per physics tick
# while frames may run faster or slower, so velocities are taken from tick to tick, over
# the physics ticks between the two poses.
var _snap_pos: Array[Vector3] = []
var _snap_rot: Array[Basis] = []
var _snap_twist := 0.0
var _snap_ref := Transform3D.IDENTITY   ## Reference in the body frame
var _snap_com := Vector3.ZERO
var _fresh := false
var _posed := false                 ## A pose has been sampled since setup
var _ticks := 0                     ## Physics ticks since the pose last used
var _used_pos: Array[Vector3] = []
var _used_rot: Array[Basis] = []
var _used_twist := 0.0
var _stage := 0                     ## 0: no pose yet, 1: one pose, 2: momentum known
var _warmup := 0.0


func _ready() -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	_body = vehicle as Node as RigidBody3D
	if skeleton == null or _body == null:
		push_error("LimbReaction: needs a skeleton and a RigidBody3D vehicle")
		return
	_fire_control = vehicle.find_component(FireControl) as FireControl
	_flight = vehicle.find_component(FlightComputer) as FlightComputer
	_residual_at = _body.center_of_mass
	# After the loadout has mounted its equipment.
	_setup.call_deferred()


## Reaction torque on the body for this physics tick (body frame): minus the change in
## the limbs' angular momentum since the last call, over `delta`.
func take_torque(delta: float) -> Vector3:
	if not enabled or delta <= 0.0:
		return Vector3.ZERO
	_fill = _flight.get_propellant_fraction() if _flight != null else 1.0
	_ticks += 1
	if _fresh:
		_measure(_ticks * delta)
		_ticks = 0
	if drive_body_mass and _posed:
		_update_mass_properties()
	# No new pose: the limbs keep the momentum last measured.
	if _stage < 2:
		return Vector3.ZERO
	var k := 1.0 if momentum_smoothing <= 0.0 else 1.0 - exp(-delta / momentum_smoothing)
	var smoothed := last_momentum.lerp(_raw_momentum, k)
	var torque := -(smoothed - last_momentum) / delta if _warmup > warmup_time else Vector3.ZERO
	last_momentum = smoothed
	return torque


## Angular momentum of the tracked limbs from the newest pose against the one used last,
## `dt` apart.
func _measure(dt: float) -> void:
	_fresh = false
	var momentum := Vector3.ZERO
	if _stage > 0:
		for i in _bones.size():
			var m := _part_mass(i)
			var v := (_snap_pos[i] - _used_pos[i]) / dt
			var dq := (_snap_rot[i] * _used_rot[i].transposed()).get_rotation_quaternion()
			var w := AttitudeOffsetSolver.to_rotation_vector(dq) / dt
			var rot := _snap_rot[i]
			momentum += m * (_snap_pos[i] - _snap_com).cross(v) + rot * (_inertia[i] * m) * rot.transposed() * w
		momentum = _snap_ref.basis * momentum
		if _ref >= 0:
			# Torso twist: azimuth + is to the right, a negative turn about up.
			momentum += Vector3.UP * (-(_snap_twist - _used_twist) / dt * torso_twist_inertia)
		_raw_momentum = momentum
		if _stage == 1:
			last_momentum = momentum
	_used_pos = _snap_pos.duplicate()
	_used_rot = _snap_rot.duplicate()
	_used_twist = _snap_twist
	_stage = mini(_stage + 1, 2)


func _part_mass(i: int) -> float:
	return _mass[i] + _tank[i] * _fill


## Centre of mass and inertia of the parts in their latest pose, sent to the body when
## they moved enough. The hull is moved by the opposite of the centre's shift and its spin
## rescaled for the new inertia, so the suit's momentum is what it was.
func _update_mass_properties() -> void:
	var parts_mass := 0.0
	var moment := Vector3.ZERO
	var pos: Array[Vector3] = []
	var rots: Array[Basis] = []
	for i in _bones.size():
		var p := _snap_ref * _snap_pos[i]
		pos.append(p)
		rots.append(_snap_ref.basis * _snap_rot[i])
		var m := _part_mass(i)
		parts_mass += m
		moment += p * m
	var total := _flight.get_total_mass() if _flight != null else parts_mass
	var residual := maxf(total - parts_mass, 0.0)
	total = parts_mass + residual
	if total <= 0.0:
		return
	var com := (moment + _residual_at * residual) / total
	# Σ R (m·I) Rᵀ + m (|d|² E − d dᵀ), accumulated as columns (Basis has no +).
	var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for i in _bones.size():
		var m := _part_mass(i)
		var own := rots[i] * (_inertia[i] * m) * rots[i].transposed()
		_add_point(cols, pos[i] - com, m)
		for k in 3:
			cols[k] += own[k]
	_add_point(cols, _residual_at - com, residual)
	total_mass = total
	centre_of_mass = com
	inertia_tensor = Basis(cols[0], cols[1], cols[2])
	if absf(_fill - _fill_joints) > joint_refresh_fill:
		_fill_joints = _fill
		_mark_ambac_joints()

	var diag := Vector3(cols[0].x, cols[1].y, cols[2].z)
	var old_diag := _body.inertia
	var moved := (com - _body.center_of_mass).length() > com_tolerance
	var turned := not _applied or absf(diag.x - old_diag.x) > inertia_tolerance * old_diag.x \
			or absf(diag.y - old_diag.y) > inertia_tolerance * old_diag.y \
			or absf(diag.z - old_diag.z) > inertia_tolerance * old_diag.z
	if not moved and not turned:
		return
	var basis := _body.global_basis.orthonormalized()
	var conserve := _applied and _warmup > warmup_time
	if moved:
		if conserve:
			_body.global_position -= basis * (com - _body.center_of_mass)
		_body.center_of_mass = com
	if turned:
		if conserve:
			var w := basis.transposed() * _body.angular_velocity
			_body.angular_velocity = basis * (old_diag * w / diag)
		_body.inertia = diag
	if _flight != null:
		if not _applied:
			# The first map was built a tick ago, around the scene's placeholder centre.
			_flight.invalidate_capability_map()
			_map_com = com
		elif (com - _map_com).length() > map_rebuild_distance:
			_flight.rebuild_capability_map_async()
			_map_com = com
	_applied = true


static func _add_point(cols: Array[Vector3], d: Vector3, m: float) -> void:
	var dd := d.length_squared()
	cols[0] += Vector3(dd - d.x * d.x, -d.y * d.x, -d.z * d.x) * m
	cols[1] += Vector3(-d.x * d.y, dd - d.y * d.y, -d.z * d.y) * m
	cols[2] += Vector3(-d.x * d.z, -d.y * d.z, dd - d.z * d.z) * m


func tracks_bone(bone: StringName) -> bool:
	if skeleton == null:
		return false
	var idx := skeleton.find_bone(bone)
	return idx >= 0 and _bones.has(idx)


## Inertia (kg·m²) of everything a joint at `bone` turns about `axis` (skeleton space)
## through the bone's head, at rest: the bone's tracked subtree and its equipment.
func joint_inertia(bone: StringName, axis: Vector3) -> float:
	var root := skeleton.find_bone(bone)
	if root < 0:
		return 0.0
	var bs := _body_from_skeleton()
	var pivot := bs * skeleton.get_bone_global_rest(root).origin
	var a := (bs.basis * axis).normalized()
	var total := 0.0
	for i in _bones.size():
		if not _in_subtree(_bones[i], root):
			continue
		var m := _part_mass(i)
		var rest := skeleton.get_bone_global_rest(_bones[i])
		var rot := (bs.basis * rest.basis).orthonormalized()
		var d := bs * (rest * _com[i]) - pivot
		total += a.dot(rot * (_inertia[i] * m) * rot.transposed() * a) + m * a.cross(d).length_squared()
	return total


## Parts with their mass now (dry + propellant), kg, in setup order (equipment after the
## segments). For the HUD and probes.
func get_part_masses() -> Dictionary:
	var out := {}
	for i in _bones.size():
		out[_names[i]] = _part_mass(i)
	return out


func _setup() -> void:
	_ref = skeleton.find_bone(reference_bone) if reference_bone != &"" else -1
	if reference_bone != &"" and _ref < 0:
		push_error("LimbReaction: no reference bone '%s'" % reference_bone)
		return
	var bs := _body_from_skeleton()
	for seg in segments:
		var idx := skeleton.find_bone(seg.bone_name)
		var mesh_name := seg.mesh_name if seg.mesh_name != &"" else _pascal(seg.bone_name)
		var mesh := skeleton.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D
		if idx < 0 or mesh == null:
			push_warning("LimbReaction: skipping %s (bone or mesh '%s' missing)" % [seg.bone_name, mesh_name])
			continue
		# Skinned meshes sit in the bind (rest) pose in skeleton space.
		var box := _skeleton_aabb(mesh)
		_add(idx, seg.bone_name, seg.mass, seg.propellant_capacity, box, skeleton.get_bone_global_rest(idx), bs)
	# Equipment carried by a tracked bone moves with it.
	var loadout := VehicleBase.find_vehicle(self).find_component(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			var idx := skeleton.find_bone(eq.mount_bone)
			if idx < 0 or not _bones.has(idx):
				continue
			var box := AABB()
			var first := true
			for vi in eq.find_children("*", "VisualInstance3D", true, false):
				var b := _skeleton_aabb(vi as VisualInstance3D)
				box = b if first else box.merge(b)
				first = false
			if not first:
				_add(idx, eq.name, eq.mass, 0.0, box, skeleton.get_bone_global_pose(idx), bs)
	if drive_body_mass:
		var tanks := 0.0
		for t in _tank:
			tanks += t
		if _flight != null and absf(tanks - _flight.propellant_capacity) > 0.001 * _flight.propellant_capacity:
			push_warning("LimbReaction: tanks hold %.0f kg, the flight computer %.0f kg" % [tanks, _flight.propellant_capacity])
	_mark_ambac_joints()
	var modifier := LimbReactionModifier.new()
	modifier.name = "LimbReactionModifier"
	modifier.reaction = self
	skeleton.add_child(modifier)


## Segment from a box in skeleton space, attached to bone `idx` posed at `bone_pose`.
func _add(idx: int, part: StringName, mass: float, tank: float, box: AABB, bone_pose: Transform3D, bs: Transform3D) -> void:
	var size := (bs.basis * box.size).abs()   # body units (the skeleton may be scaled)
	var ixx := (size.y * size.y + size.z * size.z) / 12.0
	var iyy := (size.x * size.x + size.z * size.z) / 12.0
	var izz := (size.x * size.x + size.y * size.y) / 12.0
	var inertia_body := Basis(Vector3(ixx, 0, 0), Vector3(0, iyy, 0), Vector3(0, 0, izz))
	var rot := (bs.basis * bone_pose.basis).orthonormalized()
	_bones.append(idx)
	_names.append(part)
	_mass.append(mass)
	_tank.append(tank)
	_com.append(bone_pose.affine_inverse() * box.get_center())
	_inertia.append(rot.transposed() * inertia_body * rot)
	_snap_pos.append(Vector3.ZERO)
	_snap_rot.append(Basis.IDENTITY)


func _mark_ambac_joints() -> void:
	var ambac := VehicleBase.find_vehicle(self).find_component(AmbacController) as AmbacController
	if ambac == null:
		return
	for i in ambac.joints.size():
		var j := ambac.joints[i]
		if tracks_bone(j.bone_name):
			ambac.set_measured(i, joint_inertia(j.bone_name, j.axis))


## Called from the last skeleton modifier with this frame's final pose.
func sample(_skeleton: Skeleton3D, dt: float) -> void:
	if not enabled:
		_stage = 0
		_warmup = 0.0
		_fresh = false
		_ticks = 0
		last_momentum = Vector3.ZERO
		_raw_momentum = Vector3.ZERO
		return
	_warmup += dt
	var bs := _body_from_skeleton()
	var ref := bs * (skeleton.get_bone_global_pose(_ref) if _ref >= 0 else Transform3D.IDENTITY)
	_snap_ref = Transform3D(ref.basis.orthonormalized(), ref.origin)
	var to_ref := _snap_ref.basis.transposed()
	_snap_com = to_ref * (_body.center_of_mass - ref.origin)
	for i in _bones.size():
		var pose := bs * skeleton.get_bone_global_pose(_bones[i])
		_snap_pos[i] = to_ref * (pose * _com[i] - ref.origin)
		_snap_rot[i] = to_ref * pose.basis.orthonormalized()
	_snap_twist = deg_to_rad(_fire_control.get_torso_yaw()) if _fire_control != null else 0.0
	_fresh = true
	_posed = true


func _body_from_skeleton() -> Transform3D:
	return _body.global_transform.affine_inverse() * skeleton.global_transform


func _skeleton_aabb(vi: VisualInstance3D) -> AABB:
	return skeleton.global_transform.affine_inverse() * vi.global_transform * vi.get_aabb()


func _in_subtree(bone: int, root: int) -> bool:
	while bone >= 0:
		if bone == root:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


static func _pascal(bone: StringName) -> StringName:
	var out := ""
	for part in String(bone).replace(".", "_").split("_"):
		out += part.capitalize().replace(" ", "")
	return StringName(out)
