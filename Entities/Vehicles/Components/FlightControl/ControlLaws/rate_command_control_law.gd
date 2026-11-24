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
##   rigidly with the suit, while the other axes keep holding and auto-rotating
##   (steered axes keep auto-rotating too, slower: steer_auto_rotate_share).
## Translation — the stick pushes along its direction (pilot frame) with no top speed;
##   speed on the axes it holds is wanted, never cancelled. Released axes coast. Brake
##   (Ctrl) stops the motion, relative to the reference frame, on the axes the stick
##   isn't holding, and on held axes still moving against the stick; a double-tapped
##   brake may turn the suit further, like a boost. Drift hold pushes out motion
##   nobody commanded (force spilled while turning) on the axes the stick isn't holding.
## Auto-rotation — an AttitudeOffsetSolver may turn the body away from the
##   pilot frame (body = pilot · offset) so its strongest thrusters face the
##   force demand. The cockpit counter-rotates, so the pilot's view stays put.
## Movement modes — how far auto-rotation may commit: normal flight and Shift
##   are capped (cruise/boost_max_offset_deg) so the suit stays quick to change
##   direction; a double-tapped Shift (or an analog stick at its stops) unlocks the
##   solver's full range. Precision (toggle) turns auto-rotation off and gentles thrust
##   and turn rates.
## Dodge — a press with a direction kicks that way for dodge_time, and on for as long
##   as the button is held, until the kick tank is dry: the pintles open (FlightComputer
##   burst) and the suit pushes with everything it has from the attitude it is in, no
##   swing. While held, the stick steers it.
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
## Auto-rotation keeps running on a steered axis at this fraction of its swing rate
## (the view still turns at the stick rate; the body adds the swing). 0 = pause it.
@export_range(0.0, 1.0) var steer_auto_rotate_share: float = 0.4
## Swing rate left to the axes that aren't steered while another one is.
@export_range(0.0, 1.0) var steer_free_swing_share: float = 0.4
## Only auto-rotate while boosting. Off: auto-rotate whenever a translation is
## commanded (or boosting) and the demand needs it; plain stops never rotate.
@export var auto_rotate_on_boost_only: bool = false

@export_group("Rotation")
## Max commanded rate at full stick (pitch, yaw, roll), deg/s.
@export var max_rate_deg := Vector3(90.0, 90.0, 120.0)
## The stick's turn rate is capped at what the suit can stop again within this time
## (clean torque + limbs), s. The pilot gets a slower top rate on the heavy axes, and a
## turn that ends where the stick is released. 0 = no cap.
@export var stop_time: float = 0.4
## Share of the clean torque a stop can count on while the thrusters are also pushing at
## full capability (a boost or a hard brake), per axis (pitch, yaw, roll); the cap above
## plans with it. Measure it with the suit's allocator under load before raising it.
@export var loaded_torque_share := Vector3(0.6, 0.6, 0.6)
## Rate loop bandwidth for steering and stops, 1/s. Higher = snappier, more chatter.
@export var rate_gain: float = 7.5
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
@export_range(0.0, 1.0) var torque_fraction: float = 0.85
## Torque authority auto-rotation (and attitude hold) may use.
@export_range(0.0, 1.0) var auto_rotate_torque_fraction: float = 0.85
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
## Allocator torque priority while steering or stopping a turn (< 0 = allocator default).
## Low keeps the force clean: hard turns otherwise buy torque with off-centre thrust,
## which shoves the suit sideways. AMBAC still adds its torque on top.
@export var steer_torque_priority: float = 0.35
## Share of the force capability given up while steering or stopping a turn, so the
## thrusters have room left to make torque.
@export_range(0.0, 0.9) var steer_force_reserve: float = 0.3
## Same while a released turn is being stopped: the stop comes first, for the moment it takes.
@export_range(0.0, 0.9) var stop_force_reserve: float = 0.6
## Allocator torque priority while realigning to rest (< 0 = allocator default).
## Lower keeps the suit's braking push clean at the cost of a slower return.
@export var realign_torque_priority: float = 0.5

