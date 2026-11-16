class_name SensorTrack
extends RefCounted

## What the suit believes about one target: a Kalman filter on position, velocity and
## acceleration (world frame) with a Singer motion model, the target's acceleration a
## random process that decays over `maneuver_time` (how long a suit holds one thrust).
##
## Measurements are 3D points with a covariance (a camera's angles plus a range, see
## SensorSuite), stamped with the time they were captured. They arrive late (sensor
## latency): the filter steps to the capture time, updates, and get_estimate() predicts
## on to now, so latency becomes track lag with no special case.
##
## A measurement too far from the prediction (Mahalanobis gate) is rejected; a few in a
## row and the track breaks and starts again from the new measurement. A hard jink can
## break a track, as it can a real one.
##
##   TENTATIVE  fewer than `firm_hits` updates: no fire solution yet
##   FIRM       tracking
##   COAST      no update for `coast_after` s: predicting, uncertainty growing
##   LOST       no update for `lost_after` s

enum State { TENTATIVE, FIRM, COAST, LOST }

const N := 9   # [px vx ax py vy ay pz vz az]

var maneuver_time := 0.8         ## Singer τ, s
var maneuver_accel := 30.0       ## Singer σ, m/s² (~3 G)
var firm_hits := 4
var coast_after := 0.25
var lost_after := 1.2
var gate := 16.0                 ## Mahalanobis d², 3 dof (~99.9%)
var break_after := 3             ## Rejections in a row that restart the track

var state := State.TENTATIVE
var time := -1.0                 ## Capture time the state is at
var hits := 0
var last_update := -INF          ## Capture time of the last accepted measurement
var rejected_in_a_row := 0
var breaks := 0                  ## Times the track restarted (telemetry)

var _x := PackedFloat64Array()
var _p := PackedFloat64Array()   ## N×N, row-major


func _init() -> void:
	_x.resize(N)
	_p.resize(N * N)


func is_started() -> bool:
	return time >= 0.0


## True while the estimate is good enough to shoot from.
func has_solution() -> bool:
	return state == State.FIRM


## Takes a measurement captured at `t` (s): `pos` world, `cov` its covariance (m²).
func add_measurement(t: float, pos: Vector3, cov: Basis) -> void:
	if not is_started():
		_start(t, pos, cov)
		return
	if t < time:
		return   # older than the state (another sensor's slower pipeline): skip
	_predict(t - time)
	time = t
	var y := pos - _position()
	var s := _add_basis(_pos_cov(), cov)
	var s_inv := s.inverse()
	var d2 := y.dot(s_inv * y)
	if d2 > gate:
		rejected_in_a_row += 1
		if rejected_in_a_row >= break_after:
			breaks += 1
			_start(t, pos, cov)
		return
	rejected_in_a_row = 0
	# K = P Hᵀ S⁻¹ (H picks the positions), x += K y, P −= K H P.
	var ph := PackedFloat64Array()   # N×3: P's position columns
	ph.resize(N * 3)
	for r in N:
		for c in 3:
			ph[r * 3 + c] = _p[r * N + c * 3]
	var k := PackedFloat64Array()
	k.resize(N * 3)
	for r in N:
		var row := Vector3(ph[r * 3], ph[r * 3 + 1], ph[r * 3 + 2])
		var kr := s_inv.transposed() * row   # row · S⁻¹ (S symmetric)
		k[r * 3] = kr.x
		k[r * 3 + 1] = kr.y
		k[r * 3 + 2] = kr.z
	for r in N:
		_x[r] += k[r * 3] * y.x + k[r * 3 + 1] * y.y + k[r * 3 + 2] * y.z
	var p_new := _p.duplicate()
	for r in N:
		for c in N:
			# (K H P)[r][c] = Σ_m K[r][m] · P[pos m][c]
			p_new[r * N + c] -= k[r * 3] * _p[c] + k[r * 3 + 1] * _p[3 * N + c] + k[r * 3 + 2] * _p[6 * N + c]
	_p = p_new
	_symmetrize()
	hits += 1
	last_update = t
	if hits >= firm_hits:
		state = State.FIRM


## Updates the state machine for the current time (no measurement needed).
func tick(now: float) -> void:
	if not is_started():
		return
	var since := now - last_update
	if since > lost_after:
		state = State.LOST
	elif since > coast_after:
		state = State.COAST
	elif hits >= firm_hits:
		state = State.FIRM


