class_name PilotCommand
extends RefCounted

## One frame of pilot intent, independent of the input device (keyboard, HOTAS, AI).
## Axes use the vehicle's local frame: x = right, y = up, z = back (forward is -Z).

## Translation demand per local axis, each in [-1, 1]. Forward = negative z.
var translation := Vector3.ZERO

## Rotation-rate demand about each local axis, each in [-1, 1], right-hand rule:
## +x = pitch up, +y = yaw left, +z = roll left.
var rotation := Vector3.ZERO

## Allow full thrust instead of the cruise limit.
var boost := false
## Boost with full auto-rotation (Shift double-tapped and held). Implies boost.
var boost_full := false

## The translation comes from an analog stick, whose travel is the throttle: past the
## control law's onset it ramps from the cruise limit into boost, with no boost button.
var analog_thrust := false

## Brake the motion on the axes the translation doesn't hold, or holds against the
## current motion (Ctrl held). Released keys
## otherwise coast. brake_full (Ctrl double-tapped and held) stops harder, turning the
## suit further to use its big thrusters, like a boost.
var brake := false
var brake_full := false

## One-shot requests, true only on the frame the button was pressed.
var toggle_rotation_mode := false
var toggle_precision := false
var toggle_horizon_lock := false
var toggle_coupled := false