@export_group("Boost")
## While boosting (or hard braking, outside precision): rate limits are multiplied by
## this, and torque/thrust limits open fully.
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
## Coupled: the brake is always on, so the suit stops on the axes the stick isn't
## holding instead of coasting. A hard brake still has to be asked for.
@export var coupled: bool = false

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
## Analog sticks (PilotCommand.analog_thrust): one exponential curve from 0 up to
## analog_accel_g at analog_full_boost_onset; above cruise_accel_g it counts as boosting.
@export var analog_accel_g: float = 7.0
## How bent the curve is: 0 = straight, 3 = half travel gives ~1/6 of analog_accel_g.
@export_range(0.0, 8.0) var analog_curve: float = 3.0
## Past this demand (after the stick's deadzone and expo: 0.92 is ~95% of the travel) the
## stick eases from boost into full boost (no acceleration cap, auto-rotation opening to the
## solver's full range), reached at the stops.
@export_range(0.1, 1.0) var analog_full_boost_onset: float = 0.92
## Precision mode's speed loop gain, (m/s²) per (m/s) of error.
@export var velocity_gain: float = 0.8
## Braking: (m/s²) per (m/s) of the motion being stopped, up to stop_accel_g (a combat
## suit stops at once), limited by what the attitude can deliver. Precision mode brakes
## at precision_accel_g.
@export var brake_gain: float = 2.5
@export var stop_accel_g: float = 6.0

@export_group("Dodge")
## How long a kick pushes at least, s (held, it goes on until the kick tank is dry).
@export var dodge_time: float = 0.3
## Acceleration cap of a kick, G (the pilot's limit). 0 = everything the thrusters give.
@export var dodge_accel_g: float = 0.0
## Stick deflection that gives a kick its direction.
@export_range(0.0, 1.0) var dodge_min_stick: float = 0.3
## A press without a direction waits this long for the stick, then is dropped, s.
@export var dodge_buffer_time: float = 0.15

@export_group("Drift hold")
## Cancels motion the pilot didn't ask for (force spilled by hard turns, thruster lag)
## on the axes the stick isn't holding, against the velocity the commands alone give.
@export var drift_hold: bool = true
## (m/s²) per (m/s) of drift, up to cruise_accel_g (precision_accel_g in precision).
@export var drift_gain: float = 3.0
## Drift above this is taken as real (a collision, a new reference frame), m/s.
@export var drift_max_error: float = 3.0

var _initialized := false
var _pilot := Quaternion.IDENTITY    ## Pilot frame orientation (global)
var _offset := Quaternion.IDENTITY   ## Body relative to pilot frame
var _offset_target_r := Vector3.ZERO ## Smoothed solver target, rotation vector (pilot frame)
var _offset_rate := Vector3.ZERO     ## Offset swing rate, pilot frame (rad/s), fed forward
var _offset_vel := Vector3.ZERO      ## Swing velocity of the commanded offset (rotation vector, rad/s)
var _auto_rotating := false   ## Solver engaged this tick (force must stay clean)
var _recover := 0.0           ## 0..1, how far the body lags the auto-rotation target
var _brake := 0.0             ## 0..1, the hold is braking into its target (gets full torque)
var _force_load := 0.0        ## 0..1, force demand as a share of the capability along it
# Per pilot axis masks (pitch, yaw, roll), 1 = set:
var _active := Vector3.ZERO          ## Steered by the stick
var _capture := Vector3.ZERO         ## Steered, or released and still braking
var _locked := Vector3.ZERO          ## Cockpit locked to the body
var _newly_locked := Vector3.ZERO
var _release_timer := Vector3.ZERO
var _turn_sign := Vector3.ZERO       ## Direction each steered axis was turning
var _analog := false                 ## Stick travel sets the acceleration this tick
var _analog_boost := false           ## ...and asks for more than cruise
var _full_share := 0.0               ## ...and this far (0..1) into full boost
var _dodge_wait := 0.0               ## A dodge press waiting for a direction, s left
var _dodge_left := 0.0               ## Kick in progress, s left
var _dodge_dir := Vector3.ZERO       ## Its direction (global)
var _dodge_holding := false          ## Its button is still held since the press
var _last_boost := false             ## For the HUD label
var _last_boost_full := false
var _last_brake := false
var _last_brake_full := false
var _thruster_limit := Vector3.INF   ## Thrusters' share of this tick's torque limit
var _stick := Vector3.ZERO           ## Rotation demand after horizon-lock shaping
var _horizon_up := Vector3.UP        ## Global "up" the horizon lock levels to
var _display_up := Vector3.UP        ## HUD's up: re-levelled by a roll like _horizon_up, keeping pitch
var _manual_roll := false            ## Pilot is rolling (sets a new horizon)
var _v_expect := Vector3.ZERO        ## Velocity the commands alone would give (global)
var _intent_accel := Vector3.ZERO    ## Last tick's commanded acceleration (global)
var _drift_frame := -10              ## Physics frame of the last drift update


