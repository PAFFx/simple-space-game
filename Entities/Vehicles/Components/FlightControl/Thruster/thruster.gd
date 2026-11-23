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
@export_range(0.0, 60.0) var gimbal_limit_deg: float = 20.0:
	set(value):
		gimbal_limit_deg = value
		_planes_local.clear()
## Tighter limit on the fore/aft swing (about the node's local X axis), deg. At or
## above gimbal_limit_deg it adds nothing. Lets a nozzle swing wide sideways but only
## a little fore and aft.
@export_range(0.0, 90.0) var gimbal_pitch_limit_deg: float = 90.0:
	set(value):
		gimbal_pitch_limit_deg = value
		_planes_local.clear()
## Centre of the fore/aft range, deg: the swing runs bias ± pitch limit, so a nozzle can
## rest at one end of its range (e.g. a calf plate that only swings back, away from the leg).
@export_range(-60.0, 60.0) var gimbal_pitch_bias_deg: float = 0.0:
	set(value):
		gimbal_pitch_bias_deg = value
		_planes_local.clear()
## Same for the sideways swing (about local Y). 0 = the nozzle only swings fore/aft
## (one-plane, "2D" vectoring); gimbal_limit_deg 0 = fixed nozzle.
@export_range(0.0, 90.0) var gimbal_yaw_limit_deg: float = 90.0:
	set(value):
		gimbal_yaw_limit_deg = value
		_planes_local.clear()
## Centre of the sideways range, deg (bias ± yaw limit), e.g. a nozzle that can only swing
## outward because something sits on its inner side.
@export_range(-60.0, 60.0) var gimbal_yaw_bias_deg: float = 0.0:
	set(value):
		gimbal_yaw_bias_deg = value
		_planes_local.clear()
## For a nozzle in a pod that swings about a hinge away from the nozzle (e.g. a backpack
## pod hanging from the top): that hinge, local to this node. The nozzle (where the force
## acts and the plume starts) then swings around it with the gimbal. Zero = gimbal in place.
@export var swing_pivot := Vector3.ZERO
@export var gimbal_rate_deg: float = 120.0        ## Max gimbal slew, deg/s
## Sideways slew (about local Y) when it differs from the fore/aft one, deg/s; 0 = same.
## E.g. a nozzle that swings sideways on its own inside a pod that pivots fore/aft.
@export var gimbal_yaw_rate_deg: float = 0.0
@export var spool_up_time: float = 0.25           ## Throttle time constant rising, s
@export var spool_down_time: float = 0.12         ## Throttle time constant falling, s
## Below this the thruster cuts off. Keep small: coarse cut-offs break the
## allocator's balancing of opposing thrusters and cause drift.
@export_range(0.0, 0.2) var min_throttle: float = 0.002
## Below this commanded throttle the nozzle parks back at centre (an idle nozzle doesn't
## keep its last aim).
@export_range(0.0, 0.2) var park_throttle: float = 0.01
@export var enabled: bool = true
## Short name shown on the HUD thruster page. Empty = node name.
@export var hud_label: String = ""

@export_group("Visuals")
@export var plume_length: float = 7.0             ## Plume length at full thrust, m
## Off for ports built into the armor: only the plume shows, from the model's surface.
@export var show_nozzle: bool = true
## Slot-shaped port: the plume is stretched into a flat sheet along this direction (local),
## as long as the vector, instead of a round jet. Zero = round.
@export var plume_slot := Vector3.ZERO
@export var nozzle_scale: float = 1.0:
	set(v):
		nozzle_scale = v
		if is_node_ready():
			_visual.scale = Vector3.ONE * v
## Shader plume (turbulence, shock diamonds, nozzle flare) instead of the plain cones.
@export var exhaust_fx: bool = false
## Energy of a light at the nozzle that lights the suit while firing (exhaust_fx only). 0 = none.
@export var glow_light_energy: float = 0.0
@export var glow_light_color := Color(0.6, 0.8, 1.0)

## Plane normals per thruster in FlightState.thruster_planes (pitch ×2, yaw ×2).
const PLANES := 4
## Diameter of the plume mesh's base at nozzle_scale 1, m.
const PLUME_BASE_WIDTH := 0.76
## Shock diamond spacing, in nozzle widths.
const DIAMOND_SPACING := 1.7
## FxCore's length as a fraction of the plume's (its scale in the scene).
const FX_CORE_LENGTH := 0.6

