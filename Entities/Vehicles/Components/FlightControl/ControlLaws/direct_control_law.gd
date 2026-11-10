class_name DirectControlLaw
extends ControlLaw

## No assists: stick deflection maps straight to force and torque authority.
## Useful as a baseline and as a "FCS failure / manual reversion" mode.

@export_range(0.0, 1.0) var cruise_thrust_fraction: float = 0.5
@export_range(0.0, 1.0) var torque_fraction: float = 0.35


func compute(state: FlightState, command: PilotCommand) -> Wrench:
	var limit := 1.0 if command.boost else cruise_thrust_fraction
	var force := scale_by_authority(command.translation, state) * limit
	var torque := command.rotation * state.max_torque * torque_fraction
	return Wrench.new(force, torque)


func get_mode_labels() -> PackedStringArray:
	return PackedStringArray(["FCS DIRECT"])