func reset() -> void:
	_initialized = false


func get_pilot_offset() -> Quaternion:
	return _offset


func get_pilot_orientation() -> Variant:
	return _pilot


## The HUD's horizon, not _horizon_up: a roll resets that one to the cockpit's up
## (so yaw stays flat), which would also reset the displayed pitch.
func get_horizon_up() -> Variant:
	return _display_up if horizon_lock and _initialized else null


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
		_display_up = _horizon_up
		_manual_roll = false
	if command.toggle_precision:
		precision = not precision
	if command.toggle_coupled:
		coupled = not coupled
	if command.toggle_rotation_mode:
		rotation_mode = ((rotation_mode + 1) % RotationMode.size()) as RotationMode
		_pilot = body_q * _offset.inverse()
	if command.toggle_horizon_lock:
		horizon_lock = not horizon_lock
		_horizon_up = _pilot * Vector3.UP
		_display_up = _horizon_up
		_manual_roll = false

	_analog = command.analog_thrust and not (precision or command.boost or command.boost_full)
	var amount := minf(command.translation.length(), 1.0)
	# A little hysteresis, so a stick resting at the onset doesn't flicker the boost.
	var probe := amount + (0.05 if _analog_boost else 0.0)
	_analog_boost = _analog and _analog_curve_g(probe) > cruise_accel_g
	_full_share = clampf((amount - analog_full_boost_onset) / maxf(1.0 - analog_full_boost_onset, 0.01),
			0.0, 1.0) if _analog_boost else 0.0
	command.boost = command.boost or command.boost_full or _analog_boost
	_update_dodge(state, command)
	_last_boost = command.boost or _dodge_left > 0.0
	_last_boost_full = command.boost_full or _full_share > 0.0 or _dodge_left > 0.0
	command.brake = command.brake or command.brake_full
	_last_brake = command.brake   # the HUD's brake cue shows the pilot's own braking
	command.brake = command.brake or coupled
	_last_brake_full = command.brake_full
	_stick = _horizon_stick(command)
	_update_locks(state, command)
	_update_pilot(body_q)
	_level_horizon(state.delta)
	var force_world := _translation_force_world(state, command)
	var drift_force := _drift_correction(state, command, force_world)
	if _dodge_left > 0.0:
		drift_force = Vector3.ZERO
	_update_offset(state, force_world, command)
	var wanted := state.to_local(force_world + drift_force)
	_force_load = 0.0
	if wanted.length() > 1.0:
		_force_load = minf(wanted.length() / maxf(state.force_capability(wanted.normalized()), 1.0), 1.0)
	var torque := _rotation_torque(state, command, body_q)
	# Attitude needs thrust too: a push at full capability leaves the allocator nothing
	# to turn with, so the force gives way while the pilot steers or a turn is stopping.
	var reserve := stop_force_reserve if _is_stopping() \
			else (steer_force_reserve if _locked != Vector3.ZERO else 0.0)
	if _dodge_left > 0.0:
		reserve = 0.0
	var force_body := clamp_to_capability(state.to_local(force_world + drift_force), state,
			1.0 - reserve)
	var wrench := Wrench.new(force_body, torque)
	wrench.thruster_torque_limit = _thruster_limit
	wrench.burst = _dodge_left > 0.0
	# Stopping a turn or braking into a target always wins: it matters more than a clean push.
	if _is_stopping():
		wrench.torque_priority = recover_torque_priority
	elif _locked != Vector3.ZERO:
		wrench.torque_priority = steer_torque_priority
	else:
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
	if coupled:
		labels.append("COUPLED")
	# Boost and brake show on the thrust cue and the flight path marker instead.
	if precision and not _last_boost:
		labels.append("PRECISION")
	return labels


func get_boost_level() -> int:
	return 2 if _last_boost_full else (1 if _last_boost else 0)


## A kick in progress.
func is_dodging() -> bool:
	return _dodge_left > 0.0