var throttle: float = 0.0                         ## Actual spooled throttle [0, 1]
## Pintle throat factor (FlightComputer, burst): thrust ×this at the same throttle and
## chamber pressure, Isp ÷this. 1 = rated throat.
var throat_factor: float = 1.0

## _limit_planes(), kept until a gimbal setting changes (their setters clear it).
var _planes_local: Array[Vector3] = []
var _gimbal_dir := Vector3(NAN, NAN, NAN)       ## The aim and pivot the gimbal node was last set to
var _gimbal_pivot := Vector3.ZERO
var _cmd_throttle: float = 0.0
var _cmd_dir := Vector3.FORWARD                   ## Commanded thrust dir, local to this node
var _dir := Vector3.FORWARD                       ## Actual thrust dir, local to this node

@onready var _gimbal: Node3D = $Gimbal
@onready var _visual: Node3D = $Gimbal/Visual
@onready var _plume: Node3D = $Gimbal/Visual/PlumePivot


var _slot_ratio := 1.0                            ## Plume width along the slot / round width
var _fx_plume: GeometryInstance3D
var _fx_core: GeometryInstance3D
var _glow: GeometryInstance3D
var _light: OmniLight3D
var _flicker := 1.0


func _ready() -> void:
	_visual.scale = Vector3.ONE * nozzle_scale
	$Gimbal/Visual/Nozzle.visible = show_nozzle
	if plume_slot != Vector3.ZERO:
		# Turn the plume about its own axis so its local X runs along the slot.
		var y := _plume.global_basis.y.normalized()
		var x := global_basis * plume_slot
		x = (x - y * x.dot(y)).normalized()
		_plume.global_basis = Basis(x, y, x.cross(y))
		_slot_ratio = maxf(1.0, plume_slot.length() / (PLUME_BASE_WIDTH * nozzle_scale))
	if exhaust_fx:
		_setup_fx()
	_set_layers(self, Layers.VEHICLE_EXT)
	_update_visuals()


func _setup_fx() -> void:
	_plume.get_node("Plume").visible = false
	_plume.get_node("Core").visible = false
	_fx_plume = _plume.get_node("FxPlume")
	_fx_core = _plume.get_node("FxCore")
	_glow = $Gimbal/Visual/Glow
	_fx_plume.visible = true
	_fx_core.visible = true
	var noise_seed := randf() * 100.0
	_fx_plume.set_instance_shader_parameter("seed", noise_seed)
	_fx_core.set_instance_shader_parameter("seed", noise_seed + 31.0)
	if glow_light_energy > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = glow_light_color
		_light.omni_range = maxf(4.0, plume_length * 0.6)
		_light.omni_attenuation = 1.5
		_light.position = Vector3(0.0, 0.0, 1.2)
		_light.visible = false
		$Gimbal/Visual.add_child(_light)


## Current thrust in Newtons.
func get_thrust() -> float:
	return throttle * max_thrust * throat_factor if enabled else 0.0


## Actual nozzle deflection, each axis in [-1, 1] of the gimbal limit.
func get_gimbal_deflection() -> Vector2:
	var limit := sin(deg_to_rad(gimbal_limit_deg))
	if limit <= 0.0:
		return Vector2.ZERO
	return Vector2(_dir.x, _dir.y) / limit


## Actual sideways swing, rad: atan2(d.x, −d.z) of the thrust direction (+ tips it to +X).
func get_yaw() -> float:
	return atan2(_dir.x, -_dir.z)


## Actual swing from the nominal aim as the shortest rotation, in this node's axes.
func get_gimbal_rotation() -> Quaternion:
	return Quaternion(Vector3.FORWARD, _dir)


func get_hud_label() -> String:
	return hud_label if hud_label != "" else String(name)


## Available thrust for the allocator (0 when disabled).
func get_available_thrust() -> float:
	return max_thrust * throat_factor if enabled else 0.0


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


