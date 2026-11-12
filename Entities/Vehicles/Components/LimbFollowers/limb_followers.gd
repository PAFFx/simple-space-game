class_name LimbFollowers
extends Node

## Moves armor parts with the limbs they cover (skirt plates with the thighs), so a
## raised or swung leg doesn't cut through them. Followers can sum several joints on
## the same bone (e.g. a side plate opening with both the outward and fore/aft swing).
## Visual; thrusters on those parts ride them, so the allocator sees where they are.

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
		var i := ambac.find_joint(f.source_bone, f.source_axis)
		if i < 0:
			push_warning("LimbFollowers: no AMBAC joint %s %s" % [f.source_bone, f.source_axis])
		_sources.append(i)
	var modifier := LimbFollowerModifier.new()
	modifier.name = "LimbFollowerModifier"
	modifier.followers = self
	skeleton.add_child(modifier)


## Skeleton-space rotation per bone right now.
func get_bone_rotations() -> Dictionary:
	var out := {}
	for k in followers.size():
		var i := _sources[k]
		if i < 0:
			continue
		var f := followers[k]
		var a := ambac.angles[i]
		var angle := clampf(a * (f.positive if a > 0.0 else f.negative),
				deg_to_rad(f.min_angle_deg), deg_to_rad(f.max_angle_deg))
		var q := Quaternion(f.axis.normalized(), angle)
		out[f.bone_name] = (out[f.bone_name] as Quaternion) * q if out.has(f.bone_name) else q
	return out
