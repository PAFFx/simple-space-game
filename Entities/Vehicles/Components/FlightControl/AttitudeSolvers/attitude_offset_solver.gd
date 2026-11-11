@abstract
class_name AttitudeOffsetSolver
extends Resource

## Chooses how far to turn the suit's body away from the pilot frame so a force
## demand can be met by its strongest thrusters (e.g. swing the backpack
## mains toward the direction of travel). The cockpit counter-rotates by the
## same offset, so the pilot's view stays put.

## Limit on the body ↔ pilot frame angle. Keep it below the cockpit gimbal's
## soft knee so swings (and their overshoot) never reach the gimbal limit.
@export var max_offset_deg: float = 60.0
## Per-axis limits of the offset (pitch, yaw, roll), deg. Yaw is kept tiny so the
## suit never swings sideways under the pilot; sideways moves are done by rolling.
@export var axis_limit_deg := Vector3(60.0, 3.0, 60.0)
## How fast the offset may change, deg/s.
@export var slew_rate_deg: float = 120.0
## Low-pass on the solver's target, s. Smooths starting and stopping a swing.
@export var smoothing_time: float = 0.1


## Override: target offset (body = pilot · offset) for a force demand given in the
## pilot frame. `current` is the offset in use, for warm starts and smoothness.
## `locked` is a per pilot axis mask (pitch, yaw, roll; 1 = locked): those
## rotation-vector components must stay as they are in `current`.
## `max_angle_deg` caps the offset below max_offset_deg (movement modes use it).
@abstract func solve(state: FlightState, force_pilot: Vector3, current: Quaternion,
		locked: Vector3, max_angle_deg: float) -> Quaternion


## The same rotation the short way round (q and −q are the same rotation; −q's
## angle is 360° minus q's, which makes clamps and slerps flip).
static func shortest(q: Quaternion) -> Quaternion:
	return -q if q.w < 0.0 else q


## Rotation vector (axis · angle, short way round) of a rotation. Accurate for tiny
## per-tick rotations too (Quaternion.get_axis() isn't normalised below ~0.5°).
static func to_rotation_vector(q: Quaternion) -> Vector3:
	q = shortest(q)
	var v := Vector3(q.x, q.y, q.z)
	var s := v.length()
	if s < 1e-9:
		return v * 2.0
	return v * (2.0 * atan2(s, q.w) / s)


static func from_rotation_vector(r: Vector3) -> Quaternion:
	var angle := r.length()
	return Quaternion(r / angle, angle) if angle > 1e-6 else Quaternion.IDENTITY


static func clamp_rotation(q: Quaternion, max_angle: float) -> Quaternion:
	q = shortest(q)
	var angle := q.get_angle()
	if angle <= max_angle or angle < 1e-6:
		return q
	return Quaternion(q.get_axis(), max_angle)
