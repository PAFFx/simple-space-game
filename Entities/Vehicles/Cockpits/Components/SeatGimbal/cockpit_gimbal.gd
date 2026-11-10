class_name CockpitGimbal
extends Node

## Turns the whole cockpit (seat, screen, camera) inside the hull so it holds the
## pilot frame in the world while the FCS turns the body for thrust vectoring:
## cockpit rotation relative to the hull = body⁻¹ · pilot (measured, not commanded,
## so it stays still while the body is still swinging). Commanded rotations turn
## the pilot frame itself, so the cockpit moves with them, slightly ahead of the body.
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


func _physics_process(_delta: float) -> void:
	if _cockpit == null or flight_computer == null or flight_computer.control_law == null:
		return
	var relative := AttitudeOffsetSolver.clamp_rotation(
			flight_computer.get_cockpit_rotation(), deg_to_rad(max_angle_deg))
	_cockpit.basis = _rest * Basis(relative)


## Current cockpit ↔ body angle, degrees.
func get_offset_deg() -> float:
	return rad_to_deg(Quaternion(_cockpit.basis * _rest.inverse()).get_angle()) if _cockpit else 0.0
