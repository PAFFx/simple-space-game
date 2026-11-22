class_name ArmReachSolver
extends RefCounted

## Poses an arm so its hand sits at a given transform: the local rotations (skeleton
## bone poses) of the lean bones, upper arm, forearm and hand, from the rest pose.
##
## The elbow is a hinge (the axis AMBAC bends it about, skeleton RIGHT at rest) and sets
## the shoulder–wrist distance; the shoulder then points the arm at the wrist, free to swing
## the elbow round that line. Of those swings it takes the one that leaves the wrist the
## least bend (and points the elbow nearest the hint). The hand's roll about the forearm
## goes into the forearm's own twist, up to twist_limit_deg; the wrist keeps the rest.
## Keeping the upper arm and forearm out of the equipment (MsDrawMotion.clearance) comes
## first: the wrist bends as far as it must for that.

const SWING_STEP_DEG := 3.0
## Cost of an elbow pointing away from its hint, deg of wrist bend per unit of (1 − cos).
const HINT_WEIGHT := 40.0
## Cost of the arm inside the equipment, deg of wrist bend per metre of overlap.
const CLEARANCE_WEIGHT := 600.0
## Cost of moving away from an anchor pose (the previous key, the pose it blends into), deg
## of wrist bend per deg the upper arm turns / the forearm rolls: keys solved one by one
## otherwise flip between equally good arms and the motion between them flails.
const UPPER_CONTINUITY := 0.6
const TWIST_CONTINUITY := 0.4


## Every key of `motion` solved in order (bone index → local pose rotation per key), each
## kept near the one before (the first near the arm's rest pose, the last near it too: the
## held pose it blends into is close), so the arm moves through them without flailing.
static func solve_motion(skel: Skeleton3D, motion: MsDrawMotion, mount: Transform3D,
		skel_from_body: Transform3D) -> Array[Dictionary]:
	var upper := skel.find_bone(motion.upper_arm_bone)
	var rest := [skel.get_bone_rest(upper).basis.get_rotation_quaternion(), 0.0, 1.0]
	var keys: Array[Dictionary] = []
	var prev: Array = rest
	var count := motion.get_key_count()
	for i in count:
		var anchors := [prev]
		if i == count - 1 and i > 0:
			anchors.append([rest[0], rest[1], 0.5])
		var chosen: Array = []
		keys.append(solve_key(skel, motion, i, mount, skel_from_body, anchors, chosen))
		if not chosen.is_empty():
			prev = [chosen[0], chosen[1], 1.0]
	return keys


## Bone index → local pose rotation for key `key` of `motion`, the equipment placed at
## `placement` (body frame) when its rest placement in the hand is `mount` (body frame).
## `skel_from_body` maps the body frame into skeleton space.
##
## `anchors`: poses to stay near, each [upper arm local rotation, forearm twist rad, weight];
## `chosen`, if given, gets this key's [upper arm local rotation, forearm twist].
static func solve_key(skel: Skeleton3D, motion: MsDrawMotion, key: int, mount: Transform3D,
		skel_from_body: Transform3D, anchors: Array = [], chosen: Array = []) -> Dictionary:
	var hand := skel.find_bone(motion.hand_bone)
	# The equipment's placement moves the hand with it from its rest pose.
	var hand_target := skel_from_body * motion.get_key(key) * mount.affine_inverse() \
			* skel_from_body.affine_inverse() * skel.get_bone_global_rest(hand)
	var poses := lean_poses(skel, motion, motion.get_lean_weight(key))
	var hint := motion.get_elbow_hint(key)
	if hint != Vector3.ZERO:
		hint = (skel_from_body.basis * hint).normalized()
	# The equipment as obstacles: in the hand from the grab on, on its stow point before.
	var at := motion.get_key(maxi(key, motion.reach_keys.size()))
	var obstacles: Array = []
	for c: Array in motion.clearance:
		obstacles.append([skel_from_body * at * (c[0] as Vector3), skel_from_body * at * (c[1] as Vector3), c[2]])
	poses.merge(solve_arm(skel, skel.find_bone(motion.upper_arm_bone), skel.find_bone(motion.forearm_bone),
			hand, hand_target, poses, deg_to_rad(motion.twist_limit_deg), hint, obstacles,
			Vector2(motion.upper_arm_radius, motion.forearm_radius), anchors, chosen), true)
	return poses


## The motion's lean at `weight` as bone poses.
static func lean_poses(skel: Skeleton3D, motion: MsDrawMotion, weight: float) -> Dictionary:
	var poses := {}
	for bone_name: StringName in motion.lean:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var q := Quaternion.IDENTITY
		for r: Array in motion.lean[bone_name]:
			q = Quaternion((r[0] as Vector3).normalized(), deg_to_rad(r[1]) * weight) * q
		var g := skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
		poses[idx] = _rest_rot(skel, idx) * (g.inverse() * q * g)
	return poses