## [position, velocity, acceleration, position covariance] predicted to `now`.
func get_estimate(now: float) -> Array:
	if not is_started():
		return [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Basis()]
	var x := _x
	var p := _p
	var dt := maxf(now - time, 0.0)
	if dt > 0.0:
		var saved_x := _x.duplicate()
		var saved_p := _p.duplicate()
		_predict(dt)
		x = _x
		p = _p
		_x = saved_x
		_p = saved_p
	var cov := Basis(Vector3(p[0], p[3 * N], p[6 * N]), Vector3(p[3], p[3 * N + 3], p[6 * N + 3]),
			Vector3(p[6], p[3 * N + 6], p[6 * N + 6]))
	return [Vector3(x[0], x[3], x[6]), Vector3(x[1], x[4], x[7]), Vector3(x[2], x[5], x[8]), cov]


## Covariance (m²) of where the target will be `ahead` s after `now`: what a shot that
## takes that long to arrive has to cover.
func get_position_covariance_ahead(now: float, ahead: float) -> Basis:
	if not is_started():
		return Basis()
	var saved_x := _x.duplicate()
	var saved_p := _p.duplicate()
	_predict(maxf(now - time, 0.0) + maxf(ahead, 0.0))
	var p := _p
	_x = saved_x
	_p = saved_p
	return Basis(Vector3(p[0], p[3 * N], p[6 * N]), Vector3(p[3], p[3 * N + 3], p[6 * N + 3]),
			Vector3(p[6], p[3 * N + 6], p[6 * N + 6]))


func _start(t: float, pos: Vector3, cov: Basis) -> void:
	time = t
	last_update = t
	hits = 1
	rejected_in_a_row = 0
	state = State.TENTATIVE
	_x.fill(0.0)
	_p.fill(0.0)
	_x[0] = pos.x
	_x[3] = pos.y
	_x[6] = pos.z
	for a in 3:
		for b in 3:
			_p[(a * 3) * N + b * 3] = cov[b][a]
	for a in 3:
		_p[(a * 3 + 1) * N + a * 3 + 1] = 150.0 * 150.0       # velocity unknown: ±150 m/s
		_p[(a * 3 + 2) * N + a * 3 + 2] = maneuver_accel * maneuver_accel


## Singer transition and process noise over dt, the same for each axis block.
func _predict(dt: float) -> void:
	if dt <= 0.0:
		return
	var b := 1.0 / maneuver_time
	var e := exp(-b * dt)
	var f := [[1.0, dt, (b * dt - 1.0 + e) / (b * b)], [0.0, 1.0, (1.0 - e) / b], [0.0, 0.0, e]]
	var q := 2.0 * b * maneuver_accel * maneuver_accel
	var t2 := dt * dt
	var t3 := t2 * dt
	var qm := [[t3 * t2 / 20.0, t2 * t2 / 8.0, t3 / 6.0], [t2 * t2 / 8.0, t3 / 3.0, t2 / 2.0], [t3 / 6.0, t2 / 2.0, dt]]
	for a in 3:
		var o := a * 3
		var x0 := _x[o]
		var x1 := _x[o + 1]
		var x2 := _x[o + 2]
		_x[o] = f[0][0] * x0 + f[0][1] * x1 + f[0][2] * x2
		_x[o + 1] = f[1][1] * x1 + f[1][2] * x2
		_x[o + 2] = f[2][2] * x2
	# P = F P Fᵀ + Q with F block-diagonal: each 3×3 block (a, b) becomes Fa Pab Faᵀ.
	var p_new := PackedFloat64Array()
	p_new.resize(N * N)
	for ba in 3:
		for bb in 3:
			var blk := []
			for i in 3:
				blk.append([_p[(ba * 3 + i) * N + bb * 3], _p[(ba * 3 + i) * N + bb * 3 + 1], _p[(ba * 3 + i) * N + bb * 3 + 2]])
			for i in 3:
				for j in 3:
					var sum := 0.0
					for m in 3:
						for n in 3:
							sum += f[i][m] * blk[m][n] * f[j][n]
					if ba == bb:
						sum += q * qm[i][j]
					p_new[(ba * 3 + i) * N + bb * 3 + j] = sum
	_p = p_new


func _position() -> Vector3:
	return Vector3(_x[0], _x[3], _x[6])


func _pos_cov() -> Basis:
	return Basis(Vector3(_p[0], _p[3 * N], _p[6 * N]), Vector3(_p[3], _p[3 * N + 3], _p[6 * N + 3]),
			Vector3(_p[6], _p[3 * N + 6], _p[6 * N + 6]))


static func _add_basis(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)


func _symmetrize() -> void:
	for r in N:
		for c in range(r + 1, N):
			var v := 0.5 * (_p[r * N + c] + _p[c * N + r])
			_p[r * N + c] = v
			_p[c * N + r] = v
