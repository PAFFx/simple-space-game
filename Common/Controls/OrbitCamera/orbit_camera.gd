class_name OrbitCamera
extends Camera3D

## External camera that orbits a target (so it rolls with a spacecraft). Mouse
## or the look mini-stick orbits (the mouse unless it is steering the suit), a tap of the
## stick's button recentres, wheel zooms — only while this camera is current.
##
## Orientation comes from the pilot frame (the vehicle's cockpit) by default, so
## the view stays steady while the FCS turns the body for thrust vectoring and
## the suit visibly leans and rolls inside it. Position always follows the target.

@export var target: Node3D
## Orbit in the pilot's axes (the vehicle cockpit's orientation) instead of the body's.
@export var follow_pilot_frame: bool = true
## Optional explicit node to take the orbit orientation from (overrides follow_pilot_frame).
@export var orientation_source: Node3D
## Point in the target's local space to orbit around.
@export var focus_offset := Vector3(0.0, 11.0, 0.0)
@export var distance: float = 40.0
@export var min_distance: float = 8.0
@export var max_distance: float = 300.0
@export var sensitivity: float = 0.15  ## deg per pixel
@export var yaw_deg: float = 150.0
@export var pitch_deg: float = -10.0
## Follow smoothing time constant, s. 0 = rigid.
@export var follow_lag: float = 0.08
## Mini-stick orbit, as for the pilot camera; empty = a StickLook with its defaults.
@export var stick: StickLook

var _rest := Vector2.ZERO   ## (yaw, pitch) to recentre to, deg
var _recentering := false


func _ready() -> void:
	top_level = true
	if stick == null:
		stick = StickLook.new()
	_rest = Vector2(yaw_deg, pitch_deg)
	# Moved every frame from the target's interpolated transform (see _update).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cull_mask = Layers.MASK_THIRD_PERSION
	if target == null:
		target = get_parent() as Node3D
	if orientation_source == null and follow_pilot_frame and target != null:
		var vehicle := target as VehicleBase if target is VehicleBase \
				else VehicleBase.find_vehicle(target)
		if vehicle != null:
			orientation_source = vehicle.get_cockpit()
	_update(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not PilotInputActions.is_mouse_steering():
		_recentering = false
		yaw_deg -= event.relative.x * sensitivity
		pitch_deg = clampf(pitch_deg - event.relative.y * sensitivity, -89.0, 89.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1)


func _process(delta: float) -> void:
	stick.update(delta)
	if current:
		_stick_orbit(delta)
	var weight := 1.0 if follow_lag <= 0.0 else 1.0 - exp(-delta / follow_lag)
	_update(weight)


func _stick_orbit(delta: float) -> void:
	if stick.tapped:
		_recentering = true
	if stick.moving:
		_recentering = false
	if _recentering:
		var w := 1.0 - exp(-delta / maxf(stick.recenter_time, 0.001))
		# Shortest way round in yaw.
		yaw_deg = _rest.x + wrapf(yaw_deg - _rest.x, -180.0, 180.0)
		yaw_deg = lerpf(yaw_deg, _rest.x, w)
		pitch_deg = lerpf(pitch_deg, _rest.y, w)
		_recentering = absf(yaw_deg - _rest.x) > 0.01 or absf(pitch_deg - _rest.y) > 0.01
		return
	yaw_deg -= stick.pan.x * delta
	pitch_deg = clampf(pitch_deg + stick.pan.y * delta, -89.0, 89.0)


func _update(weight: float) -> void:
	if target == null:
		return
	var frame := target.get_global_transform_interpolated()
	var axes := frame.basis
	if orientation_source != null:
		axes = orientation_source.get_global_transform_interpolated().basis
	var orbit := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	var focus := frame * focus_offset
	var desired_basis := axes.orthonormalized() * orbit
	var desired := Transform3D(desired_basis, focus + desired_basis.z * distance)
	global_transform = global_transform.interpolate_with(desired, weight)
