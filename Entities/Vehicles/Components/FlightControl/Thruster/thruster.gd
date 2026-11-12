class_name Thruster
extends Node3D

## Gimballed thruster that pushes its RigidBody3D.
##
## Orientation: the node's -Z is the nominal THRUST direction, so the blue +Z
## gizmo arrow in the editor shows where the exhaust plume goes.
##
## The FlightComputer calls set_command() then step() every physics tick. The
## applied force follows the *actual* gimbal angle and spooled throttle, so
## actuator lag is part of the simulation rather than hidden from the solver.

@export var max_thrust: float = 150000.0          ## N
@export_range(0.0, 60.0) var gimbal_limit_deg: float = 20.0
## Tighter limit on the fore/aft swing (about the node's local X axis), deg. At or
## above gimbal_limit_deg it adds nothing. Lets a nozzle swing wide sideways but only
## a little fore and aft.
@export_range(0.0, 90.0) var gimbal_pitch_limit_deg: float = 90.0
## Same for the sideways swing (about local Y). 0 = the nozzle only swings fore/aft
## (one-plane, "2D" vectoring); gimbal_limit_deg 0 = fixed nozzle.
@export_range(0.0, 90.0) var gimbal_yaw_limit_deg: float = 90.0
@export var gimbal_rate_deg: float = 120.0        ## Max gimbal slew, deg/s
@export var spool_up_time: float = 0.25           ## Throttle time constant rising, s
@export var spool_down_time: float = 0.12         ## Throttle time constant falling, s
## Below this the thruster cuts off. Keep small: coarse cut-offs break the
## allocator's balancing of opposing thrusters and cause drift.
@export_range(0.0, 0.2) var min_throttle: float = 0.002
@export var enabled: bool = true
## Short name shown on the HUD thruster page. Empty = node name.
@export var hud_label: String = ""

@export_group("Visuals")
@export var plume_length: float = 7.0             ## Plume length at full thrust, m
## Off for ports built into the armor: only the plume shows, from the model's surface.
@export var show_nozzle: bool = true
@export var nozzle_scale: float = 1.0:
	set(v):
		nozzle_scale = v
		if is_node_ready():
			_visual.scale = Vector3.ONE * v

## Plane normals per thruster in FlightState.thruster_planes (pitch ×2, yaw ×2).
const PLANES := 4

var throttle: float = 0.0                         ## Actual spooled throttle [0, 1]

var _cmd_throttle: float = 0.0
var _cmd_dir := Vector3.FORWARD                   ## Commanded thrust dir, local to this node
var _dir := Vector3.FORWARD                       ## Actual thrust dir, local to this node

@onready var _gimbal: Node3D = $Gimbal
@onready var _visual: Node3D = $Gimbal/Visual
@onready var _plume: Node3D = $Gimbal/Visual/PlumePivot


func _ready() -> void:
	_visual.scale = Vector3.ONE * nozzle_scale
	$Gimbal/Visual/Nozzle.visible = show_nozzle
	_set_layers(self, Layers.VEHICLE_EXT)
	_update_visuals()


## Current thrust in Newtons.
func get_thrust() -> float:
	return throttle * max_thrust if enabled else 0.0


## Actual nozzle deflection, each axis in [-1, 1] of the gimbal limit.
func get_gimbal_deflection() -> Vector2:
	var limit := sin(deg_to_rad(gimbal_limit_deg))
	if limit <= 0.0:
		return Vector2.ZERO
	return Vector2(_dir.x, _dir.y) / limit


func get_hud_label() -> String:
	return hud_label if hud_label != "" else String(name)


## Available thrust for the allocator (0 when disabled).
func get_available_thrust() -> float:
	return max_thrust if enabled else 0.0


func get_cone_rad() -> float:
	return deg_to_rad(gimbal_limit_deg)


