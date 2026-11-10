class_name PilotInputSource
extends Node

## Abstract source of PilotCommands. Swap the concrete node (keyboard, HOTAS,
## autopilot, replay...) without touching the flight computer.

var last_command := PilotCommand.new()


## Override: build this physics frame's command. Called once per physics tick.
func poll_command() -> PilotCommand:
	return PilotCommand.new()


func get_command() -> PilotCommand:
	last_command = poll_command()
	return last_command
