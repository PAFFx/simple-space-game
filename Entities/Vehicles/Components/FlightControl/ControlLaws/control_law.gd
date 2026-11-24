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


## Override: boost / brake for the HUD this tick: 0 off, 1 on, 2 full (double-tapped).
func get_boost_level() -> int:
	return 0


func get_brake_level() -> int:
	return 0


## Override: a kick (pintle burst dodge) is in progress.
func is_dodging() -> bool:
	return false


## Body orientation relative to the pilot frame (body = pilot · offset). The
## cockpit counter-rotates by this. Identity for laws without auto-rotation.
func get_pilot_offset() -> Quaternion:
	return Quaternion.IDENTITY


## Pilot frame (cockpit) orientation, global. null = the law has none (cockpit follows the body).
func get_pilot_orientation() -> Variant:
	return null


## Pilot frame the cockpit should show if the body were at `body_q` (axes locked
## to the body follow it). null = the cockpit follows the body.
func get_cockpit_orientation(_body_q: Quaternion) -> Variant:
	return get_pilot_orientation()


## Global "up" the law levels the cockpit's roll to (horizon lock), or null when none.
func get_horizon_up() -> Variant:
	return null


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


## Scales `v` down (keeping its direction) to fit inside ±limit on every axis. A per-axis
## clamp would turn a saturated torque onto the other axes.
static func scale_to_box(v: Vector3, limit: Vector3) -> Vector3:
	var scale := 1.0
	for k in 3:
		if absf(v[k]) > limit[k]:
			scale = minf(scale, limit[k] / absf(v[k]))
	return v * scale


static func clamp_to_authority(force: Vector3, state: FlightState, fraction: float) -> Vector3:
	var out := Vector3.ZERO
	for k in 3:
		out[k] = clampf(force[k], -state.max_force_neg[k] * fraction, state.max_force_pos[k] * fraction)
	return out
