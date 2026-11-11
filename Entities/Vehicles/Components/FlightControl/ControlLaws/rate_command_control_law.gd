class_name RateCommandControlLaw
extends ControlLaw

## Fly-by-wire law, in the spirit of modern fighter FCS.
##
## Everything the pilot commands is in the PILOT FRAME (the cockpit's
## orientation), not the body's:
##
## Rotation — the stick commands an angular rate of the pilot frame. In
##   ATTITUDE_HOLD the frame stops when the stick is released and the body
##   holds it (rate command / attitude hold). RATE_DAMP just damps rates.
##   Locking is per axis: a steered (or still braking) axis turns the cockpit
##   rigidly with the suit, while the other axes keep holding and auto-rotating.
## Translation — VELOCITY_HOLD: stick = velocity in the pilot frame relative
##   to the reference frame; released = brought to relative rest.
##   NEWTONIAN: stick = thrust demand, coast when released.
## Auto-rotation — an AttitudeOffsetSolver may turn the body away from the
##   pilot frame (body = pilot · offset) so its strongest thrusters face the
##   force demand. The cockpit counter-rotates, so the pilot's view stays put.

enum TranslationMode { NEWTONIAN, VELOCITY_HOLD }
enum RotationMode { RATE_DAMP, ATTITUDE_HOLD }

@export var translation_mode: TranslationMode = TranslationMode.VELOCITY_HOLD
@export var rotation_mode: RotationMode = RotationMode.ATTITUDE_HOLD
## Auto-rotation for thrust vectoring (ATTITUDE_HOLD only). Empty = body stays aligned.
@export var attitude_solver: AttitudeOffsetSolver
## Auto-rotation waits for the body: the offset swing slows once the body lags the
## target by the first angle and stops at the second, so it never runs away (deg).
@export var tracking_lag_deg := Vector2(6.0, 15.0)
## Only auto-rotate while boosting. Off: auto-rotate whenever a translation is
## commanded (or boosting) and the demand needs it; plain stops never rotate.
@export var auto_rotate_on_boost_only: bool = false

@export_group("Rotation")
## Max commanded rate at full stick (pitch, yaw, roll), deg/s.
@export var max_rate_deg := Vector3(40.0, 35.0, 60.0)
## Rate loop bandwidth, 1/s. Higher = snappier, more thruster chatter.
@export var rate_gain: float = 2.5
## Attitude loop gain, (rad/s) per rad of error.
@export var attitude_gain: float = 1.6
## After the stick is released, attitude is locked once the rate drops below this, deg/s.
@export var hold_capture_rate_deg: float = 2.0
@export var stick_deadzone: float = 0.04
## Each rotation axis locks to the stick on its own; it stays locked this long after
## its input drops into the deadzone, so a noisy stick doesn't flicker the lock, s.
@export var axis_release_time: float = 0.12
## Fraction of torque authority the FCS may request.
@export_range(0.0, 1.0) var torque_fraction: float = 0.6
## Torque authority auto-rotation (and attitude hold) may use.
@export_range(0.0, 1.0) var auto_rotate_torque_fraction: float = 0.4
## Allocator torque priority while auto-rotating/holding. Low = never spill force to
## rotate faster (big turning moments otherwise borrow the off-centre mains).
@export var auto_rotate_torque_priority: float = 0.5
## On stick release: rate-loop gain multiplier and full torque, so rotation stops at once.
@export var stop_gain_multiplier: float = 2.0
## Fraction of the estimated angular deceleration the braking curve plans with
## (slack for actuator lag and allocation losses). Higher = faster, riskier.
@export_range(0.1, 1.0) var braking_margin: float = 0.5
## Rate-loop gain multiplier while holding / realigning, so the body can follow the
## braking curve tightly (a soft loop brakes late and overshoots).
@export var hold_rate_gain_multiplier: float = 5.0
## Allocator torque priority while realigning to rest (< 0 = allocator default).
## Lower keeps the suit's braking push clean at the cost of a slower return.
@export var realign_torque_priority: float = 0.5

