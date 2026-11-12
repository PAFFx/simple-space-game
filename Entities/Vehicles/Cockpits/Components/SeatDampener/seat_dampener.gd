class_name SeatDampener
extends Node

## Linear seat G dampening. The seat rides on a spring-damper suspension with
## limited travel, which smooths jolts (thruster kicks, impacts), and an
## active inertial compensator cancels a fraction of the sustained
## acceleration (UC fiction: no suspension can reduce steady G on its own).
##
## Exposes the cabin (suit) G and the G the pilot actually feels, and sways
## the camera mount by the seat travel.

const G0 := 9.80665

@export var flight_computer: FlightComputer
@export var camera_mount: Node3D
@export var natural_frequency: float = 14.0      ## rad/s
@export var damping_ratio: float = 0.8
@export var travel: float = 0.15                 ## m, each axis
## Fraction of the remaining acceleration cancelled by the active dampener.
@export_range(0.0, 0.95) var inertial_compensation: float = 0.55
@export var sway_scale: float = 0.6
@export var filter_time: float = 0.05            ## s, smooths the cabin accel estimate

var cabin_g: float = 0.0
var pilot_g: float = 0.0
var peak_pilot_g: float = 0.0

var _cockpit: Node3D
var _x := Vector3.ZERO      ## seat displacement relative to the cabin, cockpit frame
var _v := Vector3.ZERO
var _accel := Vector3.ZERO  ## filtered cabin acceleration, world
var _prev_point_v := Vector3.ZERO
var _primed := false
var _mount_rest := Vector3.ZERO
var _hatch: CockpitHatch


func _ready() -> void:
	_cockpit = get_parent() as Node3D
	if camera_mount != null:
		_mount_rest = camera_mount.position
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		if flight_computer == null:
			flight_computer = vehicle.find_component(FlightComputer) as FlightComputer
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch


func _physics_process(delta: float) -> void:
	var body := flight_computer.body if flight_computer != null else null
	if body == null or _cockpit == null or delta <= 0.0:
		return
	var com := flight_computer.state.com_position
	var point_v := body.linear_velocity + body.angular_velocity.cross(_cockpit.global_position - com)
	if not _primed:
		_primed = true
		_prev_point_v = point_v
		return
	var raw := (point_v - _prev_point_v) / delta
	_prev_point_v = point_v
	_accel = _accel.lerp(raw, 1.0 - exp(-delta / maxf(filter_time, 1e-3)))

	# Seat relative to the cabin: x'' = -a_cabin - wn² x - 2 ζ wn x'
	var a_local := _cockpit.global_basis.inverse() * _accel
	if _hatch != null and _hatch.is_unsealed():
		a_local = Vector3.ZERO  # linear seat off with the hatch open: the seat settles to centre
	var wn := natural_frequency
	var rel_accel := -a_local - _x * wn * wn - _v * 2.0 * damping_ratio * wn
	_v += rel_accel * delta
	_x += _v * delta
	for k in 3:
		if absf(_x[k]) > travel:
			# Bottomed out: the seat now moves with the cabin.
			_x[k] = clampf(_x[k], -travel, travel)
			_v[k] = 0.0
			rel_accel[k] = 0.0

	var seat_accel := a_local + rel_accel
	cabin_g = _accel.length() / G0
	pilot_g = seat_accel.length() * (1.0 - inertial_compensation) / G0
	peak_pilot_g = maxf(peak_pilot_g * exp(-delta / 3.0), pilot_g)
	if camera_mount != null:
		camera_mount.position = _mount_rest + _x * sway_scale
