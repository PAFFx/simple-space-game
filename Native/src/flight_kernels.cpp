#include "flight_kernels.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>
#include <vector>

using namespace godot;

// Same arithmetic, in the same order, as the GDScript each function replaces: a float
// read from a PackedFloat32Array widens to double as in GDScript, and one stored into it
// rounds back to float, as there. MAX / CLAMP are the engine's (GDScript's maxf / clampf).

PackedVector3Array FlightKernels::allocator_solve(PackedVector3Array p_u, const PackedVector3Array &p_positions,
		const PackedFloat32Array &p_max, const PackedVector3Array &p_axes, const PackedFloat32Array &p_cones,
		const PackedVector3Array &p_planes, int p_planes_per, const Vector3 &p_force_target,
		const Vector3 &p_torque_target, int p_count, double p_step, double p_wf2, const Vector3 &p_wt2,
		double p_lam, double p_price) const {
	const int64_t n = p_u.size();
	const Vector3 *r = p_positions.ptr();
	const float *t = p_max.ptr();
	const Vector3 *axes = p_axes.ptr();
	const Vector3 *planes = p_planes.ptr();
	const int64_t planes_size = p_planes.size();
	std::vector<double> tan_c(n), cos_c(n), sin_c(n), damping(n), shrink(n);
	for (int64_t i = 0; i < n; i++) {
		const double cone = p_cones[i];
		tan_c[i] = std::tan(cone);
		cos_c[i] = std::cos(cone);
		sin_c[i] = std::sin(cone);
		const double ti = t[i];
		damping[i] = 2.0 * p_lam * ti * ti;
		shrink[i] = p_step * p_price * ti;
	}
	Vector3 *u = p_u.ptrw();
	std::vector<Vector3> y(u, u + n);
	double momentum = 1.0;
	for (int k = 0; k < p_count; k++) {
		Vector3 force;
		Vector3 torque;
		for (int64_t i = 0; i < n; i++) {
			const Vector3 f = y[i] * (double)t[i];
			force += f;
			torque += r[i].cross(f);
		}
		const Vector3 g_force = (force - p_force_target) * (2.0 * p_wf2);
		const Vector3 g_torque = (torque - p_torque_target) * p_wt2 * 2.0;

		const double next_momentum = (1.0 + std::sqrt(1.0 + 4.0 * momentum * momentum)) * 0.5;
		const double beta = (momentum - 1.0) / next_momentum;
		for (int64_t i = 0; i < n; i++) {
			const double ti = t[i];
			if (ti <= 0.0) {
				u[i] = Vector3();
				y[i] = Vector3();
				continue;
			}
			const Vector3 yi = y[i];
			const Vector3 grad = (g_force + g_torque.cross(r[i])) * ti + yi * damping[i];
			const Vector3 w = yi - grad * p_step;
			// Onto the gimbal cone (project_to_cone)...
			const Vector3 axis = axes[i];
			const double a = w.dot(axis);
			const Vector3 perp = w - axis * a;
			const double s = perp.length();
			Vector3 v;
			if (s <= a * tan_c[i]) {
				v = w;
			} else if (s * tan_c[i] <= -a) {
				v = Vector3();
			} else if (s < 1e-9) {
				v = axis * MAX(a, 0.0);
			} else {
				const Vector3 edge = axis * cos_c[i] + perp / s * sin_c[i];
				v = edge * (a * cos_c[i] + s * sin_c[i]);
			}
			const double v_len = v.length();
			if (v_len > 1.0) {
				v = v / v_len;
			}
			// ...then inside its swing-limit planes.
			if (planes_size >= p_planes_per * (i + 1)) {
				for (int kk = 0; kk < p_planes_per; kk++) {
					const Vector3 m = planes[p_planes_per * i + kk];
					const double over = m.dot(v);
					if (over > 0.0) {
						v -= m * over;
					}
				}
			}
			const double sh = shrink[i];
			if (sh > 0.0) {
				const double length = v.length();
				v = length > 1e-12 ? v * (MAX(length - sh, 0.0) / length) : Vector3();
			}
			y[i] = v + (v - u[i]) * beta;
			u[i] = v;
		}
		momentum = next_momentum;
	}
	return p_u;
}

PackedVector3Array FlightKernels::allocator_wrench_of(const PackedVector3Array &p_u,
		const PackedVector3Array &p_positions, const PackedFloat32Array &p_max) const {
	Vector3 force;
	Vector3 torque;
	const int64_t n = p_u.size();
	for (int64_t i = 0; i < n; i++) {
		const Vector3 f = p_u[i] * (double)p_max[i];
		force += f;
		torque += p_positions[i].cross(f);
	}
	PackedVector3Array out;
	out.push_back(force);
	out.push_back(torque);
	return out;
}