## A press starts a kick along the stick (pilot frame) once the stick gives a direction,
## within dodge_buffer_time, and only with the kick tank ready. It lasts dodge_time, and
## past that for as long as the button stays held, ending when the kick tank runs dry.
## While held the stick steers it; let go, it keeps its last direction.
func _update_dodge(state: FlightState, command: PilotCommand) -> void:
	if command.dodge:
		_dodge_wait = dodge_buffer_time
	var stick := command.translation
	if _dodge_left > 0.0:
		_dodge_holding = _dodge_holding and command.dodge_held
		_dodge_left = maxf(_dodge_left - state.delta, 0.0)
		if _dodge_holding:
			_dodge_left = maxf(_dodge_left, state.delta)
			if stick.length() >= dodge_min_stick:
				_dodge_dir = (_pilot * stick).normalized()
		if state.burst_reserve <= 0.0:
			_dodge_left = 0.0
		if _dodge_left > 0.0:
			return
	if _dodge_wait <= 0.0:
		return
	if stick.length() >= dodge_min_stick and state.burst_ready:
		_dodge_dir = (_pilot * stick).normalized()
		_dodge_left = dodge_time
		_dodge_holding = command.dodge_held
		_dodge_wait = 0.0
	else:
		_dodge_wait -= state.delta


func get_brake_level() -> int:
	return 2 if _last_brake_full else (1 if _last_brake else 0)


## Auto-rotation limit for this tick, deg (0 = off).
func _offset_limit_deg(command: PilotCommand) -> float:
	if command.boost_full or (command.brake_full and not precision):
		return attitude_solver.max_offset_deg
	if command.boost:
		return lerpf(boost_max_offset_deg, attitude_solver.max_offset_deg, _full_share)
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
		_roll_display_up()
	if _manual_roll:
		_horizon_up = _pilot * Vector3.UP
		_roll_display_up()
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


