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

# --- Weapons (read by FireControl) ---

## Vulcans: pods open and spun up (trigger first detent), firing (second detent).
var vulcan_ready := false
var vulcan_fire := false
## Fire the selected weapon (weapon release), held.
var fire_main := false
## One-shots: lock the contact under the cursor (never unlocks); unlock (or close the zoom
## window first); step the lock to the next contact by azimuth (1 = right, -1 = left);
## open the zoom window, or cycle its level.
var lock_commit := false
var unlock := false
var target_cycle := 0
var zoom := false
## Hold the shield toward where the pilot looks.
var shield_block := false
## One-shot: weapon select hat direction (FireControl.Hat), -1 = none.
var weapon_select := -1
## One-shot: 1 = master arm on, -1 = off, 2 = toggle, 0 = none.
var master_arm := 0
## One-shot: master mode to enter (FireControl.MasterMode), -1 = none.
var master_mode := -1
## One-shot: switch the sensor of interest (HUD cursor / pilot's view).
var soi_cycle := false
## HUD cursor slew, each in [-1, 1]: x = right, y = up.
var cursor_slew := Vector2.ZERO
