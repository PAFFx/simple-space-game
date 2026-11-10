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
## Fraction of torque authority the FCS may request.
@export_range(0.0, 1.0) var torque_fraction: float = 0.6
## On stick release: rate-loop gain multiplier and full torque, so rotation stops at once.
@export var stop_gain_multiplier: float = 2.0

@export_group("Boost")
## While boosting: rate limits are multiplied by this, and torque/thrust limits open fully.
@export var boost_rate_multiplier: float = 1.7
@export var boost_rate_gain_multiplier: float = 1.5
@export var boost_speed_multiplier: float = 2.0

@export_group("Translation")
## Acceleration limit, same in every direction, so the suit moves in a straight
## line toward the command. Auto-rotation finds the attitude that can deliver it.
@export var cruise_accel_g: float = 0.35
@export var boost_accel_g: float = 2.0
## Velocity demanded at full stick in VELOCITY_HOLD, m/s.
@export var max_command_speed: float = 60.0
## Velocity loop gain, (m/s²) per (m/s) of error.
@export var velocity_gain: float = 0.8

var _initialized := false
var _pilot := Quaternion.IDENTITY    ## Pilot frame orientation (global)
var _offset := Quaternion.IDENTITY   ## Body relative to pilot frame
var _offset_target := Quaternion.IDENTITY
var _stick_active := false
var _capturing := false


func reset() -> void:
	_initialized = false


func get_pilot_offset() -> Quaternion:
	return _offset


func get_pilot_orientation() -> Variant:
	return _pilot


func compute(state: FlightState, command: PilotCommand) -> Wrench:
	var body_q := state.basis.get_rotation_quaternion()
	if not _initialized:
		_initialized = true
		_offset = Quaternion.IDENTITY
		_pilot = body_q
	if command.toggle_translation_mode:
		translation_mode = ((translation_mode + 1) % TranslationMode.size()) as TranslationMode
	if command.toggle_rotation_mode:
		rotation_mode = ((rotation_mode + 1) % RotationMode.size()) as RotationMode
		_pilot = body_q * _offset.inverse()

	_stick_active = command.rotation.length() > stick_deadzone
	var force_world := _translation_force_world(state, command)
	_update_offset(state, force_world, command)
	var torque := _rotation_torque(state, command, body_q)
	var force_body := clamp_to_capability(state.to_local(force_world), state, 1.0)
	return Wrench.new(force_body, torque)


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
	return rotation_mode == RotationMode.ATTITUDE_HOLD and not _stick_active and not _capturing


func _update_offset(state: FlightState, force_world: Vector3, command: PilotCommand) -> void:
	var target := Quaternion.IDENTITY
	var slew := deg_to_rad(60.0)
	var smoothing := 0.0
	if attitude_solver != null:
		slew = deg_to_rad(attitude_solver.slew_rate_deg)
		smoothing = attitude_solver.smoothing_time
		# While the pilot steers (or the turn is still braking) the suit and cockpit
		# move as one rigid unit: keep the offset exactly as it is.
		if _stick_active or _capturing:
			return
		var translating := command.translation.length() > stick_deadzone
		var wanted := command.boost if auto_rotate_on_boost_only else (command.boost or translating)
		if rotation_mode == RotationMode.ATTITUDE_HOLD and state.allow_attitude_offset and wanted:
			var force_pilot := _pilot.inverse() * force_world
			target = attitude_solver.solve(state, force_pilot, _offset)
	# Low-pass the target first so the body eases into (and out of) a new attitude.
	if smoothing > 0.0:
		_offset_target = _offset_target.slerp(target, 1.0 - exp(-state.delta / smoothing))
		target = _offset_target
	var angle := _offset.angle_to(target)
	if angle > 1e-5:
		_offset = _offset.slerp(target, minf(1.0, slew * state.delta / angle)).normalized()


func _rotation_torque(state: FlightState, command: PilotCommand, body_q: Quaternion) -> Vector3:
	var omega := state.local_angular_velocity
	var max_rate := max_rate_deg * (PI / 180.0) * (boost_rate_multiplier if command.boost else 1.0)
	var stick_rate := command.rotation * max_rate if _stick_active else Vector3.ZERO
	var rate_cmd := stick_rate

	if rotation_mode == RotationMode.ATTITUDE_HOLD:
		if _stick_active or _capturing:
			# Steering, or braking the turn after release: the cockpit is locked rigidly
			# to the suit (pilot = body · offset⁻¹), so it never leads or lags the hull.
			# The stick commands the rate about the pilot's axes directly.
			_capturing = _stick_active or omega.length() >= deg_to_rad(hold_capture_rate_deg)
			_pilot = body_q * _offset.inverse()
			rate_cmd = state.to_local(_pilot * stick_rate)
		else:
			# Hold: track pilot · offset (the offset may be moving for thrust vectoring).
			var err_q := (_pilot * _offset) * body_q.inverse()
			if err_q.w < 0.0:
				err_q = -err_q
			var err := state.to_local(Vector3(err_q.x, err_q.y, err_q.z) * 2.0)
			rate_cmd = (err * attitude_gain).clamp(-max_rate * 1.2, max_rate * 1.2)
	else:
		_offset = Quaternion.IDENTITY
		_pilot = body_q

	var stopping := _capturing and not _stick_active
	var gain := rate_gain * (boost_rate_gain_multiplier if command.boost else 1.0)
	if stopping:
		gain *= stop_gain_multiplier
	var alpha := (rate_cmd - omega) * gain
	var inertia := state.inertia_local
	var torque := inertia * alpha + omega.cross(inertia * omega)
	var limit := state.max_torque * (1.0 if command.boost or stopping else torque_fraction)
	return torque.clamp(-limit, limit)


func _translation_force_world(state: FlightState, command: PilotCommand) -> Vector3:
	var stick_world := _pilot * command.translation
	var accel_limit := (boost_accel_g if command.boost else cruise_accel_g) * FlightComputer.G0
	if translation_mode == TranslationMode.NEWTONIAN:
		return stick_world.limit_length(1.0) * accel_limit * state.mass

	var speed := max_command_speed * (boost_speed_multiplier if command.boost else 1.0)
	var v_error := stick_world * speed - state.linear_velocity
	return (v_error * velocity_gain).limit_length(accel_limit) * state.mass
