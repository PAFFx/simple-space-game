#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

// The flight computer's and sensors' hot loops, in C++. Each is the GDScript it replaces
// (named in the comment) with the same operations in the same order, so the results are
// bit-identical; the GDScript stays as the fallback (FlightNative).
class FlightKernels : public RefCounted {
	GDCLASS(FlightKernels, RefCounted)

protected:
	static void _bind_methods();

public:
	// ConeProjectedAllocator._solve: FISTA on u toward a target wrench; returns the new u.
	PackedVector3Array allocator_solve(PackedVector3Array p_u, const PackedVector3Array &p_positions,
			const PackedFloat32Array &p_max, const PackedVector3Array &p_axes, const PackedFloat32Array &p_cones,
			const PackedVector3Array &p_planes, int p_planes_per, const Vector3 &p_force_target,
			const Vector3 &p_torque_target, int p_count, double p_step, double p_wf2, const Vector3 &p_wt2,
			double p_lam, double p_price) const;
	// ConeProjectedAllocator._wrench_of: [force, torque] of u.
	PackedVector3Array allocator_wrench_of(const PackedVector3Array &p_u, const PackedVector3Array &p_positions,
			const PackedFloat32Array &p_max) const;
	// ConeProjectedAllocator.trim's FISTA loop on the throttles (x already clamped).
	PackedFloat32Array allocator_trim(PackedFloat32Array p_x, const PackedFloat32Array &p_lo,
			const PackedFloat32Array &p_hi, const PackedVector3Array &p_fcol, const PackedVector3Array &p_tcol,
			const Vector3 &p_f_dir, double p_side, double p_wf2, const Vector3 &p_wt2, const Vector3 &p_force,
			const Vector3 &p_torque, double p_step, int p_iterations) const;
	// SensorTrack._predict: x (9) and P (81) over dt; returns x then P (90 values).
	PackedFloat64Array track_predict(const PackedFloat64Array &p_x, const PackedFloat64Array &p_p, double p_dt,
			double p_maneuver_time, double p_sigma) const;
	// SensorTrack.add_measurement's gain and update (and _symmetrize); returns x then P.
	PackedFloat64Array track_update(const PackedFloat64Array &p_x, const PackedFloat64Array &p_p,
			const Vector3 &p_y, const Basis &p_s_inv) const;
	// ForceCapabilityMap.lookup's blend over the samples.
	double capability_lookup(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_values,
			double p_floor, const Vector3 &p_dir) const;
};

} // namespace godot
