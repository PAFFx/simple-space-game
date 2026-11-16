class_name LimbFollowers
extends Node

## Moves armor parts with the limbs they cover (skirt plates with the thighs, shoulder
## armour with the arms), so a raised or swung limb doesn't cut through them. Followers can
## sum several joints on the same bone (e.g. a side plate opening with both the outward and
## fore/aft swing). Visual; thrusters on those parts ride them, so the allocator sees where
## they are.

@export var skeleton: Skeleton3D
@export var ambac: AmbacController
@export var followers: Array[LimbFollower] = []

var _sources := PackedInt32Array()


func _ready() -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	if ambac == null and vehicle != null:
		ambac = vehicle.find_component(AmbacController) as AmbacController
	if skeleton == null or ambac == null:
		push_error("LimbFollowers: skeleton or AMBAC missing")
		return
	for f in followers:
		var i := -1 if f.from_pose else ambac.find_joint(f.source_bone, f.source_axis)
		if i < 0 and not f.from_pose:
			push_warning("LimbFollowers: no AMBAC joint %s %s" % [f.source_bone, f.source_axis])
		_sources.append(i)
	var modifier := LimbFollowerModifier.new()
	modifier.name = "LimbFollowerModifier"
	modifier.followers = self
	skeleton.add_child(modifier)


## Skeleton-space rotation per bone right now. `skel` is mid modifier pass, so pose
## followers read the final pose of their source.
func get_bone_rotations(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for k in followers.size():
		var f := followers[k]
		var a := 0.0
		if f.from_pose:
			a = pose_swing(skel, f.source_bone, f.source_axis)
		elif _sources[k] >= 0:
			a = ambac.angles[_sources[k]]
		else:
			continue
		if f.ease_in_deg != Vector2.ZERO:
			a *= smoothstep(deg_to_rad(f.ease_in_deg.x), deg_to_rad(f.ease_in_deg.y), absf(a))
		var angle := clampf(a * (f.positive if a > 0.0 else f.negative),
				deg_to_rad(f.min_angle_deg), deg_to_rad(f.max_angle_deg))
		var q := Quaternion(f.axis.normalized(), angle)
		out[f.bone_name] = (out[f.bone_name] as Quaternion) * q if out.has(f.bone_name) else q
	return out


## A limb's swing from rest, rad, in its parent's frame (skeleton axes at rest): about
## RIGHT = fore/aft (+ forward, for a hanging limb), about BACK = sideways (+ toward +X).
static func pose_swing(skel: Skeleton3D, bone_name: StringName, axis: Vector3) -> float:
	var bone := skel.find_bone(bone_name)
	if bone < 0:
		return 0.0
	var parent := skel.get_bone_parent(bone)
	var to_rest := Basis.IDENTITY
	if parent >= 0:
		to_rest = skel.get_bone_global_rest(parent).basis.orthonormalized() \
				* skel.get_bone_global_pose(parent).basis.orthonormalized().inverse()
	var now := (to_rest * skel.get_bone_global_pose(bone).basis.y).normalized()
	var rest := skel.get_bone_global_rest(bone).basis.y.normalized()
	if axis.abs().is_equal_approx(Vector3.RIGHT):
		# −Y (hanging) swings toward −Z (forward).
		return atan2(-now.z, -now.y) - atan2(-rest.z, -rest.y)
	return asin(clampf(now.x, -1.0, 1.0)) - asin(clampf(rest.x, -1.0, 1.0))
