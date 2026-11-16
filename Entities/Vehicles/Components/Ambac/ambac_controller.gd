class_name AmbacController
extends Node

## AMBAC (Active Mass Balance Auto Control): swings limbs to produce reaction
## torque on the body, so attitude can be trimmed without propellant.
##
## Each tick the FlightComputer hands it a torque request: a `share` of the FBW
## demand plus whatever exceeds the thrusters' authority. The FBW budgets for that
## extra (get_capacity()), so limbs make the suit turn, stop and swing faster, not
## just save propellant. Joint accelerations are found by weighted least squares
## (priority × headroom, occupied groups get no weight), then a centering spring
## pulls every limb back to its target: neutral (0), or a stance pose set by a
## StanceController through set_target(), whose motion is fed forward so the limb
## follows it exactly. Moving a limb pushes the body back either way, and limbs can't
## make sustained torque, so the returned *achieved* torque is subtracted from what
## the thrusters must give.
##
## Locked groups (lock_group(), or occupied by active equipment) take no part in
## balancing; their joints just hold their target.

@export var enabled: bool = true
@export var skeleton: Skeleton3D
@export var joints: Array[AmbacJoint] = []
## Fraction of the FBW torque demand offered to AMBAC first (on top of any demand
## beyond the thrusters' authority, which AMBAC always gets).
@export_range(0.0, 1.0) var share: float = 0.4
## Share of the limbs' peak torque the FBW may count on (they lose authority near
## their stops and while the centering spring pulls them home).
@export_range(0.0, 1.0) var capacity_fraction: float = 0.25
## Centering spring natural frequency (rad/s) and damping ratio.
@export var centering_frequency: float = 1.6
@export var centering_damping: float = 1.0
## Regularisation of the allocation (keeps it sane when no joint can help).
@export var regularization: float = 1e-3

var angles := PackedFloat32Array()   ## rad
var rates := PackedFloat32Array()    ## rad/s
var targets := PackedFloat32Array()  ## Pose each joint is held at, rad (0 = neutral)
var target_rates := PackedFloat32Array()
var target_accels := PackedFloat32Array()
var _locked := {}                    ## Group → true: hard-locked (no balancing)
var last_torque := Vector3.ZERO      ## Achieved body torque, body frame
## Part of last_torque from measured joints: LimbReaction applies their real reaction.
var last_measured_torque := Vector3.ZERO
var _measured := PackedByteArray()
var _loadout: MsLoadout
var _axes_body: Array[Vector3] = []


func _ready() -> void:
	angles.resize(joints.size())
	rates.resize(joints.size())
	targets.resize(joints.size())
	target_rates.resize(joints.size())
	target_accels.resize(joints.size())
	_measured.resize(joints.size())
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
	return enabled and j.priority > 0.0 and not is_group_locked(j.group)


## True while a group takes no part in balancing (hard-locked, or its equipment is in use).
func is_group_locked(group: StringName) -> bool:
	if group == &"":
		return false
	return _locked.has(group) or (_loadout != null and _loadout.is_group_occupied(group))


## Holds a group at its targets and keeps it out of balancing (e.g. a limb in use).
func lock_group(group: StringName) -> void:
	_locked[group] = true


func unlock_group(group: StringName) -> void:
	_locked.erase(group)


## Index of the joint on `bone` about `axis` (skeleton space), or -1.
func find_joint(bone: StringName, axis: Vector3) -> int:
	for i in joints.size():
		if joints[i].bone_name == bone and joints[i].axis.normalized().dot(axis.normalized()) > 0.99:
			return i
	return -1


## Joint i's limb is tracked by LimbReaction, which applies its real reaction torque;
## AMBAC plans with `inertia` (from the same mass model) but doesn't apply it itself.
func set_measured(i: int, inertia: float) -> void:
	_measured[i] = 1
	if inertia > 0.0:
		joints[i].inertia = inertia


## Pose target for joint i: angle (rad) plus its rate and acceleration, fed forward so
## the limb follows a moving target without lag.
func set_target(i: int, angle: float, rate := 0.0, accel := 0.0) -> void:
	var j := joints[i]
	targets[i] = clampf(angle, deg_to_rad(j.min_angle_deg), deg_to_rad(j.max_angle_deg))
	target_rates[i] = rate
	target_accels[i] = accel


## Torque the free limbs can add right now, per body axis (N·m): each available
## joint's peak reaction torque, scaled by its remaining travel.
func get_capacity() -> Vector3:
	var out := Vector3.ZERO
	if not enabled or _axes_body.size() != joints.size():
		return out
	for i in joints.size():
		if not is_joint_available(i):
			continue
		var j := joints[i]
		var half := deg_to_rad(maxf(j.max_angle_deg - j.min_angle_deg, 1e-3)) * 0.5
		var mid := deg_to_rad(j.max_angle_deg + j.min_angle_deg) * 0.5
		var headroom := clampf(1.0 - absf(angles[i] - mid) / half, 0.0, 1.0)
		out += _axes_body[i].abs() * (j.inertia * j.get_max_accel() * headroom)
	return out * capacity_fraction


## Average angle / limit (in the direction it's deflected) over all joints, 0..1 (HUD).
func get_usage() -> float:
	if joints.is_empty():
		return 0.0
	var sum := 0.0
	for i in joints.size():
		var limit := joints[i].max_angle_deg if angles[i] >= 0.0 else -joints[i].min_angle_deg
		sum += absf(angles[i]) / maxf(deg_to_rad(limit), 1e-4)
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
	var measured := Vector3.ZERO
	for i in n:
		var j := joints[i]
		var lo := deg_to_rad(minf(j.min_angle_deg, 0.0))
		var hi := deg_to_rad(maxf(j.max_angle_deg, 0.0))
		var alpha := -weights[i] * j.inertia * _axes_body[i].dot(lam)
		# Back off as the limb approaches its stop in the direction it's being pushed.
		if alpha > 0.0:
			alpha *= clampf((hi - angles[i]) / maxf(hi, 1e-4), 0.0, 1.0)
		elif alpha < 0.0:
			alpha *= clampf((angles[i] - lo) / maxf(-lo, 1e-4), 0.0, 1.0)
		alpha += target_accels[i] - w0 * w0 * (angles[i] - targets[i]) \
				- 2.0 * centering_damping * w0 * (rates[i] - target_rates[i])
		var max_accel := j.get_max_accel()
		alpha = clampf(alpha, -max_accel, max_accel)

		var max_rate := deg_to_rad(j.max_rate_deg)
		var new_rate := clampf(rates[i] + alpha * delta, -max_rate, max_rate)
		var new_angle := angles[i] + new_rate * delta
		if new_angle > hi or new_angle < lo:
			new_angle = clampf(new_angle, lo, hi)
			new_rate = 0.0
		var actual_alpha := (new_rate - rates[i]) / delta
		rates[i] = new_rate
		angles[i] = new_angle
		var reaction := -_axes_body[i] * j.inertia * actual_alpha
		total += reaction
		if _measured[i]:
			measured += reaction
	last_torque = total
	last_measured_torque = measured
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
