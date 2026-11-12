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
## Translation — the stick pushes along its direction (pilot frame) with no top speed;
##   speed on the axes it holds is wanted, never cancelled. Released axes coast. Brake
##   (Ctrl) stops the motion, relative to the reference frame, on the axes the stick
##   isn't holding; a double-tapped brake may turn the suit further, like a boost.
## Auto-rotation — an AttitudeOffsetSolver may turn the body away from the
##   pilot frame (body = pilot · offset) so its strongest thrusters face the
##   force demand. The cockpit counter-rotates, so the pilot's view stays put.
## Movement modes — how far auto-rotation may commit: normal flight and Shift
##   are capped (cruise/boost_max_offset_deg) so the suit stays quick to change
##   direction; a double-tapped Shift unlocks the solver's full range. Precision
##   (toggle) turns auto-rotation off and gentles thrust and turn rates.
## Horizon lock — (toggle) yaw turns about a stored "up" and roll is held level to
##   it, so pitch + yaw never bank the view. Rolling by hand sets a new horizon.
##   It fades out looking straight up or down, so loops still work.

enum RotationMode { RATE_DAMP, ATTITUDE_HOLD }

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
## Rate loop bandwidth for steering and stops, 1/s. Higher = snappier, more chatter.
@export var rate_gain: float = 5.0
## Rate loop bandwidth while auto-rotating, 1/s. Gentler, so the swing never asks for
## turning moments that spill force.
@export var auto_rotate_rate_gain: float = 2.5
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
## When the body falls behind the auto-rotation target (across tracking_lag_deg), its torque
## budget and priority rise to these, so thrust torque can't push it past the target.
@export var recover_torque_priority: float = 2.0
## On stick release: rate-loop gain multiplier and full torque, so rotation stops at once.
@export var stop_gain_multiplier: float = 2.5
## Fraction of the estimated angular deceleration the braking curve plans with
## (slack for actuator lag and allocation losses). Higher = faster, riskier.
@export_range(0.1, 1.0) var braking_margin: float = 0.8
## Reaction delay the braking curve allows for (thruster spool-up, nozzle slew), s. Braking
## starts this much earlier, so the body doesn't arrive still turning and swing past.
@export var braking_delay: float = 0.15
## Braking margin for easing an auto-rotation swing into its end point (a soft target,
## so it can plan closer to the real deceleration than a stop).
@export_range(0.1, 1.0) var swing_braking_margin: float = 1.0
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

@export_group("Movement modes")
## Auto-rotation limit in normal flight and with Shift held, deg. A double-tapped Shift
## or brake uses the solver's own max_offset_deg.
@export var cruise_max_offset_deg: float = 20.0
@export var boost_max_offset_deg: float = 30.0
## Precision mode: no auto-rotation, this acceleration (pushing and braking), no pushing
## past precision_speed along the stick, and the turn rates scaled down. Shift still
## boosts normally.
@export var precision_accel_g: float = 0.15
@export var precision_speed: float = 20.0
@export var precision_rate_multiplier: float = 0.5
@export var precision: bool = false

@export_group("Horizon lock")
@export var horizon_lock: bool = true
## Levelling: roll rate per rad of bank, 1/s, and its limit, deg/s.
@export var horizon_level_gain: float = 3.0
@export var horizon_level_rate_deg: float = 30.0
## How close to level the nose must be for the full lock (|cos pitch|). Below it the
## lock fades toward plain body-axis yaw, so pitching over the top doesn't flip.
@export_range(0.05, 1.0) var horizon_fade: float = 0.25

@export_group("Translation")
## Acceleration limit, same in every direction, so the suit moves in a straight
## line toward the command. Auto-rotation finds the attitude that can deliver it.
@export var cruise_accel_g: float = 0.8
## Shift. A double-tapped (full) boost has no limit: everything the thrusters can give.
@export var boost_accel_g: float = 7.0
## Precision mode's speed loop gain, (m/s²) per (m/s) of error.
@export var velocity_gain: float = 0.8
## Braking: (m/s²) per (m/s) of the motion being stopped, up to stop_accel_g (a combat
## suit stops at once), limited by what the attitude can deliver. Precision mode brakes
## at precision_accel_g.
@export var brake_gain: float = 2.5
@export var stop_accel_g: float = 6.0