@export_group("Boost")
## While boosting: rate limits are multiplied by this, and torque/thrust limits open fully.
@export var boost_rate_multiplier: float = 1.7
@export var boost_rate_gain_multiplier: float = 1.5
@export var boost_speed_multiplier: float = 2.5

@export_group("Translation")
## Acceleration limit, same in every direction, so the suit moves in a straight
## line toward the command. Auto-rotation finds the attitude that can deliver it.
@export var cruise_accel_g: float = 0.35
@export var boost_accel_g: float = 4.0
## Velocity demanded at full stick in VELOCITY_HOLD, m/s.
@export var max_command_speed: float = 60.0
## Velocity loop gain, (m/s²) per (m/s) of error.
@export var velocity_gain: float = 0.8
## Velocity loop gain while boosting: snappy starts, stops and direction changes (dodging).
@export var boost_velocity_gain: float = 2.5

var _initialized := false
var _pilot := Quaternion.IDENTITY    ## Pilot frame orientation (global)
var _offset := Quaternion.IDENTITY   ## Body relative to pilot frame
var _offset_target_r := Vector3.ZERO ## Smoothed solver target, rotation vector (pilot frame)
var _offset_rate := Vector3.ZERO     ## Offset swing rate, pilot frame (rad/s), fed forward
var _auto_rotating := false   ## Solver engaged this tick (force must stay clean)
# Per pilot axis masks (pitch, yaw, roll), 1 = set:
var _active := Vector3.ZERO          ## Steered by the stick
var _capture := Vector3.ZERO         ## Steered, or released and still braking
var _locked := Vector3.ZERO          ## Cockpit locked to the body
var _newly_locked := Vector3.ZERO
var _release_timer := Vector3.ZERO
var _turn_sign := Vector3.ZERO       ## Direction each steered axis was turning


func reset() -> void:
	_initialized = false


func get_pilot_offset() -> Quaternion:
	return _offset


func get_pilot_orientation() -> Variant:
	return _pilot


func get_cockpit_orientation(body_q: Quaternion) -> Variant:
	if not _initialized:
		return null
	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		return body_q
	return _follow_body(body_q)


func compute(state: FlightState, command: PilotCommand) -> Wrench:
	var body_q := state.basis.get_rotation_quaternion()
	if not _initialized:
		_initialized = true
		_pilot = body_q
		_offset = Quaternion.IDENTITY
		_offset_target_r = Vector3.ZERO
		_offset_rate = Vector3.ZERO
		_auto_rotating = false
		_active = Vector3.ZERO
		_capture = Vector3.ZERO
		_locked = Vector3.ZERO
		_release_timer = Vector3.ZERO
		_turn_sign = Vector3.ZERO
	if command.toggle_translation_mode:
		translation_mode = ((translation_mode + 1) % TranslationMode.size()) as TranslationMode
	if command.toggle_rotation_mode:
		rotation_mode = ((rotation_mode + 1) % RotationMode.size()) as RotationMode
		_pilot = body_q * _offset.inverse()

	_update_locks(state, command)
	_update_pilot(body_q)
	var force_world := _translation_force_world(state, command)
	_update_offset(state, force_world, command)
	var torque := _rotation_torque(state, command, body_q)
	var force_body := clamp_to_capability(state.to_local(force_world), state, 1.0)
	var wrench := Wrench.new(force_body, torque)
	# Steering and stopping keep the allocator default.
	if _locked == Vector3.ZERO:
		wrench.torque_priority = auto_rotate_torque_priority if _auto_rotating \
				else realign_torque_priority
	return wrench


