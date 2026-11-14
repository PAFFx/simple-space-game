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


func _ready() -> void:
	PilotInputActions.ensure_defaults()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and PilotInputActions.is_mouse_steering():
		_mouse_px += (event as InputEventMouseMotion).relative


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
	var urgent := Input.is_action_pressed(a.BOOST) or Input.is_action_pressed(a.BRAKE)
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
	# Rotation mode, precision and horizon lock are cockpit switches (CockpitSwitchPanel).
	return cmd


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