## Turns the HUD's horizon about the pilot's forward until it carries no bank, keeping
## its pitch.
func _roll_display_up() -> void:
	var up_p := _pilot.inverse() * _display_up
	var y := sqrt(maxf(1.0 - up_p.z * up_p.z, 0.0))
	_display_up = _pilot * Vector3(0.0, -y if up_p.y < 0.0 else y, up_p.z)


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
	if _dodge_left > 0.0:
		# A kick is over before a swing could help: it pushes from the attitude it found.
		_offset_target_r = r_cur
		_offset_vel = Vector3.ZERO
		return
	var share := steer_auto_rotate_share
	if _locked == Vector3.ONE and share <= 0.0:
		_offset_target_r = r_cur
		return
	var free := Vector3.ONE - _locked
	# Axes whose offset may not move at all, and each axis's share of the swing rate.
	var frozen := _locked if share <= 0.0 else Vector3.ZERO
	var moving := Vector3.ONE - frozen
	# While any axis is steered the whole swing slows, not just that axis: a full-rate
	# swing on the others takes the torque the turn (and its stop) needs.
	var speed := Vector3.ONE if _locked == Vector3.ZERO else free * steer_free_swing_share + _locked * share
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
					attitude_solver.solve(state, force_pilot, _offset, frozen, limit))
			_auto_rotating = true
		else:
			# Nothing needs the offset: aim the free axes straight back at the cockpit
			# and let the time-optimal hold bring the body home in one motion.
			_offset = AttitudeOffsetSolver.from_rotation_vector(r_target)
			_offset_target_r = r_target
			_offset_vel = Vector3.ZERO
			return
	r_target = r_target * moving + r_cur * frozen
	# Low-pass the target first so the body eases into (and out of) a new attitude.
	_offset_target_r = _offset_target_r * moving + r_cur * frozen
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
	var remaining := (_offset_target_r - r_cur) * moving
	var to_body := func(v: Vector3) -> Vector3: return state.to_local(_pilot * v)
	var to_pilot := func(v: Vector3) -> Vector3: return _pilot.inverse() * state.to_global(v)
	var v_want: Vector3 = to_pilot.call(_braking_rate(state, to_body.call(remaining), swing_braking_margin))
	v_want = (v_want * moving).limit_length(slew) * speed
	_offset_vel *= moving
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
	# A hard brake snap-turns like a boost, to swing the big thrusters into the stop.
	var fast_turn := command.boost or (command.brake_full and not precision)
	if fast_turn:
		max_rate *= boost_rate_multiplier
	elif precision:
		max_rate *= precision_rate_multiplier
	var gain := rate_gain * (boost_rate_gain_multiplier if fast_turn else 1.0)
	var inertia := state.inertia_local
	var gyro := omega.cross(inertia * omega)
	var steering := _active != Vector3.ZERO
	# Never turn faster than the suit can stop again within stop_time: past that, letting
	# go of the stick leaves the view spinning on for a second.
	if stop_time > 0.0:
		var to_body := Quaternion.IDENTITY if rotation_mode != RotationMode.ATTITUDE_HOLD \
				else (_pilot.inverse() * body_q).inverse()
		for k in 3:
			var axis := Vector3.ZERO
			axis[k] = 1.0
			max_rate[k] = minf(max_rate[k], _max_alpha(state, to_body * axis, 1.0) * braking_margin
					* lerpf(1.0, loaded_torque_share[k], _force_load) * stop_time)

	if rotation_mode != RotationMode.ATTITUDE_HOLD:
		var rate_cmd := _stick * max_rate if steering else Vector3.ZERO
		if not steering:
			gain *= hold_rate_gain_multiplier
		var fraction := 1.0 if fast_turn and steering else torque_fraction
		_thruster_limit = state.max_torque * fraction
		var limit := _thruster_limit + state.ambac_torque
		return scale_to_box(inertia * ((rate_cmd - omega) * gain) + gyro, limit)

	# Everything below is about the pilot's axes. Locked axes: the stick commands the
	# rate (0 while braking a released turn). Free axes: track pilot · offset. Both
	# get the offset swing fed forward so fast swings don't lag.
	var body_to_pilot := _pilot.inverse() * body_q
	var pilot_to_body := body_to_pilot.inverse()
	var free := Vector3.ONE - _locked
	var rate_p := _stick * max_rate * _active + _offset_rate
	if free != Vector3.ZERO:
		var err_q := AttitudeOffsetSolver.shortest((_pilot * _offset) * body_q.inverse())
		# Not get_axis() * get_angle(): that axis isn't normalised below ~0.5°, which left
		# the hold with almost no error to correct until the body had drifted that far.
		var err_p := (_pilot.inverse() * AttitudeOffsetSolver.to_rotation_vector(err_q)) * free
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
			gain_p[k] = auto_rotate_rate_gain * (boost_rate_gain_multiplier if fast_turn else 1.0)
		else:
			gain_p[k] = gain * hold_rate_gain_multiplier
	var alpha_p := (rate_p - omega_p) * gain_p

	# Locked and free axes get separate torque budgets: a boosted turn or a stop may
	# use it all, while auto-rotation stays gentle so it never spills force. The limbs'
	# torque comes on top of both (it moves no thrusters, so it's always clean).
	var stopping := _is_stopping()
	var lock_fraction := 1.0 if stopping or (fast_turn and steering) else torque_fraction
	var free_fraction := lerpf(_auto_fraction() if _auto_rotating else torque_fraction, 1.0, _brake)
	var lock_thrust := state.max_torque * lock_fraction
	var free_thrust := state.max_torque * free_fraction
	var lock_limit := lock_thrust + state.ambac_torque
	var free_limit := free_thrust + state.ambac_torque
	var torque_lock := scale_to_box(inertia * (pilot_to_body * (alpha_p * _locked)), lock_limit)
	var torque_free := scale_to_box(inertia * (pilot_to_body * (alpha_p * free)), free_limit)
	_thruster_limit = lock_thrust if _locked != Vector3.ZERO else free_thrust
	if free != Vector3.ZERO:
		_thruster_limit = _thruster_limit.max(free_thrust)
	var limit := _thruster_limit + state.ambac_torque
	# The pilot's own turn (and its stop) comes first; holding the other axes gets the
	# room that's left, so a saturated hold can't water down a stop.
	var first := scale_to_box(torque_lock + gyro, limit)
	return first + torque_free * _room_for(first, torque_free, limit)


## Largest share (0..1) of `extra` that still fits inside ±limit on top of `base`.
static func _room_for(base: Vector3, extra: Vector3, limit: Vector3) -> float:
	var share := 1.0
	for k in 3:
		if absf(extra[k]) < 1e-6:
			continue
		var room := (limit[k] - base[k]) if extra[k] > 0.0 else (limit[k] + base[k])
		share = minf(share, maxf(room, 0.0) / absf(extra[k]))
	return share


## A released turn is still being braked on some axis.
func _is_stopping() -> bool:
	return (_capture - _active).max(Vector3.ZERO) != Vector3.ZERO


