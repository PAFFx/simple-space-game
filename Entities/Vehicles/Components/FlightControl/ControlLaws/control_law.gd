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


## Body orientation relative to the pilot frame (body = pilot · offset). The
## cockpit counter-rotates by this. Identity for laws without auto-rotation.
func get_pilot_offset() -> Quaternion:
	return Quaternion.IDENTITY


## Pilot frame (cockpit) orientation, global. null = the law has none (cockpit follows the body).
func get_pilot_orientation() -> Variant:
	return null


## True while the cockpit should move rigidly with the body.
func is_cockpit_locked() -> bool:
	return false


## Called when the law is (re)engaged so stale integrators / holds are dropped.
func reset() -> void:
	pass


## Maps a [-1, 1] demand onto the asymmetric per-axis force authority.
static func scale_by_authority(demand: Vector3, state: FlightState) -> Vector3:
	var out := Vector3.ZERO
	for k in 3:
		out[k] = demand[k] * (state.max_force_pos[k] if demand[k] >= 0.0 else state.max_force_neg[k])
	return out


## Scales `force` down (keeping its direction) to fit `fraction` of the directional authority.
static func clamp_to_capability(force: Vector3, state: FlightState, fraction: float) -> Vector3:
	var magnitude := force.length()
	if magnitude < 1e-6:
		return Vector3.ZERO
	var limit := state.force_capability(force / magnitude) * fraction
	return force * (limit / magnitude) if magnitude > limit else force


static func clamp_to_authority(force: Vector3, state: FlightState, fraction: float) -> Vector3:
	var out := Vector3.ZERO
	for k in 3:
		out[k] = clampf(force[k], -state.max_force_neg[k] * fraction, state.max_force_pos[k] * fraction)
	return out