func get_mode_labels() -> PackedStringArray:
	var trans := "TRANS NEWTON" if translation_mode == TranslationMode.NEWTONIAN else "TRANS V-HOLD"
	var rot := "ROT RATE"
	if rotation_mode == RotationMode.ATTITUDE_HOLD:
		rot = "ROT ATT-HOLD" + (" ●" if is_holding_attitude() else "")
	var labels := PackedStringArray([trans, rot])
	if attitude_solver != null and rotation_mode == RotationMode.ATTITUDE_HOLD:
		labels.append("VECTOR %02d°" % roundi(rad_to_deg(_offset.get_angle())))
	return labels


func is_holding_attitude() -> bool:
	return rotation_mode == RotationMode.ATTITUDE_HOLD and _locked == Vector3.ZERO


## Per-axis lock state. An axis locks while its stick is deflected (plus
## axis_release_time, so a noisy stick doesn't flicker) and stays locked after
## release until the released axes have all stopped turning the way they were
## steered (rate below hold_capture_rate_deg or reversed), then hands them to the
## attitude hold, which also takes out any overshoot without moving the view.
func _update_locks(state: FlightState, command: PilotCommand) -> void:
	var was_locked := _locked
	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		var on := command.rotation.length() > stick_deadzone
		_active = Vector3.ONE if on else Vector3.ZERO
		_capture = Vector3.ZERO
		_locked = Vector3.ONE
		_newly_locked = Vector3.ZERO
		return
	# Body turn rate about the pilot's axes, minus what the offset swing itself causes.
	var rate_p := _pilot.inverse() * state.angular_velocity - _offset_rate
	for k in 3:
		if absf(command.rotation[k]) > stick_deadzone:
			_active[k] = 1.0
			_release_timer[k] = axis_release_time
		elif _active[k] > 0.0:
			_release_timer[k] -= state.delta
			if _release_timer[k] <= 0.0:
				_active[k] = 0.0
	var capture_rate := deg_to_rad(hold_capture_rate_deg)
	var stopped := true
	for k in 3:
		if _active[k] > 0.0:
			if absf(rate_p[k]) > capture_rate:
				_turn_sign[k] = signf(rate_p[k])
		elif _capture[k] > 0.0 and rate_p[k] * _turn_sign[k] >= capture_rate:
			stopped = false
	_capture = _active if stopped else _capture.max(_active)
	_locked = _capture
	_newly_locked = (_locked - was_locked).max(Vector3.ZERO)


## Moves the pilot frame with the body on locked axes and holds it on free ones.
## A newly locked axis first takes the body's lag on it into the offset, so locking
## mid-swing never jumps the view.
func _update_pilot(body_q: Quaternion) -> void:
	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		_offset = Quaternion.IDENTITY
		_pilot = body_q
		return
	if _newly_locked != Vector3.ZERO:
		var lag := AttitudeOffsetSolver.from_rotation_vector(_deviation(body_q) * _newly_locked)
		_offset = (lag * _offset).normalized()
		_offset_target_r = AttitudeOffsetSolver.to_rotation_vector(_offset)
	_pilot = _follow_body(body_q)


## Body deviation from pilot · offset, as a rotation vector in the pilot frame
## (body = pilot · D · offset).
func _deviation(body_q: Quaternion) -> Vector3:
	return AttitudeOffsetSolver.to_rotation_vector(_pilot.inverse() * body_q * _offset.inverse())


## Pilot frame that follows a body at body_q on the locked axes only.
func _follow_body(body_q: Quaternion) -> Quaternion:
	if _locked == Vector3.ONE:
		return (body_q * _offset.inverse()).normalized()
	if _locked == Vector3.ZERO:
		return _pilot
	var step := AttitudeOffsetSolver.from_rotation_vector(_deviation(body_q) * _locked)
	return (_pilot * step).normalized()