func _auto_fraction() -> float:
	return lerpf(auto_rotate_torque_fraction, torque_fraction, _recover)


## Angular acceleration the torque budget allows about a body axis, rad/s² (INF if none).
func _max_alpha(state: FlightState, axis: Vector3, fraction: float = -1.0) -> float:
	if fraction < 0.0:
		fraction = _auto_fraction() if _auto_rotating else torque_fraction
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


## Force (global) that pushes out drift on the pilot axes the stick isn't holding.
## The expected velocity integrates only the pilot's intent (clamped to capability),
## so whatever else moved the suit shows up as the error.
func _drift_correction(state: FlightState, command: PilotCommand, intent_world: Vector3) -> Vector3:
	var v := state.linear_velocity
	var frame := Engine.get_physics_frames()
	var continuous := frame == _drift_frame + 1
	_drift_frame = frame
	var active := drift_hold and not command.brake
	if active and continuous:
		_v_expect += _intent_accel * state.delta
	else:
		_v_expect = v
	_intent_accel = state.to_global(clamp_to_capability(
			state.to_local(intent_world), state, 1.0)) / state.mass
	if not active:
		return Vector3.ZERO
	var err_p := _pilot.inverse() * (v - _v_expect)
	for k in 3:
		if absf(command.translation[k]) > stick_deadzone:
			err_p[k] = 0.0
	if err_p.length() > drift_max_error:
		_v_expect = v
		return Vector3.ZERO
	var err := _pilot * err_p
	_v_expect = v - err  # held axes: their speed is wanted, so it's expected
	var gentle := precision and not command.boost
	var limit := (precision_accel_g if gentle else cruise_accel_g) * FlightComputer.G0
	return (-err * drift_gain).limit_length(limit) * state.mass


## Acceleration for a stick deflection of `amount` (0..1). Keys and buttons scale the
## mode's limit; an analog stick follows the curve up to analog_accel_g, then eases into
## full boost (`full`, everything) past the full-boost onset.
func _push_accel(amount: float, accel_limit: float, full: float) -> float:
	if not _analog:
		return amount * accel_limit
	var boost := analog_accel_g * FlightComputer.G0
	if amount <= analog_full_boost_onset:
		return _analog_curve_g(amount) * FlightComputer.G0
	var t := (amount - analog_full_boost_onset) / maxf(1.0 - analog_full_boost_onset, 0.01)
	return lerpf(boost, maxf(full, boost), t)


## The stick's curve below full boost, G: 0 at rest, analog_accel_g at the full-boost onset.
func _analog_curve_g(amount: float) -> float:
	var s := clampf(amount / analog_full_boost_onset, 0.0, 1.0)
	if analog_curve < 0.01:
		return s * analog_accel_g
	return analog_accel_g * (exp(analog_curve * s) - 1.0) / (exp(analog_curve) - 1.0)


func _translation_force_world(state: FlightState, command: PilotCommand) -> Vector3:
	if _dodge_left > 0.0:
		var kick := _total_thrust(state) / state.mass
		if dodge_accel_g > 0.0:
			kick = minf(kick, dodge_accel_g * FlightComputer.G0)
		return _dodge_dir * kick * state.mass
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
		var push_accel := _push_accel(minf(amount, 1.0), accel_limit, _total_thrust(state) / state.mass)
		if gentle:
			push_accel = clampf((precision_speed * minf(amount, 1.0) - v.dot(dir)) * velocity_gain,
					0.0, push_accel)
		push = dir * push_accel
	if not command.brake:
		return push * state.mass
	# Brake the pilot axes the stick isn't holding, and held axes still moving against
	# the stick (so reversing brakes hard first, then pushes).
	var v_p := _pilot.inverse() * v
	for k in 3:
		var s := command.translation[k]
		if absf(s) > stick_deadzone and v_p[k] * s > 0.0:
			v_p[k] = 0.0
	var v_free := _pilot * v_p
	var brake_limit := (precision_accel_g if gentle else stop_accel_g) * FlightComputer.G0
	if command.brake_full and not gentle:
		brake_limit = maxf(brake_limit, _total_thrust(state) / state.mass)  # hard brake: no cap
	var brake := (-v_free * brake_gain).limit_length(brake_limit)
	return (push + brake).limit_length(maxf(accel_limit, brake_limit)) * state.mass
