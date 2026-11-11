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

## One-shot requests, true only on the frame the button was pressed.
var toggle_translation_mode := false
var toggle_rotation_mode := false
var toggle_precision := false
