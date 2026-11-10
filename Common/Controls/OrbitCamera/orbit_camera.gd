class_name OrbitCamera
extends Camera3D

## External camera that orbits a target in the target's own frame (so it rolls
## with a spacecraft). Mouse orbits, wheel zooms — only while this camera is current.

@export var target: Node3D
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


func _ready() -> void:
	top_level = true
	# Moved every frame from the target's interpolated transform (see _update).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cull_mask = Layers.MASK_THIRD_PERSION
	if target == null:
		target = get_parent() as Node3D
	_update(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_deg -= event.relative.x * sensitivity
		pitch_deg = clampf(pitch_deg - event.relative.y * sensitivity, -89.0, 89.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1)


func _process(delta: float) -> void:
	var weight := 1.0 if follow_lag <= 0.0 else 1.0 - exp(-delta / follow_lag)
	_update(weight)


func _update(weight: float) -> void:
	if target == null:
		return
	var frame := target.get_global_transform_interpolated()
	var orbit := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	var focus := frame * focus_offset
	var desired_basis := frame.basis.orthonormalized() * orbit
	var desired := Transform3D(desired_basis, focus + desired_basis.z * distance)
	global_transform = global_transform.interpolate_with(desired, weight)
