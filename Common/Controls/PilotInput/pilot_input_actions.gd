class_name PilotInputActions

## Input action names used by the mobile suit, plus default bindings.
## Defaults are only registered for actions missing from the InputMap, so any
## binding defined in Project Settings > Input Map takes precedence.

const TRANSLATE_FORWARD := &"ms_translate_forward"
const TRANSLATE_BACK := &"ms_translate_back"
const TRANSLATE_LEFT := &"ms_translate_left"
const TRANSLATE_RIGHT := &"ms_translate_right"
const TRANSLATE_UP := &"ms_translate_up"
const TRANSLATE_DOWN := &"ms_translate_down"
const PITCH_UP := &"ms_pitch_up"
const PITCH_DOWN := &"ms_pitch_down"
const YAW_LEFT := &"ms_yaw_left"
const YAW_RIGHT := &"ms_yaw_right"
const ROLL_LEFT := &"ms_roll_left"
const ROLL_RIGHT := &"ms_roll_right"
const BOOST := &"ms_boost"
const TOGGLE_TRANSLATION_MODE := &"ms_toggle_translation_mode"
const TOGGLE_ROTATION_MODE := &"ms_toggle_rotation_mode"
const TOGGLE_HATCH := &"ms_toggle_hatch"
const TOGGLE_VIEW := &"ms_toggle_view"

# action: [keys, joypad axis (axis, sign) or null, joypad button or -1]
const _DEFAULTS := {
	TRANSLATE_FORWARD: [[KEY_W], [JOY_AXIS_LEFT_Y, -1.0], -1],
	TRANSLATE_BACK: [[KEY_S], [JOY_AXIS_LEFT_Y, 1.0], -1],
	TRANSLATE_LEFT: [[KEY_A], [JOY_AXIS_LEFT_X, -1.0], -1],
	TRANSLATE_RIGHT: [[KEY_D], [JOY_AXIS_LEFT_X, 1.0], -1],
	TRANSLATE_UP: [[KEY_R, KEY_SPACE], [JOY_AXIS_TRIGGER_RIGHT, 1.0], -1],
	TRANSLATE_DOWN: [[KEY_F], [JOY_AXIS_TRIGGER_LEFT, 1.0], -1],
	# Flight-sim convention: pushing the stick forward (Up arrow) pitches the nose down.
	PITCH_UP: [[KEY_DOWN], [JOY_AXIS_RIGHT_Y, 1.0], -1],
	PITCH_DOWN: [[KEY_UP], [JOY_AXIS_RIGHT_Y, -1.0], -1],
	YAW_LEFT: [[KEY_LEFT], [JOY_AXIS_RIGHT_X, -1.0], -1],
	YAW_RIGHT: [[KEY_RIGHT], [JOY_AXIS_RIGHT_X, 1.0], -1],
	ROLL_LEFT: [[KEY_Q], null, JOY_BUTTON_LEFT_SHOULDER],
	ROLL_RIGHT: [[KEY_E], null, JOY_BUTTON_RIGHT_SHOULDER],
	BOOST: [[KEY_SHIFT], null, JOY_BUTTON_LEFT_STICK],
	TOGGLE_TRANSLATION_MODE: [[KEY_T], null, JOY_BUTTON_X],
	TOGGLE_ROTATION_MODE: [[KEY_G], null, JOY_BUTTON_Y],
	TOGGLE_HATCH: [[KEY_H], null, JOY_BUTTON_BACK],
	TOGGLE_VIEW: [[KEY_V], null, JOY_BUTTON_START],
}


static func ensure_defaults() -> void:
	for action: StringName in _DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.15)
		var spec: Array = _DEFAULTS[action]
		for key: Key in spec[0]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		if spec[1] != null:
			var joy := InputEventJoypadMotion.new()
			joy.axis = spec[1][0]
			joy.axis_value = spec[1][1]
			InputMap.action_add_event(action, joy)
		if spec[2] >= 0:
			var btn := InputEventJoypadButton.new()
			btn.button_index = spec[2]
			InputMap.action_add_event(action, btn)
