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
const BRAKE := &"ms_brake"
## Hold to steer pitch/yaw with the mouse (otherwise the mouse looks around).
const MOUSE_STEER := &"ms_mouse_steer"
## Toggle cockpit click mode: a free cursor for the cockpit's switches (left / right click
## throws a switch either way); otherwise the mouse looks around.
const CLICK_MODE := &"ms_click_mode"
const TOGGLE_VIEW := &"ms_toggle_view"
const TOGGLE_RIFLE := &"ms_toggle_rifle"
const TOGGLE_SHIELD := &"ms_toggle_shield"

# Keyboard only. Flight sticks and HOTAS report raw axes/buttons whose indices
# differ per device, so analog input is bound through HotasPilotInput instead.
const _DEFAULTS := {
	TRANSLATE_FORWARD: [KEY_W],
	TRANSLATE_BACK: [KEY_S],
	TRANSLATE_LEFT: [KEY_A],
	TRANSLATE_RIGHT: [KEY_D],
	TRANSLATE_UP: [KEY_SPACE, KEY_R],
	TRANSLATE_DOWN: [KEY_ALT, KEY_F],
	# Flight-sim convention: pushing the stick forward (Up arrow) pitches the nose down.
	PITCH_UP: [KEY_DOWN],
	PITCH_DOWN: [KEY_UP],
	YAW_LEFT: [KEY_LEFT],
	YAW_RIGHT: [KEY_RIGHT],
	ROLL_LEFT: [KEY_Q],
	ROLL_RIGHT: [KEY_E],
	BOOST: [KEY_SHIFT],
	BRAKE: [KEY_CTRL],
	TOGGLE_VIEW: [KEY_V],
	TOGGLE_RIFLE: [KEY_1],
	TOGGLE_SHIELD: [KEY_2],
}

# Keys bound on the left of the keyboard only (right Alt is AltGr on many layouts).
const _LEFT_ONLY := [KEY_ALT]

const _MOUSE_DEFAULTS := {
	MOUSE_STEER: [MOUSE_BUTTON_RIGHT],
	CLICK_MODE: [MOUSE_BUTTON_MIDDLE],
}


static func ensure_defaults() -> void:
	for action: StringName in _DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.15)
		for key: Key in _DEFAULTS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if key in _LEFT_ONLY:
				ev.location = KEY_LOCATION_LEFT
			InputMap.action_add_event(action, ev)
	for action: StringName in _MOUSE_DEFAULTS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for button: MouseButton in _MOUSE_DEFAULTS[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)


## True while the mouse steers the suit instead of looking around.
static func is_mouse_steering() -> bool:
	return InputMap.has_action(MOUSE_STEER) and Input.is_action_pressed(MOUSE_STEER) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
