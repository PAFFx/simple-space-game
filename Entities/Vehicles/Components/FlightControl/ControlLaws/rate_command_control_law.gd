class_name RateCommandControlLaw
extends ControlLaw

## Fly-by-wire law, in the spirit of modern fighter FCS:
##
## Rotation — the stick commands an angular RATE, not a torque. Releasing the
##   stick brings rotation to a stop; in ATTITUDE_HOLD the attitude is then
##   captured and held against disturbances (e.g. asymmetric thrust).
## Translation — NEWTONIAN: stick = thrust demand, the suit coasts when released.
##   VELOCITY_HOLD: stick = desired velocity in the body frame relative to the
##   reference frame; releasing the stick brings the suit to relative rest.

enum TranslationMode { NEWTONIAN, VELOCITY_HOLD }
enum RotationMode { RATE_DAMP, ATTITUDE_HOLD }

@export var translation_mode: TranslationMode = TranslationMode.NEWTONIAN
@export var rotation_mode: RotationMode = RotationMode.ATTITUDE_HOLD

@export_group("Rotation")
## Max commanded rate at full stick (pitch, yaw, roll), deg/s.
@export var max_rate_deg := Vector3(40.0, 35.0, 60.0)
## Rate loop bandwidth, 1/s. Higher = snappier, more thruster chatter.
@export var rate_gain: float = 3.0
## Attitude loop gain, (rad/s) per rad of error.
@export var attitude_gain: float = 1.2
## Attitude is captured once the body rate drops below this, deg/s.
@export var hold_capture_rate_deg: float = 2.0
@export var stick_deadzone: float = 0.04
## Fraction of torque authority the FCS may request.
@export_range(0.0, 1.0) var torque_fraction: float = 0.8

@export_group("Translation")
@export_range(0.0, 1.0) var cruise_thrust_fraction: float = 0.5
## Velocity demanded at full stick in VELOCITY_HOLD, m/s.
@export var max_command_speed: float = 60.0
## Velocity loop gain, (m/s²) per (m/s) of error.
@export var velocity_gain: float = 0.8

var _hold_active := false
var _hold_orientation := Quaternion.IDENTITY


func reset() -> void:
	_hold_active = false


func compute(state: FlightState, command: PilotCommand) -> Wrench:
	if command.toggle_translation_mode:
		translation_mode = ((translation_mode + 1) % TranslationMode.size()) as TranslationMode
	if command.toggle_rotation_mode:
		rotation_mode = ((rotation_mode + 1) % RotationMode.size()) as RotationMode
		_hold_active = false
	return Wrench.new(_translation_force(state, command), _rotation_torque(state, command))


func get_mode_labels() -> PackedStringArray:
	var trans := "TRANS NEWTON" if translation_mode == TranslationMode.NEWTONIAN else "TRANS V-HOLD"
	var rot := "ROT RATE"
	if rotation_mode == RotationMode.ATTITUDE_HOLD:
		rot = "ROT ATT-HOLD" + (" ●" if _hold_active else "")
	return PackedStringArray([trans, rot])


func is_holding_attitude() -> bool:
	return _hold_active


func _rotation_torque(state: FlightState, command: PilotCommand) -> Vector3:
	var omega := state.local_angular_velocity
	var max_rate := max_rate_deg * (PI / 180.0)
	var rate_cmd := Vector3.ZERO

	if command.rotation.length() > stick_deadzone:
		_hold_active = false
		rate_cmd = command.rotation * max_rate
	elif rotation_mode == RotationMode.ATTITUDE_HOLD:
		var current := state.basis.get_rotation_quaternion()
		if not _hold_active and omega.length() < deg_to_rad(hold_capture_rate_deg):
			_hold_active = true
			_hold_orientation = current
		if _hold_active:
			var q_err := _hold_orientation * current.inverse()
			if q_err.w < 0.0:
				q_err = -q_err
			# Small-angle rotation vector of the error, global → body frame.
			var err := state.to_local(Vector3(q_err.x, q_err.y, q_err.z) * 2.0)
			rate_cmd = (err * attitude_gain).clamp(-max_rate, max_rate)

	var alpha := (rate_cmd - omega) * rate_gain
	var inertia := state.inertia_local
	var torque := inertia * alpha + omega.cross(inertia * omega)
	var limit := state.max_torque * torque_fraction
	return torque.clamp(-limit, limit)


func _translation_force(state: FlightState, command: PilotCommand) -> Vector3:
	var fraction := 1.0 if command.boost else cruise_thrust_fraction
	if translation_mode == TranslationMode.NEWTONIAN:
		return scale_by_authority(command.translation, state) * fraction

	var speed := max_command_speed * (2.0 if command.boost else 1.0)
	var v_error := command.translation * speed - state.local_linear_velocity
	var force := v_error * velocity_gain * state.mass
	return clamp_to_authority(force, state, fraction)