var _initialized := false
var _pilot := Quaternion.IDENTITY    ## Pilot frame orientation (global)
var _offset := Quaternion.IDENTITY   ## Body relative to pilot frame
var _offset_target_r := Vector3.ZERO ## Smoothed solver target, rotation vector (pilot frame)
var _offset_rate := Vector3.ZERO     ## Offset swing rate, pilot frame (rad/s), fed forward
var _offset_vel := Vector3.ZERO      ## Swing velocity of the commanded offset (rotation vector, rad/s)
var _auto_rotating := false   ## Solver engaged this tick (force must stay clean)
var _recover := 0.0           ## 0..1, how far the body lags the auto-rotation target
var _brake := 0.0             ## 0..1, the hold is braking into its target (gets full torque)
# Per pilot axis masks (pitch, yaw, roll), 1 = set:
var _active := Vector3.ZERO          ## Steered by the stick
var _capture := Vector3.ZERO         ## Steered, or released and still braking
var _locked := Vector3.ZERO          ## Cockpit locked to the body
var _newly_locked := Vector3.ZERO
var _release_timer := Vector3.ZERO
var _turn_sign := Vector3.ZERO       ## Direction each steered axis was turning
var _last_boost := false             ## For the HUD label
var _last_boost_full := false
var _last_brake := false
var _last_brake_full := false
var _thruster_limit := Vector3.INF   ## Thrusters' share of this tick's torque limit
var _stick := Vector3.ZERO           ## Rotation demand after horizon-lock shaping
var _horizon_up := Vector3.UP        ## Global "up" the horizon lock levels to
var _manual_roll := false            ## Pilot is rolling (sets a new horizon)


func reset() -> void:
	_initialized = false


func get_pilot_offset() -> Quaternion:
	return _offset


func get_pilot_orientation() -> Variant:
	return _pilot


func get_horizon_up() -> Variant:
	return _horizon_up if horizon_lock and _initialized else null


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
		_horizon_up = body_q * Vector3.UP
		_manual_roll = false
	if command.toggle_precision:
		precision = not precision
	if command.toggle_rotation_mode:
		rotation_mode = ((rotation_mode + 1) % RotationMode.size()) as RotationMode
		_pilot = body_q * _offset.inverse()
	if command.toggle_horizon_lock:
		horizon_lock = not horizon_lock
		_horizon_up = _pilot * Vector3.UP
		_manual_roll = false

	command.boost = command.boost or command.boost_full
	_last_boost = command.boost
	_last_boost_full = command.boost_full
	command.brake = command.brake or command.brake_full
	_last_brake = command.brake
	_last_brake_full = command.brake_full
	_stick = _horizon_stick(command)
	_update_locks(state, command)
	_update_pilot(body_q)
	_level_horizon(state.delta)
	var force_world := _translation_force_world(state, command)
	_update_offset(state, force_world, command)
	var torque := _rotation_torque(state, command, body_q)
	var force_body := clamp_to_capability(state.to_local(force_world), state, 1.0)
	var wrench := Wrench.new(force_body, torque)
	wrench.thruster_torque_limit = _thruster_limit
	# Steering and stopping keep the allocator default.
	# Braking into a target always wins: a stop matters more than a clean push.
	if _locked == Vector3.ZERO:
		var base := lerpf(auto_rotate_torque_priority, recover_torque_priority, _recover) \
				if _auto_rotating else realign_torque_priority
		wrench.torque_priority = lerpf(base, recover_torque_priority, _brake)
	return wrench


## Only what differs from the defaults (attitude hold, horizon lock, normal movement).
func get_mode_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		labels.append("ROT RATE")
	if not horizon_lock:
		labels.append("HORIZON FREE")
	if _last_boost_full:
		labels.append("BOOST FULL")
	elif _last_boost:
		labels.append("BOOST")
	elif precision:
		labels.append("PRECISION")
	if _last_brake_full:
		labels.append("BRAKE HARD")
	elif _last_brake:
		labels.append("BRAKE")
	return labels


func get_boost_level() -> int:
	return 2 if _last_boost_full else (1 if _last_boost else 0)


func get_brake_level() -> int:
	return 2 if _last_brake_full else (1 if _last_brake else 0)


## Auto-rotation limit for this tick, deg (0 = off).
func _offset_limit_deg(command: PilotCommand) -> float:
	if command.boost_full or (command.brake_full and not precision):
		return attitude_solver.max_offset_deg
	if command.boost:
		return boost_max_offset_deg
	return 0.0 if precision else cruise_max_offset_deg


func is_holding_attitude() -> bool:
	return rotation_mode == RotationMode.ATTITUDE_HOLD and _locked == Vector3.ZERO