## Auto-rotation on the free axes; locked axes keep their offset component.
func _update_offset(state: FlightState, force_world: Vector3, command: PilotCommand) -> void:
	_offset_rate = Vector3.ZERO
	_auto_rotating = false
	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		return
	var r_cur := AttitudeOffsetSolver.to_rotation_vector(_offset)
	if _locked == Vector3.ONE:
		_offset_target_r = r_cur
		return
	var free := Vector3.ONE - _locked
	var r_target := r_cur * _locked
	var slew := deg_to_rad(60.0)
	var smoothing := 0.0
	if attitude_solver != null:
		slew = deg_to_rad(attitude_solver.slew_rate_deg)
		smoothing = attitude_solver.smoothing_time
		var translating := command.translation.length() > stick_deadzone
		var wanted := command.boost if auto_rotate_on_boost_only else (command.boost or translating)
		if state.allow_attitude_offset and wanted:
			var force_pilot := _pilot.inverse() * force_world
			r_target = AttitudeOffsetSolver.to_rotation_vector(
					attitude_solver.solve(state, force_pilot, _offset, _locked))
			_auto_rotating = true
		else:
			# Nothing needs the offset: aim the free axes straight back at the cockpit
			# and let the time-optimal hold bring the body home in one motion.
			_offset = AttitudeOffsetSolver.from_rotation_vector(r_target)
			_offset_target_r = r_target
			return
	r_target = r_target * free + r_cur * _locked
	# Low-pass the target first so the body eases into (and out of) a new attitude.
	_offset_target_r = _offset_target_r * free + r_cur * _locked
	if smoothing > 0.0:
		_offset_target_r = _offset_target_r.lerp(r_target, 1.0 - exp(-state.delta / smoothing))
	else:
		_offset_target_r = r_target
	# Throttle the swing by how far the body already lags the current target.
	var body_q := state.basis.get_rotation_quaternion()
	var lag_q := AttitudeOffsetSolver.shortest((_pilot * _offset) * body_q.inverse())
	var lag := rad_to_deg(lag_q.get_angle())
	var span := maxf(tracking_lag_deg.y - tracking_lag_deg.x, 0.01)
	slew *= clampf(1.0 - (lag - tracking_lag_deg.x) / span, 0.0, 1.0)
	var step := ((_offset_target_r - r_cur) * free).limit_length(slew * state.delta)
	if step.length_squared() < 1e-12:
		return
	var old := _offset
	_offset = AttitudeOffsetSolver.from_rotation_vector(r_cur + step)
	if _auto_rotating and state.delta > 0.0:
		_offset_rate = AttitudeOffsetSolver.to_rotation_vector(_offset * old.inverse()) / state.delta


