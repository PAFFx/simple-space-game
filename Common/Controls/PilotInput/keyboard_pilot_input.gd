class_name KeyboardPilotInput
extends PilotInputSource

## Reads keyboard / mouse actions (see PilotInputActions) into PilotCommands.
## Digital keys are slewed toward their target so the stick "travels" instead of
## snapping, which keeps the FBW demand smooth and animates cockpit grips nicely.
##
## Holding MOUSE_STEER turns mouse motion into pitch/yaw demand (mouse up = nose
## up, right = yaw right): mouse speed sets the deflection, like a stick that
## springs back when the mouse stops.
## Shift boosts; double-tap Shift (and hold) to boost with full auto-rotation. Released
## keys coast; Ctrl brakes the axes not being pushed on, double-tapped (and held) harder.
## Caps Lock kicks (dodges) along the movement keys held.
##
## Weapons: left mouse fires the selected weapon (while the mouse is captured), X the
## vulcans, T shows the lock candidate and G locks it, B holds the shield up, 1-5 are the
## weapon select hat, M master arm, N / J / K the master modes, Tab the sensor of interest.
## One-shot keys are taken from unhandled input, so a debug panel can claim them first.

## Seconds for a digital axis to travel from centre to full deflection.
@export var key_travel_time: float = 0.1
## Same for the movement keys while boost or brake is held.
@export var boost_key_travel_time: float = 0.03
## Mouse speed that gives full stick deflection, px/s.
@export var mouse_full_deflection_speed: float = 900.0
## Smoothing of the mouse demand, s (mouse events and physics ticks don't line up).
@export var mouse_smoothing: float = 0.05
## Max gap between the two presses of a double tap (full boost, hard brake), s.
@export var double_tap_time: float = 0.3

var _translation := Vector3.ZERO
var _rotation := Vector3.ZERO
var _mouse_px := Vector2.ZERO        ## Motion since the last tick
var _mouse_demand := Vector2.ZERO    ## Smoothed (yaw, pitch) deflection
var _last_press := {}                ## Action → time of its last press, s
var _double := {}                    ## Action → held since a double tap
# One-shot weapon requests since the last tick.
var _weapon_select := -1
var _master_arm := 0
var _master_mode := -1
var _lock_commit := false
var _unlock := false
var _target_cycle := 0
var _zoom := false
var _scs := -1
var _lock_nearest := false
var _dodge := false


func _ready() -> void:
	PilotInputActions.ensure_defaults()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and PilotInputActions.is_mouse_steering():
		_mouse_px += (event as InputEventMouseMotion).relative


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	var a := PilotInputActions
	for k in a.WEAPON_SELECT.size():
		if event.is_action(a.WEAPON_SELECT[k]):
			_weapon_select = k
	for k in a.MASTER_MODE.size():
		if event.is_action(a.MASTER_MODE[k]):
			_master_mode = k
	if event.is_action(a.MASTER_ARM):
		_master_arm = 2
	if event.is_action(a.LOCK_COMMIT):
		_lock_commit = true
	if event.is_action(a.UNLOCK):
		_unlock = true
	if event.is_action(a.TARGET_PREV):
		_target_cycle = -1
	if event.is_action(a.TARGET_NEXT):
		_target_cycle = 1
	if event.is_action(a.ZOOM):
		_zoom = true
	for k in a.SCS.size():
		if event.is_action(a.SCS[k]):
			_scs = k
	if event.is_action(a.LOCK_NEAREST):
		_lock_nearest = true
	if event.is_action(a.DODGE):
		_dodge = true


