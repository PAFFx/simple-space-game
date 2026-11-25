class_name CockpitGimbal
extends Node

## Turns the whole cockpit (seat, screen, camera) inside the hull so it holds the
## pilot frame in the world while the FCS turns the body for thrust vectoring:
## cockpit rotation relative to the hull = body⁻¹ · pilot (measured, not commanded,
## so it stays still while the body is still swinging). Commanded rotations turn
## the pilot frame itself, so the cockpit moves with them, slightly ahead of the body.
## Place under the CockpitBase node; it rotates that node.
## While the hatch is unsealed the gimbal eases back to centre and holds there, so the
## capsule stays lined up with its doorway (and can't turn into the hull).

@export var flight_computer: FlightComputer
## Mechanical limit of the seat gimbal.
@export var max_angle_deg: float = 75.0
## Beyond this the cockpit starts to yield smoothly instead of hitting a wall at
## the limit, so an overshooting body never snaps the pilot's view.
@export var soft_knee_deg: float = 62.0
## How fast the gimbal centres (and comes back) around a hatch opening, 1/s.
@export var hatch_blend_rate: float = 2.0

## A beam went through the cockpit (DamageModel): the gimbal is wrecked and the capsule stays
## where it is in the suit until repaired.
var jammed := false

var _cockpit: Node3D
var _rest := Basis.IDENTITY
var _hatch: CockpitHatch
var _engaged := 1.0  ## 1 = following the pilot frame, 0 = centred for the hatch


func _ready() -> void:
	_cockpit = get_parent() as Node3D
	if _cockpit != null:
		_rest = _cockpit.basis
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		if flight_computer == null:
			flight_computer = vehicle.find_component(FlightComputer) as FlightComputer
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch


func _physics_process(delta: float) -> void:
	if _cockpit == null or jammed or flight_computer == null or flight_computer.control_law == null:
		return
	var target := 0.0 if _hatch != null and _hatch.is_unsealed() else 1.0
	_engaged = move_toward(_engaged, target, hatch_blend_rate * delta)
	var q := cushion(flight_computer.get_cockpit_rotation())
	_cockpit.basis = _rest * Basis(Quaternion.IDENTITY.slerp(q, smoothstep(0.0, 1.0, _engaged)))


## Maps the wanted cockpit rotation into the gimbal range: unchanged below the
## knee, then eased (tanh) toward the limit, continuous in angle and rate.
func cushion(rotation_q: Quaternion) -> Quaternion:
	var q := AttitudeOffsetSolver.shortest(rotation_q)
	var angle := q.get_angle()
	var knee := deg_to_rad(soft_knee_deg)
	var limit := deg_to_rad(max_angle_deg)
	if angle <= knee or limit <= knee:
		return AttitudeOffsetSolver.clamp_rotation(q, limit)
	var span := limit - knee
	return Quaternion(q.get_axis(), knee + span * tanh((angle - knee) / span))


## Current cockpit ↔ body angle, degrees.
func get_offset_deg() -> float:
	return rad_to_deg(Quaternion(_cockpit.basis * _rest.inverse()).get_angle()) if _cockpit else 0.0