func _rotation_torque(state: FlightState, command: PilotCommand, body_q: Quaternion) -> Vector3:
	var omega := state.local_angular_velocity
	var max_rate := max_rate_deg * (PI / 180.0) * (boost_rate_multiplier if command.boost else 1.0)
	var gain := rate_gain * (boost_rate_gain_multiplier if command.boost else 1.0)
	var inertia := state.inertia_local
	var gyro := omega.cross(inertia * omega)
	var steering := _active != Vector3.ZERO

	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		var rate_cmd := command.rotation * max_rate if steering else Vector3.ZERO
		if not steering:
			gain *= hold_rate_gain_multiplier
		var fraction := 1.0 if command.boost and steering else torque_fraction
		var limit := state.max_torque * fraction
		return (inertia * ((rate_cmd - omega) * gain) + gyro).clamp(-limit, limit)

	# Everything below is about the pilot's axes. Locked axes: the stick commands the
	# rate (0 while braking a released turn). Free axes: track pilot · offset. Both
	# get the offset swing fed forward so fast swings don't lag.
	var body_to_pilot := _pilot.inverse() * body_q
	var pilot_to_body := body_to_pilot.inverse()
	var free := Vector3.ONE - _locked
	var rate_p := command.rotation * max_rate * _active + _offset_rate
	if free != Vector3.ZERO:
		var err_q := AttitudeOffsetSolver.shortest((_pilot * _offset) * body_q.inverse())
		var err_p := Vector3.ZERO
		if err_q.get_angle() > 1e-6:
			err_p = (_pilot.inverse() * (err_q.get_axis() * err_q.get_angle())) * free
		var err := pilot_to_body * err_p
		# Auto-rotation may swing the body faster than the pilot's own rate limits.
		var hold_rate := max_rate * 1.2
		if attitude_solver != null:
			hold_rate = hold_rate.max(Vector3.ONE * deg_to_rad(attitude_solver.slew_rate_deg) * 1.2)
		# Auto-rotation tracks a moving target gently (keeps force clean); realigning
		# to rest uses the time-optimal braking curve.
		var approach := err * attitude_gain if _auto_rotating else _braking_rate(state, err)
		var hold_p := (body_to_pilot * approach + _offset_rate) * free
		rate_p = rate_p * _locked + hold_p.clamp(-hold_rate, hold_rate)

	var omega_p := body_to_pilot * omega
	var gain_p := Vector3.ZERO
	for k in 3:
		if _active[k] > 0.0:
			gain_p[k] = gain
		elif _capture[k] > 0.0:
			gain_p[k] = gain * stop_gain_multiplier
		elif _auto_rotating:
			gain_p[k] = gain
		else:
			gain_p[k] = gain * hold_rate_gain_multiplier
	var alpha_p := (rate_p - omega_p) * gain_p

	# Locked and free axes get separate torque budgets: a boosted turn or a stop may
	# use it all, while auto-rotation stays gentle so it never spills force.
	var stopping := (_capture - _active).max(Vector3.ZERO) != Vector3.ZERO
	var lock_fraction := 1.0 if stopping or (command.boost and steering) else torque_fraction
	var free_fraction := auto_rotate_torque_fraction if _auto_rotating else torque_fraction
	var lock_limit := state.max_torque * lock_fraction
	var free_limit := state.max_torque * free_fraction
	var torque_lock := (inertia * (pilot_to_body * (alpha_p * _locked))).clamp(-lock_limit, lock_limit)
	var torque_free := (inertia * (pilot_to_body * (alpha_p * free))).clamp(-free_limit, free_limit)
	var limit := lock_limit if _locked != Vector3.ZERO else free_limit
	if free != Vector3.ZERO:
		limit = limit.max(free_limit)
	return (torque_lock + torque_free + gyro).clamp(-limit, limit)


## Time-optimal approach: the fastest rate from which the body can still brake to
## rest exactly on target, ω = √(2·α·θ), with α the deceleration the torque limit
## allows about the error axis. Linear near zero so it settles without chatter.
func _braking_rate(state: FlightState, err: Vector3) -> Vector3:
	var angle := err.length()
	if angle < 1e-6:
		return Vector3.ZERO
	var axis := err / angle
	var fraction := auto_rotate_torque_fraction if _auto_rotating else torque_fraction
	var limit := state.max_torque * fraction
	var per_alpha := (state.inertia_local * axis).abs()
	var alpha := INF
	for k in 3:
		if per_alpha[k] > 1e-3:
			alpha = minf(alpha, limit[k] / per_alpha[k])
	if alpha == INF:
		return err * attitude_gain
	alpha *= braking_margin
	var linear_zone := deg_to_rad(1.5)
	var rate := sqrt(2.0 * alpha * maxf(angle, linear_zone))
	if angle < linear_zone:
		rate *= angle / linear_zone
	return axis * rate


func _translation_force_world(state: FlightState, command: PilotCommand) -> Vector3:
	var stick_world := _pilot * command.translation
	var accel_limit := (boost_accel_g if command.boost else cruise_accel_g) * FlightComputer.G0
	if translation_mode == TranslationMode.NEWTONIAN:
		return stick_world.limit_length(1.0) * accel_limit * state.mass

	var speed := max_command_speed * (boost_speed_multiplier if command.boost else 1.0)
	var v_error := stick_world * speed - state.linear_velocity
	var gain := boost_velocity_gain if command.boost else velocity_gain
	return (v_error * gain).limit_length(accel_limit) * state.mass