## get_position_in, get_axis_in and get_limit_planes_in (appended to `planes`) for a
## frame given by its inverse (global → frame): the flight computer inverts the body once
## a tick instead of once per thruster per call. Same arithmetic, same results.
func get_position_in_inverse(to_frame: Transform3D) -> Vector3:
	return to_frame * _gimbal.global_position


func get_axis_in_inverse(to_frame: Basis) -> Vector3:
	return (to_frame * -global_basis.z).normalized()


func append_limit_planes_in_inverse(to_frame: Basis, planes: PackedVector3Array) -> void:
	var b := to_frame * global_basis
	if _planes_local.is_empty():
		_planes_local = _limit_planes()
	for m in _planes_local:
		planes.append((b * m).normalized() if m != Vector3.ZERO else Vector3.ZERO)


## Local plane normals: pitch atan2(d.y, −d.z) and yaw atan2(d.x, −d.z) stay within
## their limits (two planes each, zero when that limit adds nothing).
func _limit_planes() -> Array[Vector3]:
	var out: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	if gimbal_pitch_limit_deg < gimbal_limit_deg or gimbal_pitch_bias_deg != 0.0:
		var hi := deg_to_rad(gimbal_pitch_bias_deg + gimbal_pitch_limit_deg)
		var lo := deg_to_rad(gimbal_pitch_bias_deg - gimbal_pitch_limit_deg)
		out[0] = Vector3(0.0, cos(hi), sin(hi))
		out[1] = Vector3(0.0, -cos(lo), -sin(lo))
	if gimbal_yaw_limit_deg < gimbal_limit_deg or gimbal_yaw_bias_deg != 0.0:
		var hi := deg_to_rad(gimbal_yaw_bias_deg + gimbal_yaw_limit_deg)
		var lo := deg_to_rad(gimbal_yaw_bias_deg - gimbal_yaw_limit_deg)
		out[2] = Vector3(cos(hi), 0.0, sin(hi))
		out[3] = Vector3(-cos(lo), 0.0, -sin(lo))
	return out


## Actual (gimballed) thrust direction, global.
func get_thrust_direction_global() -> Vector3:
	return -_gimbal.global_basis.z.normalized()


## Nominal (un-gimballed) thrust direction, global.
func get_nominal_direction_global() -> Vector3:
	return -global_basis.z.normalized()


## Nominal thrust direction expressed in `frame`'s local axes.
func get_axis_in(frame: Node3D) -> Vector3:
	return (frame.global_basis.inverse() * -global_basis.z).normalized()


## Nozzle position expressed in `frame`'s local coordinates.
func get_position_in(frame: Node3D) -> Vector3:
	return frame.to_local(_gimbal.global_position)


## throttle_cmd in [0, 1]; direction is the desired thrust direction in `frame`'s axes.
func set_command(throttle_cmd: float, direction: Vector3, frame: Node3D) -> void:
	_cmd_throttle = clampf(throttle_cmd, 0.0, 1.0) if enabled else 0.0
	if _cmd_throttle < park_throttle:
		_cmd_dir = Vector3.FORWARD
	elif direction.length_squared() > 1e-8:
		var local := (global_basis.inverse() * (frame.global_basis * direction)).normalized()
		_cmd_dir = _clamp_to_cone(local)


## Where the nozzle will point after this tick's slew toward the commanded aim, in
## `frame`'s axes.
func predict_direction_in(frame: Node3D, delta: float) -> Vector3:
	return (frame.global_basis.inverse() * (global_basis * _slewed(delta))).normalized()


## Throttle range reachable this tick: x = lowest, y = highest.
func reachable_throttle(delta: float) -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var down := exp(-delta / maxf(spool_down_time, 0.001))
	var up := 1.0 - exp(-delta / maxf(spool_up_time, 0.001))
	return Vector2(throttle * down, throttle + (1.0 - throttle) * up)


## Sets the throttle the thruster should have *after* this tick (within
## reachable_throttle()), keeping the aim from set_command(): the valve is driven past
## it so the spool lag lands exactly there.
func set_throttle_now(wanted: float, delta: float) -> void:
	if not enabled:
		_cmd_throttle = 0.0
		return
	var tau := spool_up_time if wanted > throttle else spool_down_time
	var k := 1.0 - exp(-delta / maxf(tau, 0.001))
	_cmd_throttle = clampf(throttle + (wanted - throttle) / k, 0.0, 1.0)
	if wanted < min_throttle:
		_cmd_throttle = 0.0


