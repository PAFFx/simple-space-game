class_name KeyboardPilotInput
extends PilotInputSource

## Reads keyboard / mouse actions (see PilotInputActions) into PilotCommands.
## Digital keys are slewed toward their target so the stick "travels" instead of
## snapping, which keeps the FBW demand smooth and animates cockpit grips nicely.
##
## Holding MOUSE_STEER turns mouse motion into pitch/yaw demand (mouse up = nose
## up, right = yaw right): mouse speed sets the deflection, like a stick that
## springs back when the mouse stops.
## Shift boosts; double-tap Shift (and hold) to boost with full auto-rotation.

## Seconds for a digital axis to travel from centre to full deflection.
@export var key_travel_time: float = 0.1
## Mouse speed that gives full stick deflection, px/s.
@export var mouse_full_deflection_speed: float = 900.0
## Smoothing of the mouse demand, s (mouse events and physics ticks don't line up).
@export var mouse_smoothing: float = 0.05
## Max gap between the two Shift presses of a full boost, s.
@export var double_tap_time: float = 0.3

var _translation := Vector3.ZERO
var _rotation := Vector3.ZERO
var _mouse_px := Vector2.ZERO        ## Motion since the last tick
var _mouse_demand := Vector2.ZERO    ## Smoothed (yaw, pitch) deflection
var _last_boost_press := -INF
var _boost_full := false


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
	_translation = _translation.move_toward(target_t, step)
	_rotation = _rotation.move_toward(target_r, step)

	var cmd := PilotCommand.new()
	cmd.translation = _translation
	cmd.rotation = (_rotation + _poll_mouse(delta)).clamp(-Vector3.ONE, Vector3.ONE)
	_poll_boost(cmd)
	cmd.toggle_translation_mode = Input.is_action_just_pressed(a.TOGGLE_TRANSLATION_MODE)
	cmd.toggle_rotation_mode = Input.is_action_just_pressed(a.TOGGLE_ROTATION_MODE)
	cmd.toggle_precision = Input.is_action_just_pressed(a.TOGGLE_PRECISION)
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


func _poll_boost(cmd: PilotCommand) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if Input.is_action_just_pressed(PilotInputActions.BOOST):
		_boost_full = now - _last_boost_press <= double_tap_time
		_last_boost_press = now
	cmd.boost = Input.is_action_pressed(PilotInputActions.BOOST)
	if not cmd.boost:
		_boost_full = false
	cmd.boost_full = cmd.boost and _boost_full
