class_name FlightState
extends RefCounted

## Snapshot of the vehicle's physical state for one physics tick, built by the
## FlightComputer and handed to the control law and thrust allocator.
## "local" values are in the body frame; thruster geometry is relative to the COM.

var delta: float = 0.0
var mass: float = 1.0
var basis := Basis.IDENTITY             ## Body orientation (global, orthonormal)
var com_position := Vector3.ZERO        ## Centre of mass (global)

## Velocities relative to the reference frame (e.g. a station), global and local.
var linear_velocity := Vector3.ZERO
var local_linear_velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var local_angular_velocity := Vector3.ZERO
var reference_velocity := Vector3.ZERO

## Inertia tensor about the COM in the body frame.
var inertia_local := Basis.IDENTITY

## Thruster geometry, one entry per thruster (body frame, relative to COM).
var thruster_positions := PackedVector3Array()
var thruster_axes := PackedVector3Array()        ## Nominal (un-gimballed) thrust direction
var thruster_cone := PackedFloat32Array()        ## Gimbal half-angle, radians
var thruster_max := PackedFloat32Array()         ## Available thrust, N (0 = unavailable)

## Rough authority estimates derived from the geometry above.
var max_force_pos := Vector3.ZERO  ## Max force along +x/+y/+z (positive numbers)
var max_force_neg := Vector3.ZERO  ## Max force along -x/-y/-z (positive numbers)
var max_torque := Vector3.ZERO     ## Max torque per axis (symmetric, conservative)

## False while the body must stay aligned with the cockpit (e.g. hatch open).
var allow_attitude_offset: bool = true

## Clean directional authority measured through the allocator (null = ellipsoid estimate).
var capability_map: ForceCapabilityMap


func to_local(global_vector: Vector3) -> Vector3:
	return basis.transposed() * global_vector


func to_global(local_vector: Vector3) -> Vector3:
	return basis * local_vector


## Force authority (N) along a unit body-frame direction. Uses the measured
## capability map when available, else an ellipsoid through the per-axis limits
## (optimistic: it counts force that only comes with side effects).
func force_capability(dir: Vector3) -> float:
	if capability_map != null:
		return capability_map.lookup(dir)
	var s := 0.0
	for k in 3:
		var limit := max_force_pos[k] if dir[k] >= 0.0 else max_force_neg[k]
		s += (dir[k] / maxf(limit, 1.0)) ** 2
	return 1.0 / sqrt(s) if s > 0.0 else 0.0


## Fills max_force_* and max_torque from the thruster geometry.
## Each thruster is assumed to aim as well as its gimbal cone allows.
func compute_authority() -> void:
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var torque_pos := Vector3.ZERO
	var torque_neg := Vector3.ZERO
	for i in thruster_axes.size():
		var d := thruster_axes[i]
		var r := thruster_positions[i]
		var t := thruster_max[i]
		var cone := thruster_cone[i]
		for k in 3:
			var a := axes[k]
			max_force_pos[k] += t * _best_alignment(d, a, cone)
			max_force_neg[k] += t * _best_alignment(d, -a, cone)
			# Torque about axis a from force u at r is u · (a × r).
			var lever := a.cross(r)
			var arm := lever.length()
			if arm > 1e-4:
				var l := lever / arm
				torque_pos[k] += t * arm * _best_alignment(d, l, cone)
				torque_neg[k] += t * arm * _best_alignment(d, -l, cone)
	for k in 3:
		max_torque[k] = minf(torque_pos[k], torque_neg[k])


static func _best_alignment(axis: Vector3, target: Vector3, cone: float) -> float:
	var angle := maxf(0.0, axis.angle_to(target) - cone)
	return maxf(0.0, cos(angle))