## Horizon lock: yaw about the horizon's up instead of the pilot's, plus a roll
## that levels any bank. Rolling by hand bypasses it and resets the horizon.
func _horizon_stick(command: PilotCommand) -> Vector3:
	var stick := command.rotation
	if not horizon_lock:
		return stick
	if absf(stick.z) > stick_deadzone:
		_manual_roll = true
	elif _manual_roll and _capture.z == 0.0:
		_manual_roll = false
		_horizon_up = _pilot * Vector3.UP
	if _manual_roll:
		_horizon_up = _pilot * Vector3.UP
		return stick
	var steering := Vector2(stick.x, stick.y).length() > stick_deadzone
	# Keep levelling while a released pitch/yaw still brakes (each axis stops on
	# its own, which banks the view near vertical).
	var braking := _capture.x > 0.0 or _capture.y > 0.0
	if not steering and not braking:
		return stick
	var up_p := _horizon_up_pilot()
	var k := _horizon_weight(up_p)
	if not steering:
		return Vector3(0.0, 0.0, clampf(_level_rate_deg(up_p) * k / max_rate_deg.z, -1.0, 1.0))
	var yaw_axis := Vector3.UP.lerp(up_p, k).normalized()
	var rate := Vector3(stick.x * max_rate_deg.x, 0.0, 0.0) + yaw_axis * (stick.y * max_rate_deg.y)
	rate.z += _level_rate_deg(up_p) * k
	return (rate / max_rate_deg).clamp(-Vector3.ONE, Vector3.ONE)


## Horizon up in the pilot frame, flipped when inverted (so a loop keeps going
## instead of rolling back upright).
func _horizon_up_pilot() -> Vector3:
	var up_p := _pilot.inverse() * _horizon_up
	return -up_p if up_p.y < 0.0 else up_p


## 1 near level, fading to 0 looking straight up or down.
func _horizon_weight(up_p: Vector3) -> float:
	return clampf(absf(up_p.y) / horizon_fade, 0.0, 1.0)


## Roll rate that removes the bank, deg/s (about pilot +Z).
func _level_rate_deg(up_p: Vector3) -> float:
	var bank := atan2(-up_p.x, up_p.y)
	return clampf(rad_to_deg(bank) * horizon_level_gain, -horizon_level_rate_deg, horizon_level_rate_deg)


## Levels a held (free) roll axis by turning the pilot frame; the attitude hold
## brings the body along.
func _level_horizon(delta: float) -> void:
	if not horizon_lock or _manual_roll or rotation_mode != RotationMode.ATTITUDE_HOLD \
			or _locked.z > 0.0:
		return
	var up_p := _horizon_up_pilot()
	var roll := deg_to_rad(_level_rate_deg(up_p)) * _horizon_weight(up_p) * delta
	if absf(roll) > 1e-7:
		_pilot = (_pilot * Quaternion(Vector3.BACK, roll)).normalized()


