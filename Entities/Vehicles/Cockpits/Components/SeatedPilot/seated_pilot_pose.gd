class_name SeatedPilotPose
extends SkeletonModifier3D

## Poses a humanoid skeleton sitting at the controls, from its rest pose every frame:
##   spine and head   lean (SeatedPilot.lean), the torso's turn for the look
##                    (SeatedPilot.torso) and the head's own turn on it (SeatedPilot.look)
##   legs, arms       two-bone IK onto the Foot*/Hand* markers of the cockpit model
##   feet, hands      turned onto the markers' frames (−Z along the foot / fingers, +Y
##                    out of the instep / back of the hand); fingers curled round the grip
## Everything is solved in skeleton space from the rest pose, so the bones' own axes
## don't matter. Bone names default to the Amate model's, whose arm and leg bones are
## named one joint off: "upperArm" + "forearm" make the upper arm (shoulder to elbow),
## "hand" is the forearm, "foot" the shin.

@export var spine_bones: Array[StringName] = [&"spine_02", &"neck_03"]
@export var head_bone: StringName = &"head_04"
## Per side (L, R): upper bone (at the shoulder / hip), lower bone (its head is the elbow /
## knee), end bone (its head is the wrist / ankle). Bones between them stay rigid.
@export var arm_bones: Array[StringName] = [
	&"upperArm.L_031", &"hand.L_033", &"middle1.L_041",
	&"upperArm.R_08", &"hand.R_010", &"middle1.R_018"]
@export var leg_bones: Array[StringName] = [
	&"leg.L_057", &"foot.L_058", &"footTip.L_059",
	&"leg.R_053", &"foot.R_054", &"footTip.R_055"]
## The hand has no bone of its own: these all start at the wrist and turn together.
@export var hand_roots: Array[StringName] = [&"thumb1", &"index1", &"middle1", &"ring1", &"pinky1"]
@export var curled_fingers: Array[StringName] = [&"index", &"middle", &"ring", &"pinky"]
## Curl of each finger joint after the knuckle, deg.
@export var finger_curl_deg := Vector3(40.0, 48.0, 30.0)
@export var thumb_curl_deg: float = 18.0
@export var hand_targets: Array[StringName] = [&"HandL", &"HandR"]
@export var foot_targets: Array[StringName] = [&"FootL", &"FootR"]
## The cockpit model's node that turns for the hatch (the seated pilot turns with it).
@export var seat_swing_name: StringName = &"SeatSwing"
## Where the elbows and knees point, in the seat frame (x mirrored for the left side).
@export var elbow_pole := Vector3(0.9, -1.0, 0.5)
@export var knee_pole := Vector3(0.12, 1.0, -0.5)
## Share of the look the head takes (the rest is the eyes'), and its limits, deg.
@export_range(0.0, 1.0) var head_look_share: float = 0.9
@export var head_look_limit_deg := Vector2(95.0, 60.0)

var pilot: SeatedPilot

var _hands: Array[Node3D] = [null, null]
var _hand_stays: Array[bool] = [false, false]
var _feet: Array[Node3D] = [null, null]
var _rest_global := {}   # bone index → rest pose in skeleton space
var _ready_done := false
var _arms: Array[PackedInt32Array] = []
var _legs: Array[PackedInt32Array] = []
var _hand_frames: Array[Basis] = []      # rest frame of each hand (−Z fingers, +Y back of hand)
var _finger_axis: Array[Vector3] = []    # curl axis of each hand, rest skeleton space
var _foot_frame := Basis.IDENTITY        # rest frame of the feet (−Z toes, +Y up)
var _hand_bones: Array[PackedInt32Array] = []   # per side: the bones starting at the wrist
var _curls: Array[Array] = []                   # per side: [bone, curl deg] of every finger joint


func find_targets(model: Node) -> void:
	for i in 2:
		_hands[i] = model.find_child(hand_targets[i], true, false) as Node3D
		_feet[i] = model.find_child(foot_targets[i], true, false) as Node3D
		# A control outside the part that turns for the hatch stays behind.
		var node: Node = _hands[i]
		_hand_stays[i] = node != null
		while node != null and node != model:
			if node.name == seat_swing_name:
				_hand_stays[i] = false
			node = node.get_parent()


