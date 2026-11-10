class_name AmbacController
extends Node

## AMBAC (Active Mass Balance Auto Control): swings limbs to produce reaction
## torque on the body, so attitude can be trimmed without propellant.
##
## Each tick the FlightComputer hands it a torque request (a `share` of the FBW
## demand). Joint accelerations are found by weighted least squares
## (priority × headroom, occupied groups get no weight), then a centering
## spring pulls every limb back to neutral. Limbs can't make sustained torque,
## so the returned *achieved* torque is subtracted from what the thrusters must give.

@export var enabled: bool = true
@export var skeleton: Skeleton3D
@export var joints: Array[AmbacJoint] = []
## Fraction of the FBW torque demand offered to AMBAC first.
@export_range(0.0, 1.0) var share: float = 0.3
## Centering spring natural frequency (rad/s) and damping ratio.
@export var centering_frequency: float = 1.6
@export var centering_damping: float = 1.0
## Regularisation of the allocation (keeps it sane when no joint can help).
@export var regularization: float = 1e-3

var angles := PackedFloat32Array()   ## rad
var rates := PackedFloat32Array()    ## rad/s
var last_torque := Vector3.ZERO      ## Achieved body torque, body frame
var _loadout: MsLoadout
var _axes_body: Array[Vector3] = []


func _ready() -> void:
	angles.resize(joints.size())
	rates.resize(joints.size())
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_loadout = vehicle.find_component(MsLoadout) as MsLoadout
	if skeleton == null:
		push_error("AmbacController: skeleton not assigned")
		return
	var body_from_skel := vehicle.global_basis.inverse() * skeleton.global_basis if vehicle \
			else Basis.IDENTITY
	for j in joints:
		_axes_body.append((body_from_skel * j.axis).normalized())
	var modifier := AmbacModifier.new()
	modifier.name = "AmbacModifier"
	modifier.controller = self
	skeleton.add_child(modifier)


func is_joint_available(i: int) -> bool:
	var j := joints[i]
	return enabled and j.priority > 0.0 and \
			(_loadout == null or j.group == &"" or not _loadout.is_group_occupied(j.group))


## Average |angle| / limit over all joints, 0..1 (HUD).
func get_usage() -> float:
	if joints.is_empty():
		return 0.0
	var sum := 0.0
	for i in joints.size():
		sum += absf(angles[i]) / deg_to_rad(joints[i].max_angle_deg)
	return sum / joints.size()


## Advances the limbs and returns the achieved reaction torque (body frame).
func step(torque_request: Vector3, delta: float) -> Vector3:
	var n := joints.size()
	if n == 0 or _axes_body.size() != n or delta <= 0.0:
		last_torque = Vector3.ZERO
		return last_torque

	var weights := PackedFloat32Array()
	weights.resize(n)
	# M = Σ w J² a aᵀ + εI, accumulated as columns (Basis has no +).
	var reg := regularization * _scale()
	var cols: Array[Vector3] = [Vector3(reg, 0, 0), Vector3(0, reg, 0), Vector3(0, 0, reg)]
	for i in n:
		var w := joints[i].priority if is_joint_available(i) else 0.0
		weights[i] = w
		var ja := _axes_body[i] * joints[i].inertia
		for k in 3:
			cols[k] += ja * ja[k] * w
	# Solve Σ −J α a = request:  α_i = −w_i J_i a_i·λ,  M λ = request.
	var lam := Basis(cols[0], cols[1], cols[2]).inverse() * torque_request

	var w0 := centering_frequency
	var total := Vector3.ZERO
	for i in n:
		var j := joints[i]
		var limit := deg_to_rad(j.max_angle_deg)
		var alpha := -weights[i] * j.inertia * _axes_body[i].dot(lam)
		# Back off as the limb approaches its stop in the direction it's being pushed.
		if signf(alpha) == signf(angles[i]):
			alpha *= clampf(1.0 - absf(angles[i]) / limit, 0.0, 1.0)
		alpha += -w0 * w0 * angles[i] - 2.0 * centering_damping * w0 * rates[i]
		var max_accel := deg_to_rad(j.max_accel_deg)
		alpha = clampf(alpha, -max_accel, max_accel)

		var max_rate := deg_to_rad(j.max_rate_deg)
		var new_rate := clampf(rates[i] + alpha * delta, -max_rate, max_rate)
		var new_angle := angles[i] + new_rate * delta
		if absf(new_angle) > limit:
			new_angle = clampf(new_angle, -limit, limit)
			new_rate = 0.0
		var actual_alpha := (new_rate - rates[i]) / delta
		rates[i] = new_rate
		angles[i] = new_angle
		total += -_axes_body[i] * j.inertia * actual_alpha
	last_torque = total
	return total


## Skeleton-space rotation currently applied to each bone (used by AmbacModifier).
func get_bone_rotations() -> Dictionary:
	var out := {}
	for i in joints.size():
		var j := joints[i]
		var q := Quaternion(j.axis.normalized(), angles[i])
		out[j.bone_name] = (out[j.bone_name] as Quaternion) * q if out.has(j.bone_name) else q
	return out


func _scale() -> float:
	var s := 0.0
	for j in joints:
		s = maxf(s, j.inertia * j.inertia)
	return maxf(s, 1.0)
