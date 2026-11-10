class_name CockpitGimbal
extends Node

## Turns the whole cockpit (seat, screen, camera) inside the hull so it keeps the
## pilot frame while the FCS turns the body for thrust vectoring:
## cockpit rotation relative to its mount = offset⁻¹ (body = pilot · offset).
## Commanded rotations turn the pilot frame itself, so the cockpit moves with them.
## Place under the CockpitBase node; it rotates that node.

@export var flight_computer: FlightComputer
@export var max_angle_deg: float = 70.0

var _cockpit: Node3D
var _rest := Basis.IDENTITY


func _ready() -> void:
	_cockpit = get_parent() as Node3D
	if _cockpit != null:
		_rest = _cockpit.basis
	if flight_computer == null:
		var vehicle := VehicleBase.find_vehicle(self)
		if vehicle != null:
			flight_computer = vehicle.find_component(FlightComputer) as FlightComputer


func _process(_delta: float) -> void:
	if _cockpit == null or flight_computer == null or flight_computer.control_law == null:
		return
	var offset := AttitudeOffsetSolver.clamp_rotation(
			flight_computer.get_pilot_offset(), deg_to_rad(max_angle_deg))
	_cockpit.basis = _rest * Basis(offset.inverse())


## Current cockpit ↔ body angle, degrees.
func get_offset_deg() -> float:
	return rad_to_deg(Quaternion(_cockpit.basis * _rest.inverse()).get_angle()) if _cockpit else 0.0