PackedFloat32Array FlightKernels::allocator_trim(PackedFloat32Array p_x, const PackedFloat32Array &p_lo,
		const PackedFloat32Array &p_hi, const PackedVector3Array &p_fcol, const PackedVector3Array &p_tcol,
		const Vector3 &p_f_dir, double p_side, double p_wf2, const Vector3 &p_wt2, const Vector3 &p_force,
		const Vector3 &p_torque, double p_step, int p_iterations) const {
	const int64_t n = p_x.size();
	const Vector3 *fcol = p_fcol.ptr();
	const Vector3 *tcol = p_tcol.ptr();
	const float *lo = p_lo.ptr();
	const float *hi = p_hi.ptr();
	float *x = p_x.ptrw();
	std::vector<float> y(x, x + n);
	double momentum = 1.0;
	for (int k = 0; k < p_iterations; k++) {
		Vector3 force;
		Vector3 torque;
		for (int64_t i = 0; i < n; i++) {
			force += fcol[i] * (double)y[i];
			torque += tcol[i] * (double)y[i];
		}
		const Vector3 e = force - p_force;
		const Vector3 along = p_f_dir * e.dot(p_f_dir);
		const Vector3 g_force = (along + (e - along) * p_side) * (2.0 * p_wf2);
		const Vector3 g_torque = (torque - p_torque) * p_wt2 * 2.0;
		const double next_momentum = (1.0 + std::sqrt(1.0 + 4.0 * momentum * momentum)) * 0.5;
		const double beta = (momentum - 1.0) / next_momentum;
		for (int64_t i = 0; i < n; i++) {
			const double x_new = CLAMP((double)y[i] - p_step * (g_force.dot(fcol[i]) + g_torque.dot(tcol[i])),
					(double)lo[i], (double)hi[i]);
			y[i] = (float)(x_new + (x_new - (double)x[i]) * beta);
			x[i] = (float)x_new;
		}
		momentum = next_momentum;
	}
	return p_x;
}

static constexpr int N = 9;

PackedFloat64Array FlightKernels::track_predict(const PackedFloat64Array &p_x, const PackedFloat64Array &p_p,
		double p_dt, double p_maneuver_time, double p_sigma) const {
	PackedFloat64Array out;
	out.resize(N + N * N);
	double *x = out.ptrw();
	double *p_new = x + N;
	const double *xi = p_x.ptr();
	const double *p = p_p.ptr();
	for (int i = 0; i < N; i++) {
		x[i] = xi[i];
	}
	if (p_dt <= 0.0) {
		for (int i = 0; i < N * N; i++) {
			p_new[i] = p[i];
		}
		return out;
	}
	const double b = 1.0 / p_maneuver_time;
	const double e = std::exp(-b * p_dt);
	const double f[9] = { 1.0, p_dt, (b * p_dt - 1.0 + e) / (b * b), 0.0, 1.0, (1.0 - e) / b, 0.0, 0.0, e };
	const double q = 2.0 * b * p_sigma * p_sigma;
	const double t2 = p_dt * p_dt;
	const double t3 = t2 * p_dt;
	const double qm[9] = { t3 * t2 / 20.0, t2 * t2 / 8.0, t3 / 6.0, t2 * t2 / 8.0, t3 / 3.0, t2 / 2.0,
		t3 / 6.0, t2 / 2.0, p_dt };
	for (int a = 0; a < 3; a++) {
		const int o = a * 3;
		const double x0 = x[o];
		const double x1 = x[o + 1];
		const double x2 = x[o + 2];
		x[o] = f[0] * x0 + f[1] * x1 + f[2] * x2;
		x[o + 1] = f[4] * x1 + f[5] * x2;
		x[o + 2] = f[8] * x2;
	}
	for (int ba = 0; ba < 3; ba++) {
		for (int bb = 0; bb < 3; bb++) {
			const int r0 = (ba * 3) * N + bb * 3;
			const int r1 = r0 + N;
			const int r2 = r1 + N;
			const double b0 = p[r0], b1 = p[r0 + 1], b2 = p[r0 + 2];
			const double b3 = p[r1], b4 = p[r1 + 1], b5 = p[r1 + 2];
			const double b6 = p[r2], b7 = p[r2 + 1], b8 = p[r2 + 2];
			for (int i = 0; i < 3; i++) {
				const double fi0 = f[i * 3], fi1 = f[i * 3 + 1], fi2 = f[i * 3 + 2];
				for (int j = 0; j < 3; j++) {
					const double fj0 = f[j * 3], fj1 = f[j * 3 + 1], fj2 = f[j * 3 + 2];
					double sum = 0.0 + fi0 * b0 * fj0 + fi0 * b1 * fj1 + fi0 * b2 * fj2
							+ fi1 * b3 * fj0 + fi1 * b4 * fj1 + fi1 * b5 * fj2
							+ fi2 * b6 * fj0 + fi2 * b7 * fj1 + fi2 * b8 * fj2;
					if (ba == bb) {
						sum += q * qm[i * 3 + j];
					}
					p_new[(ba * 3 + i) * N + bb * 3 + j] = sum;
				}
			}
		}
	}
	return out;
}