## Fore/aft and sideways swing limits as PLANES_PER_THRUSTER plane normals m (the
## direction d is allowed when m·d ≤ 0 for all), in `frame`'s axes. Zero vectors
## where there's no extra limit.
func get_limit_planes_in(frame: Node3D) -> PackedVector3Array:
	var to_frame := frame.global_basis.inverse() * global_basis
	var out := PackedVector3Array()
	for m in _limit_planes():
		out.append((to_frame * m).normalized() if m != Vector3.ZERO else Vector3.ZERO)
	return out


## Local plane normals: pitch atan2(d.y, −d.z) and yaw atan2(d.x, −d.z) stay within
## their limits (two planes each, zero when that limit adds nothing).
func _limit_planes() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	if gimbal_pitch_limit_deg < gimbal_limit_deg:
		var h := deg_to_rad(gimbal_pitch_limit_deg)
		out[0] = Vector3(0.0, cos(h), sin(h))
		out[1] = Vector3(0.0, -cos(h), sin(h))
	if gimbal_yaw_limit_deg < gimbal_limit_deg:
		var h := deg_to_rad(gimbal_yaw_limit_deg)
		out[2] = Vector3(cos(h), 0.0, sin(h))
		out[3] = Vector3(-cos(h), 0.0, sin(h))
	return out


## Nominal thrust direction expressed in `frame`'s local axes.
func get_axis_in(frame: Node3D) -> Vector3:
	return (frame.global_basis.inverse() * -global_basis.z).normalized()


## Nozzle position expressed in `frame`'s local coordinates.
func get_position_in(frame: Node3D) -> Vector3:
	return frame.to_local(_gimbal.global_position)


## throttle_cmd in [0, 1]; direction is the desired thrust direction in `frame`'s axes.
func set_command(throttle_cmd: float, direction: Vector3, frame: Node3D) -> void:
	_cmd_throttle = clampf(throttle_cmd, 0.0, 1.0) if enabled else 0.0
	if direction.length_squared() > 1e-8:
		var local := (global_basis.inverse() * (frame.global_basis * direction)).normalized()
		_cmd_dir = _clamp_to_cone(local)


## Advances actuator dynamics and applies the resulting force to `body`.
func step(delta: float, body: RigidBody3D, has_propellant: bool) -> void:
	var target := _cmd_throttle if has_propellant else 0.0
	var tau := spool_up_time if target > throttle else spool_down_time
	throttle += (target - throttle) * (1.0 - exp(-delta / maxf(tau, 0.001)))
	if target < min_throttle and throttle < min_throttle:
		throttle = 0.0

	var angle := _dir.angle_to(_cmd_dir)
	if angle > 1e-5:
		var max_step := deg_to_rad(gimbal_rate_deg) * delta
		_dir = _dir.slerp(_cmd_dir, minf(1.0, max_step / angle)).normalized()
	_gimbal.basis = Basis.looking_at(_dir, _pick_up(_dir))

	var thrust := get_thrust()
	if thrust > 0.0:
		var force := -_gimbal.global_basis.z.normalized() * thrust
		body.apply_force(force, _gimbal.global_position - body.global_position)
	_update_visuals()


func _clamp_to_cone(local_dir: Vector3) -> Vector3:
	var limit := deg_to_rad(gimbal_limit_deg)
	var angle := Vector3.FORWARD.angle_to(local_dir)
	var d := local_dir
	if limit <= 0.0:
		return Vector3.FORWARD
	if angle > limit:
		d = Vector3.FORWARD.slerp(local_dir, limit / angle).normalized()
	for m in _limit_planes():
		if m.dot(d) > 0.0:
			d = (d - m * m.dot(d)).normalized()
	return d


static func _pick_up(dir: Vector3) -> Vector3:
	return Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT


func _update_visuals() -> void:
	var t := throttle if enabled else 0.0
	_plume.visible = t > 0.0
	if t > 0.0:
		var flicker := 1.0 + randf_range(-0.06, 0.06)
		var radius := lerpf(0.6, 1.0, t)
		_plume.scale = Vector3(radius, plume_length * t * flicker / nozzle_scale, radius)


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)
