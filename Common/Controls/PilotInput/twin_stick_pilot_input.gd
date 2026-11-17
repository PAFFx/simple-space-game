class_name TwinStickPilotInput
extends KeyboardPilotInput

## Keyboard plus two flight sticks flown tank style (found by name, see JoyDevices):
## Each pair of axes is mixed: the average translates, the difference turns.
##   fore/aft     average = forward / back, difference = yaw (right stick forward =
##                yaw left); on these sticks forward reads positive, see invert_surge
##   twist        average = up / down (clockwise = up), difference = pitch
##                (right clockwise against left counter-clockwise = nose up)
##   left/right   average = strafe, difference = roll (right stick right against left
##                stick left = roll right)
## invert_heave / invert_pitch flip the twist mixes, invert_roll the left/right one.
##
## Stick travel is the throttle (PilotCommand.analog_thrust), so there is no boost
## button, only full boost. The stick demand adds onto the keyboard's; with a stick
## missing this is plain keyboard input.
##
## Weapons (both sticks number their buttons alike). Right: trigger first detent opens the
## vulcans, second fires them (the first stays pressed under the second); weapon release
## fires the selected weapon; the 5-way hat selects weapons; master arm on / off; the
## Sensor Control Switch picks the sensor of interest (forward: HUD cursor / HMCS; aft,
## left, right: the centre, left, right display) and the mini-stick slews its cursor.
## Left: either trigger detent locks the contact under the cursor; the Target Management
## Switch (5-way hat) zooms (forward; locks first if nothing is), steps the lock right /
## left, unlocks (aft) and locks the nearest contact (depress); weapon release holds the
## shield up; NAV / DGFT / BVR.

@export_group("Devices")
@export var left_stick_name: String = "EVO L"
@export var right_stick_name: String = "EVO R"

@export_group("Axes")
@export var surge_axis: int = 1    ## Both sticks
## Stick forward reads positive on this axis (the VKB default), not negative.
@export var invert_surge: bool = true
@export var strafe_axis: int = 0   ## Both sticks
@export var heave_axis: int = 2    ## Both sticks' twist
@export var invert_heave: bool = false
@export var invert_pitch: bool = false
@export var invert_roll: bool = false

@export_group("Buttons")
@export var full_boost_button: int = 4   ## Right stick, hold
@export var brake_button: int = 21       ## Left stick, hold; double-tap and hold = hard brake
@export var coupled_button: int = 20     ## Left stick, toggles
@export var precision_button: int = 3    ## Left stick, toggles

@export_group("Weapons, right stick")
@export var vulcan_ready_button: int = 0
@export var vulcan_fire_button: int = 1
@export var weapon_release_button: int = 2
## Weapon select hat in FireControl.Hat order: forward, right, aft, left, depress.
@export var weapon_select_buttons := PackedInt32Array([15, 16, 17, 18, 19])
@export var master_arm_on_button: int = 24
@export var master_arm_off_button: int = 25
## Sensor Control Switch in FireControl.Scs order: forward, right, aft, left.
@export var scs_buttons := PackedInt32Array([10, 11, 12, 13])
@export var cursor_x_axis: int = 3
@export var cursor_y_axis: int = 4
@export var invert_cursor_y: bool = false
@export_range(0.0, 0.5) var cursor_deadzone: float = 0.12
@export_range(0.0, 1.0) var cursor_expo: float = 0.5

@export_group("Weapons, left stick")
## Trigger detents lock the contact under the cursor; TMS depress the nearest one.
@export var lock_buttons := PackedInt32Array([0, 1])
@export var lock_nearest_button: int = 19   ## TMS depress
@export var unlock_button: int = 17         ## TMS aft
@export var target_next_button: int = 16    ## TMS right
@export var target_prev_button: int = 18    ## TMS left
@export var zoom_button: int = 15           ## TMS forward
@export var shield_block_button: int = 2
## Master modes in FireControl.MasterMode order: NAV, DGFT, BVR.
@export var master_mode_buttons := PackedInt32Array([14, 10, 12])

