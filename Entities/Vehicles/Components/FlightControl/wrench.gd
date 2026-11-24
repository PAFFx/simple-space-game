class_name Wrench
extends RefCounted

## A force + torque pair in the body's local frame, torque taken about the centre of mass.

var force := Vector3.ZERO   ## Newtons
var torque := Vector3.ZERO  ## Newton-metres
## Optional override of the allocator's torque-vs-force priority for this demand
## (< 0 = allocator default). Low values keep force clean at the cost of rotation.
var torque_priority: float = -1.0
## Part of the torque the thrusters can give; anything beyond it is for AMBAC.
var thruster_torque_limit := Vector3.INF
## Open the pintles (burst: more thrust, lower Isp) for this demand.
var burst := false


func _init(p_force := Vector3.ZERO, p_torque := Vector3.ZERO) -> void:
	force = p_force
	torque = p_torque
