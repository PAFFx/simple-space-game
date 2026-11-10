class_name JoyAxisBinding
extends Resource

## Binds one raw joystick axis to one command channel, with shaping.
## Signs follow the physical stick: + = stick right / pulled back / twist right.

enum Channel {
	ROLL,     ## + = roll right
	PITCH,    ## + = stick back = nose up
	YAW,      ## + = twist right = nose right
	STRAFE,   ## + = translate right
	SURGE,    ## + = stick back = translate backward
	HEAVE,    ## + = translate up
}

@export var channel: Channel = Channel.ROLL
@export var device: int = 0
@export var axis: int = 0
@export var invert: bool = false
@export_range(0.0, 0.5) var deadzone: float = 0.05
## 0 = linear, 1 = fully cubic. Softens the centre for fine control.
@export_range(0.0, 1.0) var expo: float = 0.3


func read() -> float:
	var raw := Input.get_joy_axis(device, axis as JoyAxis)
	var mag := absf(raw)
	if mag <= deadzone:
		return 0.0
	var x := (mag - deadzone) / (1.0 - deadzone)
	x = lerpf(x, x * x * x, expo)
	return signf(raw) * x * (-1.0 if invert else 1.0)