## Per-axis lock state. An axis locks while its stick is deflected (plus
## axis_release_time, so a noisy stick doesn't flicker) and stays locked after
## release until the released axes have all stopped turning the way they were
## steered (rate below hold_capture_rate_deg or reversed), then hands them to the
## attitude hold, which also takes out any overshoot without moving the view.
func _update_locks(state: FlightState, command: PilotCommand) -> void:
	var was_locked := _locked
	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		var on := _stick.length() > stick_deadzone
		_active = Vector3.ONE if on else Vector3.ZERO
		_capture = Vector3.ZERO
		_locked = Vector3.ONE
		_newly_locked = Vector3.ZERO
		return
	# Body turn rate about the pilot's axes, minus what the offset swing itself causes.
	var rate_p := _pilot.inverse() * state.angular_velocity - _offset_rate
	for k in 3:
		if absf(_stick[k]) > stick_deadzone:
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
	_recover = 0.0
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
		var wanted := command.boost if auto_rotate_on_boost_only \
				else (command.boost or translating or command.brake_full)
		var limit := _offset_limit_deg(command)
		if state.allow_attitude_offset and wanted and limit > 0.0:
			var force_pilot := _pilot.inverse() * force_world
			r_target = AttitudeOffsetSolver.to_rotation_vector(
					attitude_solver.solve(state, force_pilot, _offset, _locked, limit))
			_auto_rotating = true
		else:
			# Nothing needs the offset: aim the free axes straight back at the cockpit
			# and let the time-optimal hold bring the body home in one motion.
			_offset = AttitudeOffsetSolver.from_rotation_vector(r_target)
			_offset_target_r = r_target
			_offset_vel = Vector3.ZERO
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
	_recover = clampf((lag - tracking_lag_deg.x) / span, 0.0, 1.0) if _auto_rotating else 0.0
	slew *= 1.0 - _recover
	# The commanded offset moves like a body would: its swing speed changes no faster than
	# the body can accelerate, and it eases into the end point the way the body can brake.
	# So the body can always follow it exactly: no overshoot when the target stops or
	# turns back, and no side drift from overshoot to make the solver change its mind.
	var remaining := (_offset_target_r - r_cur) * free
	var to_body := func(v: Vector3) -> Vector3: return state.to_local(_pilot * v)
	var to_pilot := func(v: Vector3) -> Vector3: return _pilot.inverse() * state.to_global(v)
	var v_want: Vector3 = to_pilot.call(_braking_rate(state, to_body.call(remaining), swing_braking_margin))
	v_want = (v_want * free).limit_length(slew)
	_offset_vel *= free
	var dv := v_want - _offset_vel
	var accel := _swing_accel(state, to_body.call(dv))
	_offset_vel += dv.limit_length(accel * state.delta)
	var step := _offset_vel * state.delta
	if step.length_squared() < 1e-12:
		return
	var old := _offset
	_offset = AttitudeOffsetSolver.from_rotation_vector(r_cur + step)
	if _auto_rotating and state.delta > 0.0:
		_offset_rate = AttitudeOffsetSolver.to_rotation_vector(_offset * old.inverse()) / state.delta


func _rotation_torque(state: FlightState, command: PilotCommand, body_q: Quaternion) -> Vector3:
	var omega := state.local_angular_velocity
	_brake = 0.0
	var max_rate := max_rate_deg * (PI / 180.0)
	if command.boost:
		max_rate *= boost_rate_multiplier
	elif precision:
		max_rate *= precision_rate_multiplier
	var gain := rate_gain * (boost_rate_gain_multiplier if command.boost else 1.0)
	var inertia := state.inertia_local
	var gyro := omega.cross(inertia * omega)
	var steering := _active != Vector3.ZERO

	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		var rate_cmd := _stick * max_rate if steering else Vector3.ZERO
		if not steering:
			gain *= hold_rate_gain_multiplier
		var fraction := 1.0 if command.boost and steering else torque_fraction
		_thruster_limit = state.max_torque * fraction
		var limit := _thruster_limit + state.ambac_torque
		return (inertia * ((rate_cmd - omega) * gain) + gyro).clamp(-limit, limit)

	# Everything below is about the pilot's axes. Locked axes: the stick commands the
	# rate (0 while braking a released turn). Free axes: track pilot · offset. Both
	# get the offset swing fed forward so fast swings don't lag.
	var body_to_pilot := _pilot.inverse() * body_q
	var pilot_to_body := body_to_pilot.inverse()
	var free := Vector3.ONE - _locked
	var rate_p := _stick * max_rate * _active + _offset_rate
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
		# Realigning to rest uses the time-optimal braking curve; auto-rotation tracks
		# gently, but never faster than it can still stop on target. Accelerating stays
		# gentle (clean force); once the body has to slow down to arrive, it gets the
		# full torque budget, so it stops on target instead of swinging past.
		var approach := _braking_rate(state, err)
		var reach := approach.length()
		if reach > 1e-4:
			var closing := omega.dot(err / maxf(err.length(), 1e-6))
			_brake = clampf((closing / reach - 0.6) / 0.3, 0.0, 1.0)
		if _auto_rotating:
			approach = (err * attitude_gain).limit_length(reach)
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
			var fast := command.boost or (command.brake_full and not precision)
			gain_p[k] = auto_rotate_rate_gain * (boost_rate_gain_multiplier if fast else 1.0)
		else:
			gain_p[k] = gain * hold_rate_gain_multiplier
	var alpha_p := (rate_p - omega_p) * gain_p

	# Locked and free axes get separate torque budgets: a boosted turn or a stop may
	# use it all, while auto-rotation stays gentle so it never spills force. The limbs'
	# torque comes on top of both (it moves no thrusters, so it's always clean).
	var stopping := (_capture - _active).max(Vector3.ZERO) != Vector3.ZERO
	var lock_fraction := 1.0 if stopping or (command.boost and steering) else torque_fraction
	var free_fraction := lerpf(_auto_fraction() if _auto_rotating else torque_fraction, 1.0, _brake)
	var lock_thrust := state.max_torque * lock_fraction
	var free_thrust := state.max_torque * free_fraction
	var lock_limit := lock_thrust + state.ambac_torque
	var free_limit := free_thrust + state.ambac_torque
	var torque_lock := (inertia * (pilot_to_body * (alpha_p * _locked))).clamp(-lock_limit, lock_limit)
	var torque_free := (inertia * (pilot_to_body * (alpha_p * free))).clamp(-free_limit, free_limit)
	_thruster_limit = lock_thrust if _locked != Vector3.ZERO else free_thrust
	if free != Vector3.ZERO:
		_thruster_limit = _thruster_limit.max(free_thrust)
	var limit := _thruster_limit + state.ambac_torque
	return (torque_lock + torque_free + gyro).clamp(-limit, limit)