## Upper arm, forearm and hand poses putting the hand at `target` (skeleton space), with
## the bones above the upper arm posed as in `poses` (rest where absent).
## `obstacles`: capsules [a, b, radius] (skeleton space) the upper arm and forearm
## (capsules of `radii` x, y round their bones) should keep out of.
static func solve_arm(skel: Skeleton3D, upper: int, fore: int, hand: int, target: Transform3D,
		poses: Dictionary, twist_limit: float, hint: Vector3, obstacles: Array = [],
		radii := Vector2(1.0, 1.1), anchors: Array = [], chosen: Array = []) -> Dictionary:
	var parent := global_pose(skel, skel.get_bone_parent(upper), poses)
	var parent_rot := parent.basis.get_rotation_quaternion()
	var shoulder := parent * skel.get_bone_rest(upper).origin
	var fore_rest := skel.get_bone_rest(fore)
	var hand_rest := skel.get_bone_rest(hand)
	var fore_rot := fore_rest.basis.get_rotation_quaternion()
	var hand_rot := hand_rest.basis.get_rotation_quaternion()
	var g_fore := skel.get_bone_global_rest(fore).basis.get_rotation_quaternion()
	var hinge := (g_fore.inverse() * Vector3.RIGHT).normalized()
	var to_wrist := target.origin - shoulder
	var dist := to_wrist.length()
	var w_dir := to_wrist / maxf(dist, 1e-6)

	# Elbow bend for the distance (the rest arm is ~10° bent: no hyperextension).
	var bend := 0.0
	var best_err := INF
	for i in 341:
		var b := deg_to_rad(-10.0 + i * 0.5)
		var err := absf(_wrist_local(fore_rest, fore_rot, hinge, hand_rest, b).length() - dist)
		if err < best_err - 1e-4:
			best_err = err
			bend = b
	var bend_rot := fore_rot * Quaternion(hinge, bend)
	var wrist_local := _wrist_local(fore_rest, fore_rot, hinge, hand_rest, bend)
	var arc := Quaternion(wrist_local.normalized(), w_dir)
	var want := target.basis.get_rotation_quaternion()

	var best := {}
	var best_cost := INF
	var best_meta: Array = []
	var steps := int(360.0 / SWING_STEP_DEG)
	for i in steps:
		var upper_global := Quaternion(w_dir, deg_to_rad(i * SWING_STEP_DEG)) * arc
		var upper_local := parent_rot.inverse() * upper_global
		var fore_global := upper_global * bend_rot
		var hand_req := fore_global.inverse() * want
		var dev := hand_req * hand_rot.inverse()
		var ideal := clampf(-_twist_angle(dev.inverse(), Vector3.UP), -twist_limit, twist_limit)
		# The roll that leaves the wrist straightest, or some of the way toward the anchors'.
		var twists := [ideal]
		for a: Array in anchors:
			for k in [0.33, 0.66, 1.0]:
				twists.append(lerpf(ideal, clampf(a[1], -twist_limit, twist_limit), k))
		var elbow := upper_global * fore_rest.origin
		var arm_cost := 0.0
		if hint != Vector3.ZERO:
			var off := elbow - w_dir * elbow.dot(w_dir)
			if off.length() > 1e-4:
				arm_cost += HINT_WEIGHT * (1.0 - off.normalized().dot(hint))
		var elbow_at := shoulder + elbow
		for o: Array in obstacles:
			var r: float = o[2]
			arm_cost += CLEARANCE_WEIGHT * (maxf(radii.x + r - segment_distance(shoulder, elbow_at, o[0], o[1]), 0.0)
					+ maxf(radii.y + r - segment_distance(elbow_at, target.origin, o[0], o[1]), 0.0))
		for a: Array in anchors:
			arm_cost += a[2] * UPPER_CONTINUITY * rad_to_deg((a[0] as Quaternion).angle_to(upper_local))
		for twist: float in twists:
			var twist_rot := Quaternion(Vector3.UP, twist)
			var hand_local := twist_rot.inverse() * hand_req
			var cost := arm_cost + rad_to_deg((hand_local * hand_rot.inverse()).get_angle()) + 0.05 * rad_to_deg(absf(twist))
			for a: Array in anchors:
				cost += a[2] * TWIST_CONTINUITY * rad_to_deg(absf(twist - a[1]))
			if cost < best_cost:
				best_cost = cost
				best = {upper: upper_local, fore: bend_rot * twist_rot, hand: hand_local}
				best_meta = [upper_local, twist]
	if not best_meta.is_empty():
		chosen.clear()
		chosen.append_array(best_meta)
	return best


## Closest distance between segments p1–q1 and p2–q2.
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
	return pts[0].distance_to(pts[1])


## Skeleton-space transform of `bone` with the given local pose rotations (rest elsewhere).
static func global_pose(skel: Skeleton3D, bone: int, poses: Dictionary) -> Transform3D:
	if bone < 0:
		return Transform3D.IDENTITY
	var rest := skel.get_bone_rest(bone)
	var rot: Quaternion = poses.get(bone, rest.basis.get_rotation_quaternion())
	return global_pose(skel, skel.get_bone_parent(bone), poses) * Transform3D(Basis(rot), rest.origin)


static func _rest_rot(skel: Skeleton3D, bone: int) -> Quaternion:
	return skel.get_bone_rest(bone).basis.get_rotation_quaternion()


## The hand bone's head in the upper arm's frame with the elbow bent by `bend`.
static func _wrist_local(fore_rest: Transform3D, fore_rot: Quaternion, hinge: Vector3,
		hand_rest: Transform3D, bend: float) -> Vector3:
	return fore_rest.origin + (fore_rot * Quaternion(hinge, bend)) * hand_rest.origin


## Signed angle of the twist part of `q` about `axis` (q = swing · twist).
static func _twist_angle(q: Quaternion, axis: Vector3) -> float:
	var v := Vector3(q.x, q.y, q.z)
	return wrapf(2.0 * atan2(v.dot(axis), q.w), -PI, PI)
