@abstract
class_name ControlLaw
extends Resource

## Turns pilot intent into a desired body wrench (force + torque about COM).
## Swap implementations on the FlightComputer to try different FBW philosophies.
## Instances hold per-vehicle state, so the FlightComputer duplicates them.


## Override: desired wrench in the body frame for this tick.
@abstract func compute(state: FlightState, command: PilotCommand) -> Wrench


## Override: short labels for the HUD, e.g. ["TRANS NEWTON", "ROT ATT-HOLD"].
func get_mode_labels() -> PackedStringArray:
	return PackedStringArray()


## Called when the law is (re)engaged so stale integrators / holds are dropped.
func reset() -> void:
	pass


## Maps a [-1, 1] demand onto the asymmetric per-axis force authority.
static func scale_by_authority(demand: Vector3, state: FlightState) -> Vector3:
	var out := Vector3.ZERO
	for k in 3:
		out[k] = demand[k] * (state.max_force_pos[k] if demand[k] >= 0.0 else state.max_force_neg[k])
	return out


static func clamp_to_authority(force: Vector3, state: FlightState, fraction: float) -> Vector3:
	var out := Vector3.ZERO
	for k in 3:
		out[k] = clampf(force[k], -state.max_force_neg[k] * fraction, state.max_force_pos[k] * fraction)
	return out