func poll_command() -> PilotCommand:
	var a := PilotInputActions
	var delta := get_physics_process_delta_time()
	var target_t := Vector3(
		Input.get_axis(a.TRANSLATE_LEFT, a.TRANSLATE_RIGHT),
		Input.get_axis(a.TRANSLATE_DOWN, a.TRANSLATE_UP),
		Input.get_axis(a.TRANSLATE_FORWARD, a.TRANSLATE_BACK)
	)
	var target_r := Vector3(
		Input.get_axis(a.PITCH_DOWN, a.PITCH_UP),
		Input.get_axis(a.YAW_RIGHT, a.YAW_LEFT),
		Input.get_axis(a.ROLL_RIGHT, a.ROLL_LEFT)
	)
	var step := delta / maxf(key_travel_time, 0.001)
	# Boosting or braking, the movement keys are slammed, not eased: a dodge can't wait.
	var urgent := Input.is_action_pressed(a.BOOST) or Input.is_action_pressed(a.BRAKE) \
			or Input.is_action_pressed(a.DODGE)
	var step_t := delta / maxf(boost_key_travel_time, 0.001) if urgent else step
	_translation = _translation.move_toward(target_t, step_t)
	_rotation = _rotation.move_toward(target_r, step)

	var cmd := PilotCommand.new()
	cmd.translation = _translation
	cmd.rotation = (_rotation + _poll_mouse(delta)).clamp(-Vector3.ONE, Vector3.ONE)
	cmd.boost = Input.is_action_pressed(a.BOOST)
	cmd.boost_full = _held_after_double_tap(a.BOOST)
	cmd.brake = Input.is_action_pressed(a.BRAKE)
	cmd.brake_full = _held_after_double_tap(a.BRAKE)
	cmd.dodge = _dodge
	_dodge = false
	# Rotation mode, precision and horizon lock are cockpit switches (CockpitSwitchPanel).
	_poll_weapons(cmd)
	return cmd


func _poll_weapons(cmd: PilotCommand) -> void:
	var a := PilotInputActions
	# The left button fires only while the mouse flies the view, not the click cursor.
	cmd.fire_main = Input.is_action_pressed(a.FIRE_MAIN) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	cmd.vulcan_fire = Input.is_action_pressed(a.VULCAN)
	cmd.vulcan_ready = cmd.vulcan_fire
	cmd.shield_block = Input.is_action_pressed(a.SHIELD_BLOCK)
	cmd.cursor_slew = Vector2(Input.get_axis(a.CURSOR_LEFT, a.CURSOR_RIGHT), Input.get_axis(a.CURSOR_DOWN, a.CURSOR_UP))
	cmd.weapon_select = _weapon_select
	cmd.master_arm = _master_arm
	cmd.master_mode = _master_mode
	cmd.lock_commit = _lock_commit
	cmd.unlock = _unlock
	cmd.target_cycle = _target_cycle
	cmd.zoom = _zoom
	cmd.scs = _scs
	cmd.lock_nearest = _lock_nearest
	_weapon_select = -1
	_master_arm = 0
	_master_mode = -1
	_lock_commit = false
	_unlock = false
	_target_cycle = 0
	_zoom = false
	_scs = -1
	_lock_nearest = false


## Pitch/yaw demand from mouse motion while steering.
func _poll_mouse(delta: float) -> Vector3:
	var raw := Vector2.ZERO
	if PilotInputActions.is_mouse_steering() and delta > 0.0:
		var speed := maxf(mouse_full_deflection_speed, 1.0)
		raw = Vector2(-_mouse_px.x, -_mouse_px.y) / (delta * speed)
	_mouse_px = Vector2.ZERO
	var w := 1.0 if mouse_smoothing <= 0.0 else 1.0 - exp(-delta / mouse_smoothing)
	_mouse_demand = _mouse_demand.lerp(raw.clamp(-Vector2.ONE, Vector2.ONE), w)
	if raw == Vector2.ZERO and _mouse_demand.length() < 0.01:
		_mouse_demand = Vector2.ZERO
	return Vector3(_mouse_demand.y, _mouse_demand.x, 0.0)


## True while `action` is held after being pressed twice within double_tap_time.
func _held_after_double_tap(action: StringName) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if Input.is_action_just_pressed(action):
		_double[action] = now - float(_last_press.get(action, -INF)) <= double_tap_time
		_last_press[action] = now
	if not Input.is_action_pressed(action):
		_double[action] = false
	return _double.get(action, false)
