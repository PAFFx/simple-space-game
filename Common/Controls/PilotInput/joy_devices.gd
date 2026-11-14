class_name JoyDevices

## Finds joysticks by name. Device indices follow plug order, so two identical
## sticks can swap between runs; their names ("... EVO L" / "... EVO R") don't.


## Device index of the first connected joystick whose name contains `name_part`, or -1.
static func find(name_part: String) -> int:
	if name_part.is_empty():
		return -1
	for device in Input.get_connected_joypads():
		if Input.get_joy_name(device).containsn(name_part):
			return device
	return -1


## Deadzone rescaled to start at 0, then expo (0 = linear, 1 = fully cubic).
static func shape(raw: float, deadzone: float, expo: float) -> float:
	var mag := absf(raw)
	if mag <= deadzone:
		return 0.0
	var x := minf((mag - deadzone) / (1.0 - deadzone), 1.0)
	return signf(raw) * lerpf(x, x * x * x, expo)
