class_name EquipmentDrawModifier
extends SkeletonModifier3D

## Poses the arm (and the lean) while MsLoadout draws or stows a piece of equipment: a
## spline through the bones' rotations (Catmull-Rom, through every key), from the live
## pose (whatever animation, AMBAC and aim made this frame) through the motion's keys to
## the grab, and from the grab back to the live pose. Runs after WeaponAimModifier, before the limb followers and
## LimbReaction (which measures the motion and pushes the body back). Created by MsLoadout.

var loadout: MsLoadout


func _enter_tree() -> void:
	var skel := get_parent()
	if skel != null and not skel.child_order_changed.is_connected(_keep_after_aim):
		skel.child_order_changed.connect(_keep_after_aim)


## Right after the weapon aim (the live pose it blends from includes the aim).
func _keep_after_aim() -> void:
	var skel := get_parent()
	if skel == null:
		return
	for child in skel.get_children():
		if child is WeaponAimModifier and child.get_index() > get_index():
			skel.move_child.call_deferred(self, child.get_index())
			return


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or loadout == null:
		return
	for eq in loadout.equipment:
		var p := eq.draw_progress
		if eq.draw_motion == null or p <= 0.0 or p >= 2.0:
			continue
		_swing_hatch(skel, eq.draw_motion, p)
		var keys: Array = loadout.get_draw_keys(eq)
		if keys.is_empty():
			continue
		var reach_count := eq.draw_motion.reach_keys.size()
		var stow: Dictionary = keys[reach_count]
		var path: Array = []
		var t := 0.0
		if p < 1.0:
			# Live → reach keys → grab.
			path = keys.slice(0, reach_count)
			path.append(stow)
			# With a stow arm the hand moves over its own share of the reach (and waits).
			var m := eq.draw_motion
			var start := m.hand_start if not m.present_keys.is_empty() else 0.0
			var end := m.hand_end if not m.present_keys.is_empty() else 1.0
			t = _ease((p - start) / maxf(end - start, 0.01))
		else:
			path = [stow]
			path.append_array(keys.slice(reach_count + 1))
			t = _ease(p - 1.0)
		for bone: int in stow:
			var points: Array[Quaternion] = []
			var live := skel.get_bone_pose_rotation(bone)
			if p < 1.0:
				points.append(live)
			for key: Dictionary in path:
				points.append(key[bone])
			if p >= 1.0:
				points.append(live)
			skel.set_bone_pose_rotation(bone, _spline(points, t))


## The stow arm's hatch door, open as far as the motion says for progress `p`: turned
## about its hinge (its bone's head), bottom out.
func _swing_hatch(skel: Skeleton3D, m: MsDrawMotion, p: float) -> void:
	var open := m.get_hatch_open(p)
	var bone := skel.find_bone(m.hatch_bone) if m.hatch_bone != &"" else -1
	if open <= 0.0 or bone < 0:
		return
	var hinge := (loadout.skel_from_body().basis * m.hatch_hinge).normalized()
	var q := Quaternion(hinge, -deg_to_rad(m.hatch_open_deg) * open)
	var g := skel.get_bone_global_rest(bone).basis.get_rotation_quaternion()
	skel.set_bone_pose_rotation(bone, skel.get_bone_pose_rotation(bone) * (g.inverse() * q * g))


## Smootherstep: the arm starts and stops with no jolt.
static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## Through every point, evenly spaced in t.
static func _spline(points: Array[Quaternion], t: float) -> Quaternion:
	var pts := points.duplicate()
	for i in pts.size() - 1:
		if pts[i + 1].dot(pts[i]) < 0.0:
			pts[i + 1] = -pts[i + 1]
	var n := pts.size() - 1
	if n <= 0:
		return pts[0]
	var x := clampf(t, 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	var u := x - i
	var a: Quaternion = pts[i]
	var b: Quaternion = pts[i + 1]
	var pre: Quaternion = pts[i - 1] if i > 0 else a
	var post: Quaternion = pts[i + 2] if i + 2 <= n else b
	return a.spherical_cubic_interpolate(b, pre, post, u).normalized()