PackedFloat64Array FlightKernels::track_update(const PackedFloat64Array &p_x, const PackedFloat64Array &p_p,
		const Vector3 &p_y, const Basis &p_s_inv) const {
	const double *p = p_p.ptr();
	PackedFloat64Array out;
	out.resize(N + N * N);
	double *x = out.ptrw();
	double *p_new = x + N;
	const double *xi = p_x.ptr();
	for (int i = 0; i < N; i++) {
		x[i] = xi[i];
	}
	// K = P Hᵀ S⁻¹ (H picks the positions), x += K y, P −= K H P.
	double ph[N * 3];
	for (int r = 0; r < N; r++) {
		for (int c = 0; c < 3; c++) {
			ph[r * 3 + c] = p[r * N + c * 3];
		}
	}
	const Basis st = p_s_inv.transposed();
	double k[N * 3];
	for (int r = 0; r < N; r++) {
		const Vector3 row(ph[r * 3], ph[r * 3 + 1], ph[r * 3 + 2]);
		const Vector3 kr = st.xform(row);   // row · S⁻¹ (S symmetric)
		k[r * 3] = kr.x;
		k[r * 3 + 1] = kr.y;
		k[r * 3 + 2] = kr.z;
	}
	for (int r = 0; r < N; r++) {
		x[r] += k[r * 3] * p_y.x + k[r * 3 + 1] * p_y.y + k[r * 3 + 2] * p_y.z;
	}
	for (int i = 0; i < N * N; i++) {
		p_new[i] = p[i];
	}
	for (int r = 0; r < N; r++) {
		const double k0 = k[r * 3];
		const double k1 = k[r * 3 + 1];
		const double k2 = k[r * 3 + 2];
		for (int c = 0; c < N; c++) {
			p_new[r * N + c] -= k0 * p[c] + k1 * p[3 * N + c] + k2 * p[6 * N + c];
		}
	}
	// _symmetrize
	for (int r = 0; r < N; r++) {
		for (int c = r + 1; c < N; c++) {
			const double v = 0.5 * (p_new[r * N + c] + p_new[c * N + r]);
			p_new[r * N + c] = v;
			p_new[c * N + r] = v;
		}
	}
	return out;
}

double FlightKernels::capability_lookup(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_values,
		double p_floor, const Vector3 &p_dir) const {
	double inv_sum = 0.0;
	double weight = 0.0;
	const int64_t n = p_dirs.size();
	const Vector3 *dirs = p_dirs.ptr();
	const float *values = p_values.ptr();
	for (int64_t i = 0; i < n; i++) {
		const double d = dirs[i].dot(p_dir);
		if (d <= 0.0) {
			continue;
		}
		const double w = std::pow(d, 8.0);   // ForceCapabilityMap.SHARPNESS
		inv_sum += w / MAX((double)values[i], p_floor);
		weight += w;
	}
	return inv_sum > 0.0 ? weight / inv_sum : 0.0;
}

void FlightKernels::_bind_methods() {
	ClassDB::bind_method(D_METHOD("allocator_solve", "u", "positions", "max", "axes", "cones", "planes",
								 "planes_per", "force_target", "torque_target", "count", "step", "wf2", "wt2", "lam",
								 "price"),
			&FlightKernels::allocator_solve);
	ClassDB::bind_method(D_METHOD("allocator_wrench_of", "u", "positions", "max"), &FlightKernels::allocator_wrench_of);
	ClassDB::bind_method(D_METHOD("allocator_trim", "x", "lo", "hi", "fcol", "tcol", "f_dir", "side", "wf2", "wt2",
								 "force", "torque", "step", "iterations"),
			&FlightKernels::allocator_trim);
	ClassDB::bind_method(D_METHOD("track_predict", "x", "p", "dt", "maneuver_time", "sigma"),
			&FlightKernels::track_predict);
	ClassDB::bind_method(D_METHOD("track_update", "x", "p", "y", "s_inv"), &FlightKernels::track_update);
	ClassDB::bind_method(D_METHOD("capability_lookup", "dirs", "values", "floor", "dir"),
			&FlightKernels::capability_lookup);
}