func _setup(sk: Skeleton3D) -> void:
	_ready_done = true
	for b in sk.get_bone_count():
		var parent := sk.get_bone_parent(b)
		var rest := sk.get_bone_rest(b)
		_rest_global[b] = (_rest_global[parent] as Transform3D) * rest if parent >= 0 else rest
	for side in 2:
		_arms.append(_chain(sk, arm_bones, side))
		_legs.append(_chain(sk, leg_bones, side))
		# Hand frame from the rest pose: fingers along the middle finger's root, the
		# knuckle line giving the palm's plane.
		var suffix := ".L" if side == 0 else ".R"
		var fingers := _tail_dir(sk, _find(sk, "middle1" + suffix))
		# Across the knuckles, from the little finger toward the thumb's side.
		var to_thumb := _tail_pos(sk, _find(sk, "index1" + suffix)) - _tail_pos(sk, _find(sk, "pinky1" + suffix))
		to_thumb = (to_thumb - fingers * to_thumb.dot(fingers)).normalized()
		var back := (to_thumb.cross(fingers) if side == 0 else fingers.cross(to_thumb)).normalized()
		_hand_frames.append(Basis(back.cross(-fingers), back, -fingers).orthonormalized())
		_finger_axis.append(back.cross(fingers).normalized())
		var roots := PackedInt32Array()
		for root in hand_roots:
			roots.append(_find(sk, String(root) + suffix))
		_hand_bones.append(roots)
		var curls := []
		for finger in curled_fingers:
			for joint in 3:
				curls.append([_find(sk, "%s%d%s" % [finger, joint + 2, suffix]), finger_curl_deg[joint]])
		for joint in 2:
			curls.append([_find(sk, "thumb%d%s" % [joint + 2, suffix]), thumb_curl_deg])
		_curls.append(curls)
	# The model stands on flat ground at rest, facing square to its hips (left × up).
	if _legs[0].size() < 3 or _legs[1].size() < 3:
		return
	var up := (sk.global_basis.inverse() * pilot.character.global_basis.y).normalized()
	var left := (_rest_global[_legs[0][0]] as Transform3D).origin - (_rest_global[_legs[1][0]] as Transform3D).origin
	var toes := left.cross(up).normalized()
	_foot_frame = Basis(up.cross(-toes), up, -toes).orthonormalized()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or pilot == null:
		return
	if not _ready_done:
		_setup(sk)
	var world := sk.get_global_transform_interpolated()
	var to_skel := world.affine_inverse()
	var seat := (to_skel.basis * pilot.get_global_transform_interpolated().basis).orthonormalized()

	_lean_and_look(sk, seat)
	for side in 2:
		var mirror := Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0)
		var foot := _feet[side]
		if foot != null and _legs[side].size() == 3:
			var xf := to_skel * foot.get_global_transform_interpolated()
			_two_bone_ik(sk, _legs[side], xf.origin, seat * (knee_pole * mirror))
			_set_global_basis(sk, _legs[side][2],
					xf.basis.orthonormalized() * _foot_frame.inverse() * _rest_basis(_legs[side][2]))
		var hand := _hands[side]
		if hand != null and _arms[side].size() == 3:
			var xf := to_skel * hand.get_global_transform_interpolated()
			if _hand_stays[side] and pilot.let_go > 0.0:
				# This control stays behind when the seat turns: the hand goes to the lap.
				var lap := to_skel * pilot.get_global_transform_interpolated() \
						* Transform3D(Basis.IDENTITY, pilot.lap_hand_position * mirror)
				xf = Transform3D(xf.basis.orthonormalized().slerp(lap.basis.orthonormalized(), pilot.let_go),
						xf.origin.lerp(lap.origin, pilot.let_go))
			_two_bone_ik(sk, _arms[side], xf.origin, seat * (elbow_pole * mirror))
			_pose_hand(sk, side, xf.basis.orthonormalized())


func _lean_and_look(sk: Skeleton3D, seat: Basis) -> void:
	var lean := pilot.lean
	var share := 1.0 / maxi(spine_bones.size(), 1)
	# Lean right = roll about the seat's forward axis, lean forward = pitch down.
	var sway := Basis(seat.z, deg_to_rad(-lean.x) * share) * Basis(seat.x, deg_to_rad(-lean.y) * share)
	# The torso's turn for the look, shared out along the spine.
	var torso := seat * pilot.torso * seat.inverse()
	var step := Basis(Quaternion.IDENTITY.slerp(Quaternion(torso.orthonormalized()), share))
	for bone_name in spine_bones:
		var b := sk.find_bone(bone_name)
		if b >= 0:
			_set_global_basis(sk, b, step * sway * _global_basis(sk, b))
	var head := sk.find_bone(head_bone)
	if head < 0:
		return
	# The head takes what is left of the look, on the turned torso.
	var e := (pilot.torso.inverse() * pilot.look).get_euler(EULER_ORDER_YXZ)
	var yaw := clampf(e.y, -deg_to_rad(head_look_limit_deg.x), deg_to_rad(head_look_limit_deg.x)) * head_look_share
	var pitch := clampf(e.x, -deg_to_rad(head_look_limit_deg.y), deg_to_rad(head_look_limit_deg.y)) * head_look_share
	var turn := torso * (seat * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * seat.inverse()) * torso.inverse()
	_set_global_basis(sk, head, turn * _global_basis(sk, head))