@export_group("Response")
## Expo softens the centre: 0 = linear, 1 = fully cubic. Full travel is always full demand.
@export_range(0.0, 1.0) var translation_expo: float = 0.3
@export_range(0.0, 1.0) var rotation_expo: float = 0.4
@export_range(0.0, 0.5) var deadzone: float = 0.08
## Twist springs centre less precisely than the gimbal.
@export_range(0.0, 0.5) var twist_deadzone: float = 0.1
## On the differences, so moving both sticks unevenly doesn't turn the suit. They're
## on the half difference: one stick alone needs twice this travel.
@export_range(0.0, 0.5) var yaw_deadzone: float = 0.05
@export_range(0.0, 0.5) var pitch_deadzone: float = 0.06
@export_range(0.0, 0.5) var roll_deadzone: float = 0.12
## Smoothing of the shaped demand, s. 0 = off.
@export var smoothing: float = 0.04
## Median over this many ticks of each raw axis, against sensor spikes. 1 = off.
@export_range(1, 7, 2) var spike_filter_ticks: int = 3

var _left := -1
var _right := -1
var _history := {}                 ## device * 16 + axis → last raw samples
var _stick_translation := Vector3.ZERO
var _stick_rotation := Vector3.ZERO
var _precision_held := false
var _coupled_held := false
var _brake_held := false
var _brake_pressed_at := -INF      ## Time of the brake button's last press, s
var _brake_hard := false           ## Held since a double tap
var _was_down := {}                ## device * 64 + button → pressed last tick


func _ready() -> void:
	super._ready()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_find_sticks()


func has_sticks() -> bool:
	return _left >= 0 and _right >= 0


func poll_command() -> PilotCommand:
	var cmd := super.poll_command()
	if not has_sticks():
		return cmd
	var fore := -1.0 if invert_surge else 1.0
	var left_surge := _axis(_left, surge_axis) * fore
	var right_surge := _axis(_right, surge_axis) * fore
	var up := -1.0 if invert_heave else 1.0
	var nose_up := -1.0 if invert_pitch else 1.0
	var left_twist := _axis(_left, heave_axis)
	var right_twist := _axis(_right, heave_axis)
	var left_side := _axis(_left, strafe_axis)
	var right_side := _axis(_right, strafe_axis)
	var side := (left_side + right_side) * 0.5
	var roll_right := (right_side - left_side) * 0.5 * (-1.0 if invert_roll else 1.0)
	var target_t := Vector3(
		JoyDevices.shape(side, deadzone, translation_expo),
		JoyDevices.shape((left_twist + right_twist) * 0.5 * up, twist_deadzone, translation_expo),
		JoyDevices.shape((left_surge + right_surge) * 0.5, deadzone, translation_expo))
	# PilotCommand signs: +x = pitch up, +y = yaw left, +z = roll left.
	var target_r := Vector3(
		JoyDevices.shape((right_twist - left_twist) * 0.5 * nose_up, pitch_deadzone, rotation_expo),
		JoyDevices.shape((left_surge - right_surge) * 0.5, yaw_deadzone, rotation_expo),
		-JoyDevices.shape(roll_right, roll_deadzone, rotation_expo))
	var delta := get_physics_process_delta_time()
	var w := 1.0 if smoothing <= 0.0 else 1.0 - exp(-delta / smoothing)
	_stick_translation = _ease(_stick_translation, target_t, w)
	_stick_rotation = _ease(_stick_rotation, target_r, w)

	# The stick is the throttle only while the keys aren't pushing too.
	cmd.analog_thrust = _stick_translation != Vector3.ZERO and cmd.translation == Vector3.ZERO
	cmd.translation = (cmd.translation + _stick_translation).clamp(-Vector3.ONE, Vector3.ONE)
	cmd.rotation = (cmd.rotation + _stick_rotation).clamp(-Vector3.ONE, Vector3.ONE)
	cmd.boost_full = cmd.boost_full or _button(_right, full_boost_button)
	var brake_held := _button(_left, brake_button)
	if brake_held and not _brake_held:
		var now := Time.get_ticks_msec() / 1000.0
		_brake_hard = now - _brake_pressed_at <= double_tap_time
		_brake_pressed_at = now
	_brake_hard = _brake_hard and brake_held
	_brake_held = brake_held
	cmd.brake_full = cmd.brake_full or _brake_hard
	cmd.brake = cmd.brake or cmd.brake_full or brake_held
	var coupled_held := _button(_left, coupled_button)
	cmd.toggle_coupled = coupled_held and not _coupled_held
	_coupled_held = coupled_held
	var precision_held := _button(_left, precision_button)
	cmd.toggle_precision = precision_held and not _precision_held
	_precision_held = precision_held
	_poll_stick_weapons(cmd)
	return cmd


