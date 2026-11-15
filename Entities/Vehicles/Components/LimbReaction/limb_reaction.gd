class_name LimbReaction
extends Node

## Newton's third law for the limbs. Swinging an arm (rifle raised, shield guard, weapon
## aim), turning the head or the backpack pods pushes the body the other way. The last
## skeleton modifier snapshots the final pose (whatever moved it: animation, aim, AMBAC);
## each physics tick take_torque() turns the change since the previous tick into the
## angular momentum of the tracked segments (and the equipment they carry) relative to
## `reference_bone`, about the suit's centre of mass. Its change is the impulse the limbs
## took from the body, so the body gets the opposite (applied by the FlightComputer).
##
## Motion below the reference (waist, legs) stays AMBAC's own joint model. The fire
## control's torso twist turns the reference itself, so it's added as `torso_twist_inertia`.
## AMBAC joints on tracked bones are marked measured: AMBAC still plans with them, with
## their inertia from this mass model, but their torque comes from here.

@export var enabled: bool = true
@export var skeleton: Skeleton3D
@export var reference_bone: StringName = &"chest"
@export var segments: Array[LimbSegment] = []
## Upper body about the up axis, for the fire control's torso twist (kg·m²).
@export var torso_twist_inertia: float = 1.2e5
## Time after start (or re-enabling) before motion counts: the first frames snap the
## limbs from the bind pose into the animation, which isn't a real motion.
@export var warmup_time: float = 0.3
## Low-pass on the measured momentum, s. Velocities come from poses that advance on two
## clocks (animation per frame, aim and AMBAC per tick), so a tick sees 0, 1 or 2 frames of
## motion; differencing that raw gave torque noise far above the real reaction (thrusters
## pulsing while just holding a lock). Smoothing keeps the total impulse, only spreads it.
@export var momentum_smoothing: float = 0.06

var last_momentum := Vector3.ZERO   ## Tracked limbs' angular momentum (smoothed), body frame (N·m·s)
var _raw_momentum := Vector3.ZERO

var _body: RigidBody3D
var _fire_control: FireControl
var _ref := -1
var _bones := PackedInt32Array()
var _mass := PackedFloat32Array()
var _com: Array[Vector3] = []       ## Centre of mass in bone space (skeleton units)
var _inertia: Array[Basis] = []     ## About the centre, in the bone's rest orientation (body units)
# Latest final pose (from the modifier pass), relative to the reference bone, and the
# one the last physics tick used. Aim, AMBAC and the pose layers advance per physics tick
# while frames may run faster or slower, so velocities are taken from tick to tick, over
# the physics ticks between the two poses.
var _snap_pos: Array[Vector3] = []
var _snap_rot: Array[Basis] = []
var _snap_twist := 0.0
var _snap_ref_rot := Basis.IDENTITY
var _snap_com := Vector3.ZERO
var _fresh := false
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
	# After the loadout has mounted its equipment.
	_setup.call_deferred()


## Reaction torque on the body for this physics tick (body frame): minus the change in
## the limbs' angular momentum since the last call, over `delta`.
func take_torque(delta: float) -> Vector3:
	if not enabled or delta <= 0.0:
		return Vector3.ZERO
	_ticks += 1
	if _fresh:
		_measure(_ticks * delta)
		_ticks = 0
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
			var v := (_snap_pos[i] - _used_pos[i]) / dt
			var dq := (_snap_rot[i] * _used_rot[i].transposed()).get_rotation_quaternion()
			var w := AttitudeOffsetSolver.to_rotation_vector(dq) / dt
			var rot := _snap_rot[i]
			momentum += _mass[i] * (_snap_pos[i] - _snap_com).cross(v) + rot * _inertia[i] * rot.transposed() * w
		momentum = _snap_ref_rot * momentum
		# Torso twist: azimuth + is to the right, a negative turn about up.
		momentum += Vector3.UP * (-(_snap_twist - _used_twist) / dt * torso_twist_inertia)
		_raw_momentum = momentum
		if _stage == 1:
			last_momentum = momentum
	_used_pos = _snap_pos.duplicate()
	_used_rot = _snap_rot.duplicate()
	_used_twist = _snap_twist
	_stage = mini(_stage + 1, 2)


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
		var rest := skeleton.get_bone_global_rest(_bones[i])
		var rot := (bs.basis * rest.basis).orthonormalized()
		var d := bs * (rest * _com[i]) - pivot
		total += a.dot(rot * _inertia[i] * rot.transposed() * a) + _mass[i] * a.cross(d).length_squared()
	return total


func _setup() -> void:
	_ref = skeleton.find_bone(reference_bone)
	if _ref < 0:
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
		_add(idx, seg.mass, box, skeleton.get_bone_global_rest(idx), bs)
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
				_add(idx, eq.mass, box, skeleton.get_bone_global_pose(idx), bs)
	_mark_ambac_joints()
	var modifier := LimbReactionModifier.new()
	modifier.name = "LimbReactionModifier"
	modifier.reaction = self
	skeleton.add_child(modifier)


## Segment from a box in skeleton space, attached to bone `idx` posed at `bone_pose`.
func _add(idx: int, mass: float, box: AABB, bone_pose: Transform3D, bs: Transform3D) -> void:
	var size := (bs.basis * box.size).abs()   # body units (the skeleton may be scaled)
	var ixx := mass / 12.0 * (size.y * size.y + size.z * size.z)
	var iyy := mass / 12.0 * (size.x * size.x + size.z * size.z)
	var izz := mass / 12.0 * (size.x * size.x + size.y * size.y)
	var inertia_body := Basis(Vector3(ixx, 0, 0), Vector3(0, iyy, 0), Vector3(0, 0, izz))
	var rot := (bs.basis * bone_pose.basis).orthonormalized()
	_bones.append(idx)
	_mass.append(mass)
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
	var ref := bs * skeleton.get_bone_global_pose(_ref)
	_snap_ref_rot = ref.basis.orthonormalized()
	var to_ref := _snap_ref_rot.transposed()
	_snap_com = to_ref * (_body.center_of_mass - ref.origin)
	for i in _bones.size():
		var pose := bs * skeleton.get_bone_global_pose(_bones[i])
		_snap_pos[i] = to_ref * (pose * _com[i] - ref.origin)
		_snap_rot[i] = to_ref * pose.basis.orthonormalized()
	_snap_twist = deg_to_rad(_fire_control.get_torso_yaw()) if _fire_control != null else 0.0
	_fresh = true


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
