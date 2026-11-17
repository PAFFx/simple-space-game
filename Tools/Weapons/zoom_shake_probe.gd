extends SceneTree

## Headless, frame by frame: how much the target shakes in the zoom image at ×128. A drone
## crosses 1.5 km out; the suit first holds still, then strafes and turns. Prints, per phase,
## the target's frame-to-frame motion in the zoom image (shake, zoom pixels) and how far
## off the image's centre it sits (mean, worst).
##
##   godot-double --headless --path . --fixed-fps 120 -s Tools/Weapons/zoom_shake_probe.gd

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"


class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	var translation := Vector3.ZERO
	var rotation := Vector3.ZERO
	func poll_command() -> PilotCommand:
		var out := cmd
		out.translation = translation
		out.rotation = rotation
		cmd = PilotCommand.new()
		return out

var _suit: RigidBody3D
var _fcs: FireControl
var _head: SensorHead
var _input := ScriptedInput.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	for i in 10:
		await physics_frame
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
	var vehicle := _suit as Node as VehicleBase
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = vehicle.find_component(FireControl) as FireControl
	_head = vehicle.get_sensor_head()
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await process_frame
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.DRIFT
	drone.quarry = _suit
	drone.velocity = _suit.linear_velocity + _suit.global_basis * Vector3(-60, 15, 0)
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis * SpatialMath.angles_to_direction(Vector2(5, 3)) * 1500.0
	for i in 5:
		await physics_frame
	_fcs.lock(drone)
	for i in 120:
		await physics_frame
	_fcs.zoom_level = _fcs.zoom_levels.size()
	for i in 120:
		await process_frame
	await _measure("suit still", drone, 360)
	_input.translation = Vector3(0.6, 0.0, -0.4)
	_input.rotation = Vector3(0.0, 0.25, 0.0)
	await _measure("strafing and turning", drone, 360)
	quit()


func _measure(what: String, drone: Node3D, frames: int) -> void:
	# Radians per zoom pixel at this level.
	var px := 2.0 * _head.get_zoom_half_tan().y / float(_head.zoom_size.y) / _head.zoom_magnification
	var last := Vector2.INF
	var shake_sq := 0.0
	var off_sum := 0.0
	var off_max := 0.0
	var est_off := 0.0
	var raw_off := 0.0
	var n := 0
	for i in frames:
		await process_frame
		var cam := _head.zoom_basis
		var to := (drone.get_global_transform_interpolated().origin - _head.get_global_transform_interpolated().origin).normalized()
		var depth := to.dot(-cam.z)
		var image := Vector2(to.dot(cam.x), to.dot(cam.y)) / depth / px
		if last != Vector2.INF:
			shake_sq += (image - last).length_squared()
			n += 1
		last = image
		off_sum += image.length()
		var shown := (_fcs.get_shown_target_position() - _head.get_global_transform_interpolated().origin).normalized()
		est_off += shown.angle_to(to) / px
		var truth_now := drone.global_position - _fcs.get_view_origin()
		raw_off += (_fcs.get_target_position() - _fcs.get_view_origin()).angle_to(truth_now) / px
		off_max = maxf(off_max, image.length())
	print("%-22s shake %.2f px/frame rms, off centre %.1f px mean, %.1f px worst; the HUD's target estimate %.1f px off (raw track %.1f px) (×%d, %.2f µrad/px)" % [what,
			sqrt(shake_sq / maxf(n, 1)), off_sum / frames, off_max, est_off / frames, raw_off / frames, roundi(_head.zoom_magnification), px * 1e6])