## Advances actuator dynamics and applies the resulting force to `body`.
func step(delta: float, body: RigidBody3D, has_propellant: bool) -> void:
	var target := _cmd_throttle if has_propellant else 0.0
	var tau := spool_up_time if target > throttle else spool_down_time
	throttle += (target - throttle) * (1.0 - exp(-delta / maxf(tau, 0.001)))
	if target < min_throttle and throttle < min_throttle:
		throttle = 0.0

	_dir = _slewed(delta)
	# Only when the aim moved: re-setting the same transform still notifies the nozzle's
	# subtree (plume, glow, light), for every parked thruster every tick.
	if _dir != _gimbal_dir or swing_pivot != _gimbal_pivot:
		_gimbal_dir = _dir
		_gimbal_pivot = swing_pivot
		_gimbal.basis = Basis.looking_at(_dir, _pick_up(_dir))
		if swing_pivot != Vector3.ZERO:
			_gimbal.position = swing_pivot + Quaternion(Vector3.FORWARD, _dir) * -swing_pivot

	var thrust := get_thrust()
	if thrust > 0.0:
		var force := -_gimbal.global_basis.z.normalized() * thrust
		body.apply_force(force, _gimbal.global_position - body.global_position)
	_update_visuals()


## Nozzle aim after slewing toward the command for `delta` (local axes).
func _slewed(delta: float) -> Vector3:
	var angle := _dir.angle_to(_cmd_dir)
	if angle <= 1e-5:
		return _dir
	if gimbal_yaw_rate_deg <= 0.0 or _dir.z > -0.05 or _cmd_dir.z > -0.05:
		return _dir.slerp(_cmd_dir, minf(1.0, deg_to_rad(gimbal_rate_deg) * delta / angle)).normalized()
	# Fore/aft (about X) and sideways (about Y) swing separately, each at its own rate.
	var pitch := atan2(_dir.y, -_dir.z)
	var yaw := atan2(_dir.x, -_dir.z)
	pitch = move_toward(pitch, atan2(_cmd_dir.y, -_cmd_dir.z), deg_to_rad(gimbal_rate_deg) * delta)
	yaw = move_toward(yaw, atan2(_cmd_dir.x, -_cmd_dir.z), deg_to_rad(gimbal_yaw_rate_deg) * delta)
	return Vector3(tan(yaw), tan(pitch), -1.0).normalized()


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
	if _glow:
		_glow.visible = t > 0.0
	if _light:
		_light.visible = t > 0.0
	if t <= 0.0:
		return
	var radius := lerpf(0.6, 1.0, t)
	if not exhaust_fx:
		var flicker := 1.0 + randf_range(-0.06, 0.06)
		_plume.scale = Vector3(radius * _slot_ratio, plume_length * t * flicker / nozzle_scale, radius)
		return
	# The shader adds the turbulence, so the length only wavers gently.
	_flicker = lerpf(_flicker, 1.0 + randf_range(-0.04, 0.04), 0.35)
	var plume_len := plume_length * t * _flicker
	_plume.scale = Vector3(radius * _slot_ratio, plume_len / nozzle_scale, radius)
	var diamonds := plume_len / (DIAMOND_SPACING * PLUME_BASE_WIDTH * nozzle_scale * radius)
	_fx_plume.set_instance_shader_parameter("throttle", t)
	_fx_plume.set_instance_shader_parameter("length_m", plume_len)
	_fx_plume.set_instance_shader_parameter("diamonds", diamonds)
	_fx_core.set_instance_shader_parameter("throttle", t)
	_fx_core.set_instance_shader_parameter("length_m", plume_len * FX_CORE_LENGTH)
	_fx_core.set_instance_shader_parameter("diamonds", diamonds * FX_CORE_LENGTH)
	_glow.scale = Vector3.ONE * 1.8 * radius * sqrt(_slot_ratio) * _flicker
	_glow.set_instance_shader_parameter("throttle", t)
	if _light:
		_light.light_energy = glow_light_energy * t * _flicker


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)
