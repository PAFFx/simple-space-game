class_name KeyboardPilotInput
extends PilotInputSource

## Reads keyboard / gamepad actions (see PilotInputActions) into PilotCommands.
## Digital keys are slewed toward their target so the stick "travels" instead of
## snapping, which keeps the FBW demand smooth and animates cockpit grips nicely.

## Seconds for a digital axis to travel from centre to full deflection.
@export var key_travel_time: float = 0.1

var _translation := Vector3.ZERO
var _rotation := Vector3.ZERO


func _ready() -> void:
	PilotInputActions.ensure_defaults()


func poll_command() -> PilotCommand:
	var a := PilotInputActions
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
	var step := get_physics_process_delta_time() / maxf(key_travel_time, 0.001)
	_translation = _translation.move_toward(target_t, step)
	_rotation = _rotation.move_toward(target_r, step)

	var cmd := PilotCommand.new()
	cmd.translation = _translation
	cmd.rotation = _rotation
	cmd.boost = Input.is_action_pressed(a.BOOST)
	cmd.toggle_translation_mode = Input.is_action_just_pressed(a.TOGGLE_TRANSLATION_MODE)
	cmd.toggle_rotation_mode = Input.is_action_just_pressed(a.TOGGLE_ROTATION_MODE)
	return cmd