func _auto_fraction() -> float:
	return lerpf(auto_rotate_torque_fraction, torque_fraction, _recover)


## Angular acceleration the torque budget allows about a body axis, rad/s² (INF if none).
func _max_alpha(state: FlightState, axis: Vector3) -> float:
	var fraction := _auto_fraction() if _auto_rotating else torque_fraction
	var limit := state.max_torque * fraction + state.ambac_torque
	var per_alpha := (state.inertia_local * axis).abs()
	var alpha := INF
	for k in 3:
		if per_alpha[k] > 1e-3:
			alpha = minf(alpha, limit[k] / per_alpha[k])
	return alpha


## Acceleration limit for the commanded offset's swing speed (change dv, body frame).
func _swing_accel(state: FlightState, dv: Vector3) -> float:
	if dv.length_squared() < 1e-12:
		return 0.0
	var alpha := _max_alpha(state, dv.normalized())
	return 1e3 if alpha == INF else alpha * swing_braking_margin


## Time-optimal approach: the fastest rate from which the body can still brake to
## rest exactly on target after a reaction delay τ, ω = √((α·τ)² + 2·α·θ) − α·τ, with α
## the deceleration the torque limit allows about the error axis. Linear near zero so
## it settles without chatter.
func _braking_rate(state: FlightState, err: Vector3, margin: float = -1.0) -> Vector3:
	var angle := err.length()
	if angle < 1e-6:
		return Vector3.ZERO
	var axis := err / angle
	var alpha := _max_alpha(state, axis)
	if alpha == INF:
		return err * attitude_gain
	alpha *= braking_margin if margin < 0.0 else margin
	var linear_zone := deg_to_rad(1.5)
	var lead := alpha * braking_delay
	var rate := sqrt(lead * lead + 2.0 * alpha * maxf(angle, linear_zone)) - lead
	if angle < linear_zone:
		rate *= angle / linear_zone
	return axis * rate


func _total_thrust(state: FlightState) -> float:
	var total := 0.0
	for t in state.thruster_max:
		total += t
	return total


func _translation_force_world(state: FlightState, command: PilotCommand) -> Vector3:
	var stick_world := _pilot * command.translation
	var gentle := precision and not command.boost
	var accel_g := boost_accel_g if command.boost else (precision_accel_g if gentle else cruise_accel_g)
	var accel_limit := accel_g * FlightComputer.G0
	if command.boost_full:
		accel_limit = maxf(accel_limit, _total_thrust(state) / state.mass)
	var v := state.linear_velocity
	var push := Vector3.ZERO
	var amount := stick_world.length()
	if amount > stick_deadzone:
		var dir := stick_world / amount
		var push_accel := minf(amount, 1.0) * accel_limit
		if gentle:
			push_accel = clampf((precision_speed * minf(amount, 1.0) - v.dot(dir)) * velocity_gain,
					0.0, push_accel)
		push = dir * push_accel
	if not command.brake:
		return push * state.mass
	# Brake only the pilot axes the stick isn't holding.
	var held := Vector3.ZERO
	for k in 3:
		held[k] = 1.0 if absf(command.translation[k]) > stick_deadzone else 0.0
	var v_free := _pilot * ((_pilot.inverse() * v) * (Vector3.ONE - held))
	var brake_limit := (precision_accel_g if gentle else stop_accel_g) * FlightComputer.G0
	if command.brake_full and not gentle:
		brake_limit = maxf(brake_limit, _total_thrust(state) / state.mass)  # hard brake: no cap
	var brake := (-v_free * brake_gain).limit_length(brake_limit)
	return (push + brake).limit_length(maxf(accel_limit, brake_limit)) * state.mass
