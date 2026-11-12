class_name CockpitHatch
extends Node

## Opens and closes the cockpit hatch by rotating skeleton bones, and cuts the
## matching aperture into the panoramic screen.
##
## Everything runs on one timeline `amount` (0 = sealed, 1 = open). Each panel
## and the screen aperture move during their own window of that timeline, so
## opening plays the sequence forward and closing plays it in reverse.

signal state_changed(is_open: bool)

@export var skeleton: Skeleton3D
@export var panels: Array[HatchPanel] = []
## Seconds for a full open or close.
@export var duration: float = 3.0
## Portion of the timeline during which the screen aperture opens.
@export var aperture_window := Vector2(0.0, 0.3)
@export var start_open: bool = false

var amount: float = 0.0

var _target: float = 0.0
var _screen: PanoramicScreen
var _bones: Array[Dictionary] = []


func _ready() -> void:
	_resolve_bones()
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null and vehicle.get_cockpit() != null:
		_screen = vehicle.get_cockpit().get_panoramic_screen()
	amount = 1.0 if start_open else 0.0
	_target = amount
	_apply()


func is_open() -> bool:
	return _target > 0.5


## True while panels are moving or the hatch is not fully sealed.
func is_unsealed() -> bool:
	return amount > 0.0


func open() -> void:
	_set_target(1.0)


func close() -> void:
	_set_target(0.0)


func toggle() -> void:
	_set_target(0.0 if is_open() else 1.0)


func _set_target(value: float) -> void:
	if is_equal_approx(_target, value):
		return
	_target = value
	state_changed.emit(is_open())


func _process(delta: float) -> void:
	# Exact compare: is_equal_approx() would stop a hair short of 0 and the
	# hatch would report unsealed forever.
	if amount == _target:
		return
	amount = move_toward(amount, _target, delta / maxf(duration, 0.01))
	_apply()


func _resolve_bones() -> void:
	_bones.clear()
	if skeleton == null:
		push_error("CockpitHatch: skeleton not assigned")
		return
	for panel in panels:
		var idx := skeleton.find_bone(panel.bone_name)
		if idx < 0:
			push_error("CockpitHatch: bone '%s' not found" % panel.bone_name)
			continue
		var global_rest := skeleton.get_bone_global_rest(idx).basis.get_rotation_quaternion()
		var parent := skeleton.get_bone_parent(idx)
		var parent_rest := skeleton.get_bone_global_rest(parent).basis.get_rotation_quaternion() \
				if parent >= 0 else Quaternion.IDENTITY
		_bones.append({
			"panel": panel,
			"index": idx,
			"rest": skeleton.get_bone_rest(idx).basis.get_rotation_quaternion(),
			"rest_origin": skeleton.get_bone_rest(idx).origin,
			"global_rest": global_rest,
			"parent_rest": parent_rest,
		})


func _apply() -> void:
	for b in _bones:
		var panel: HatchPanel = b.panel
		var t := smoothstep(0.0, 1.0, _window_progress(panel.window))
		var q_skel := Quaternion(panel.hinge_axis.normalized(), deg_to_rad(panel.open_angle_deg) * t)
		# Re-express the skeleton-space hinge rotation in the bone's local frame.
		var g: Quaternion = b.global_rest
		var q_local := g.inverse() * q_skel * g
		skeleton.set_bone_pose_rotation(b.index, (b.rest as Quaternion) * q_local)
		if panel.slide != Vector3.ZERO:
			var local_slide: Vector3 = (b.parent_rest as Quaternion).inverse() * (panel.slide * t)
			skeleton.set_bone_pose_position(b.index, (b.rest_origin as Vector3) + local_slide)
	if _screen != null:
		_screen.set_aperture_amount(smoothstep(0.0, 1.0, _window_progress(aperture_window)))


func _window_progress(window: Vector2) -> float:
	if window.y <= window.x:
		return 1.0 if amount >= window.x else 0.0
	return clampf((amount - window.x) / (window.y - window.x), 0.0, 1.0)