## Adds the sticks' weapon controls onto the keyboard's.
func _poll_stick_weapons(cmd: PilotCommand) -> void:
	cmd.vulcan_fire = cmd.vulcan_fire or _button(_right, vulcan_fire_button)
	cmd.vulcan_ready = cmd.vulcan_ready or cmd.vulcan_fire or _button(_right, vulcan_ready_button)
	cmd.fire_main = cmd.fire_main or _button(_right, weapon_release_button)
	cmd.shield_block = cmd.shield_block or _button(_left, shield_block_button)
	for button in lock_buttons:
		if _pressed(_left, button):
			cmd.lock_commit = true
	if _pressed(_left, lock_nearest_button):
		cmd.lock_nearest = true
	if _pressed(_left, unlock_button):
		cmd.unlock = true
	if _pressed(_left, target_next_button):
		cmd.target_cycle = 1
	if _pressed(_left, target_prev_button):
		cmd.target_cycle = -1
	if _pressed(_left, zoom_button):
		cmd.zoom = true
	for k in weapon_select_buttons.size():
		if _pressed(_right, weapon_select_buttons[k]):
			cmd.weapon_select = k
	for k in master_mode_buttons.size():
		if _pressed(_left, master_mode_buttons[k]):
			cmd.master_mode = k
	if _pressed(_right, master_arm_on_button):
		cmd.master_arm = 1
	if _pressed(_right, master_arm_off_button):
		cmd.master_arm = -1
	for k in scs_buttons.size():
		if _pressed(_right, scs_buttons[k]):
			cmd.scs = k
	var slew := Vector2(
		JoyDevices.shape(_raw_axis(_right, cursor_x_axis), cursor_deadzone, cursor_expo),
		JoyDevices.shape(_raw_axis(_right, cursor_y_axis), cursor_deadzone, cursor_expo))
	if invert_cursor_y:
		slew.y = -slew.y
	cmd.cursor_slew = (cmd.cursor_slew + slew).clamp(-Vector2.ONE, Vector2.ONE)


## True on the tick the button goes down.
func _pressed(device: int, button: int) -> bool:
	var down := _button(device, button)
	var key := device * 64 + button
	var was: bool = _was_down.get(key, false)
	_was_down[key] = down
	return down and not was


## Raw axis value. Override to script the sticks (probes).
func _raw_axis(device: int, axis: int) -> float:
	return Input.get_joy_axis(device, axis as JoyAxis)


func _button(device: int, button: int) -> bool:
	return button >= 0 and Input.is_joy_button_pressed(device, button as JoyButton)


## Median of the axis' last few samples: a spike of a tick or two never gets through.
func _axis(device: int, axis: int) -> float:
	var raw := _raw_axis(device, axis)
	if spike_filter_ticks <= 1:
		return raw
	var key := device * 16 + axis
	var samples: Array = _history.get_or_add(key, [])
	samples.append(raw)
	if samples.size() > spike_filter_ticks:
		samples.pop_front()
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[sorted.size() >> 1]


## Eases toward the target, landing exactly on a released (zero) axis.
func _ease(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var out := from.lerp(to, weight)
	for k in 3:
		if to[k] == 0.0 and absf(out[k]) < 0.02:
			out[k] = 0.0
	return out


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_find_sticks()


func _find_sticks() -> void:
	_left = JoyDevices.find(left_stick_name)
	_right = JoyDevices.find(right_stick_name)
	_history.clear()
	if not has_sticks():
		_stick_translation = Vector3.ZERO
		_stick_rotation = Vector3.ZERO
