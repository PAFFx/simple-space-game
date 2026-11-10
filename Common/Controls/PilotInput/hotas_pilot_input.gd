class_name HotasPilotInput
extends KeyboardPilotInput

## Keyboard plus raw joystick axes (flight stick, HOTAS, twin sticks).
## Each JoyAxisBinding adds onto the keyboard demand; the sum is clamped.
## Unplugged devices are simply ignored, so keyboard-only play still works.
##
## Not sure which index your stick uses? Enable log_axis_activity, move each
## axis, and read the indices from the Output panel.

## Off by default: uncalibrated or noisy sticks can inject phantom demands.
@export var joystick_enabled: bool = false
@export var axis_bindings: Array[JoyAxisBinding] = []
@export var log_axis_activity: bool = false

var _logged := {}


func poll_command() -> PilotCommand:
	var cmd := super.poll_command()
	if not joystick_enabled:
		return cmd
	var connected := Input.get_connected_joypads()
	for b in axis_bindings:
		if b == null or not connected.has(b.device):
			continue
		var v := b.read()
		match b.channel:
			JoyAxisBinding.Channel.ROLL: cmd.rotation.z -= v
			JoyAxisBinding.Channel.PITCH: cmd.rotation.x += v
			JoyAxisBinding.Channel.YAW: cmd.rotation.y -= v
			JoyAxisBinding.Channel.STRAFE: cmd.translation.x += v
			JoyAxisBinding.Channel.SURGE: cmd.translation.z += v
			JoyAxisBinding.Channel.HEAVE: cmd.translation.y += v
	cmd.rotation = cmd.rotation.clamp(-Vector3.ONE, Vector3.ONE)
	cmd.translation = cmd.translation.clamp(-Vector3.ONE, Vector3.ONE)
	if log_axis_activity:
		_log_activity(connected)
	return cmd


func _log_activity(devices: Array[int]) -> void:
	for device in devices:
		for axis in 10:
			var v := Input.get_joy_axis(device, axis as JoyAxis)
			var key := device * 100 + axis
			var bucket := roundi(v * 4.0)
			if _logged.get(key, 0) != bucket:
				_logged[key] = bucket
				print("[HotasPilotInput] joy %d (%s) axis %d = %.2f"
						% [device, Input.get_joy_name(device), axis, v])