## Turns the hand onto `target` (skeleton space) and curls the fingers.
func _pose_hand(sk: Skeleton3D, side: int, target: Basis) -> void:
	var turn := target * _hand_frames[side].inverse()
	for b in _hand_bones[side]:
		if b >= 0:
			_set_global_basis(sk, b, turn * _rest_basis(b))
	for curl: Array in _curls[side]:
		_curl(sk, curl[0], _finger_axis[side], curl[1])


## Bends a joint about `axis` (rest skeleton space), on top of its rest pose.
func _curl(sk: Skeleton3D, bone: int, axis: Vector3, angle_deg: float) -> void:
	if bone < 0:
		return
	var local_axis := (_rest_basis(bone).inverse() * axis).normalized()
	sk.set_bone_pose_rotation(bone, sk.get_bone_rest(bone).basis.get_rotation_quaternion()
			* Quaternion(local_axis, deg_to_rad(angle_deg)))


## Analytic two-bone IK: chain = [upper, lower, end]; the end bone's head goes to
## `target`, the middle joint bends toward `pole` (both in skeleton space).
func _two_bone_ik(sk: Skeleton3D, chain: PackedInt32Array, target: Vector3, pole: Vector3) -> void:
	var a := sk.get_bone_global_pose(chain[0]).origin
	var b := sk.get_bone_global_pose(chain[1]).origin
	var c := sk.get_bone_global_pose(chain[2]).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to_target := target - a
	var d := clampf(to_target.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var dir := to_target.normalized()
	var bend := pole - dir * pole.dot(dir)
	bend = bend.normalized() if bend.length_squared() > 1e-8 else dir.cross(Vector3.RIGHT).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var mid := a + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	var end := a + dir * d
	_aim(sk, chain[0], b - a, mid - a)
	b = sk.get_bone_global_pose(chain[1]).origin
	c = sk.get_bone_global_pose(chain[2]).origin
	_aim(sk, chain[1], c - b, end - b)


## Swings a bone by the shortest arc taking direction `from` to `to` (skeleton space).
func _aim(sk: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 1e-10 or to.length_squared() < 1e-10:
		return
	_set_global_basis(sk, bone, Basis(Quaternion(from.normalized(), to.normalized())) * _global_basis(sk, bone))


func _global_basis(sk: Skeleton3D, bone: int) -> Basis:
	return sk.get_bone_global_pose(bone).basis.orthonormalized()


func _rest_basis(bone: int) -> Basis:
	return (_rest_global[bone] as Transform3D).basis.orthonormalized()


## Sets a bone's orientation in skeleton space, keeping its place and scale.
func _set_global_basis(sk: Skeleton3D, bone: int, global_basis: Basis) -> void:
	var parent := sk.get_bone_parent(bone)
	var parent_basis := _global_basis(sk, parent) if parent >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (parent_basis.inverse() * global_basis).get_rotation_quaternion())


## Direction from a bone's head to its first child's head, at rest.
func _tail_dir(sk: Skeleton3D, bone: int) -> Vector3:
	if bone < 0:
		return Vector3.FORWARD
	return (_tail_pos(sk, bone) - (_rest_global[bone] as Transform3D).origin).normalized()


## A bone's tail (its first child's head) at rest, skeleton space.
func _tail_pos(sk: Skeleton3D, bone: int) -> Vector3:
	var children := sk.get_bone_children(bone) if bone >= 0 else PackedInt32Array()
	if children.is_empty():
		return Vector3.ZERO if bone < 0 else (_rest_global[bone] as Transform3D).origin
	return (_rest_global[children[0]] as Transform3D).origin


func _chain(sk: Skeleton3D, names: Array[StringName], side: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in 3:
		var b := sk.find_bone(names[side * 3 + i])
		if b < 0:
			push_warning("SeatedPilotPose: no bone '%s'" % names[side * 3 + i])
			return PackedInt32Array()
		out.append(b)
	return out


## Bone whose name starts with `prefix` (the model's names carry an index suffix).
func _find(sk: Skeleton3D, prefix: String) -> int:
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).begins_with(prefix):
			return b
	return -1
