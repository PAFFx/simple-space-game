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

## Seconds a held part takes to settle back to rest (hold_bone).
@export var hold_time: float = 0.3

var _sources := PackedInt32Array()
var _hold := {}         ## bone → [held now 0..1, wanted]


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


## Holds a part at rest (eased over hold_time), e.g. the skirt a weapon is drawn from.
func hold_bone(bone_name: StringName, on: bool) -> void:
	if _hold.has(bone_name):
		_hold[bone_name][1] = on
	elif on:
		_hold[bone_name] = [0.0, true]


func _process(delta: float) -> void:
	for bone: StringName in _hold.keys():
		var h: Array = _hold[bone]
		h[0] = move_toward(h[0], 1.0 if h[1] else 0.0, delta / maxf(hold_time, 0.01))
		if h[0] <= 0.0 and not h[1]:
			_hold.erase(bone)


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
		if f.ease_in_deg != Vector2.ZERO and (a > 0.0 or not f.ease_in_positive_only):
			a *= smoothstep(deg_to_rad(f.ease_in_deg.x), deg_to_rad(f.ease_in_deg.y), absf(a))
		var angle := clampf(a * (f.positive if a > 0.0 else f.negative),
				deg_to_rad(f.min_angle_deg), deg_to_rad(f.max_angle_deg))
		if _hold.has(f.bone_name):
			angle *= 1.0 - smoothstep(0.0, 1.0, _hold[f.bone_name][0])
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
