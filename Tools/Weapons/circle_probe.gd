extends SceneTree

## Headless: the gun solution circle's inputs against a drifting and a jinking drone, with
## the sensors on. Prints the track's predicted miss at the time of flight, the target's
## agility and the dodge it makes good, against the target's size.
##
##   godot-double --headless --path . -s Tools/Weapons/circle_probe.gd

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"


class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		return out

var _suit: RigidBody3D
var _fcs: FireControl
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
	await _ticks(10)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
	var vehicle := _suit as Node as VehicleBase
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	_fcs = vehicle.find_component(FireControl) as FireControl
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _ticks(2)
	_fcs.draw_now()   # skip the rifle draw
	for case in [["drift", TargetDrone.Behaviour.DRIFT, 0.0], ["jink 3 G", TargetDrone.Behaviour.JINK, 3.0],
			["jink 6 G", TargetDrone.Behaviour.JINK, 6.0]]:
		for distance in [800.0, 2000.0]:
			var drone := TargetDrone.new()
			drone.behaviour = case[1]
			drone.quarry = _suit
			drone.jink_accel_g = maxf(case[2], 0.1)
			drone.jink_interval = Vector2(0.5, 1.2)
			drone.velocity = _suit.linear_velocity + _suit.global_basis * Vector3(-40, 10, 0)
			current_scene.add_child(drone)
			drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
					* SpatialMath.angles_to_direction(Vector2(8, 4)) * distance
			await _ticks(2)
			_fcs.lock(drone)
			await _ticks(180)
			var sum := Vector3.ZERO
			var last_v := drone.velocity
			var mean := Vector3.ZERO
			var true_sq := 0.0
			for i in 120:
				await _ticks(1)
				var a := (drone.velocity - last_v) * 60.0
				last_v = drone.velocity
				var los_t := (drone.global_position - _fcs.get_view_origin()).normalized()
				a -= los_t * a.dot(los_t)
				mean = mean.lerp(a, 1.0 - exp(-1.0 / 60.0))
				true_sq += (a - mean).length_squared() / 120.0
				var weapon := _fcs.selected
				var tof := weapon.time_of_flight
				var cov := _fcs.get_target_covariance_ahead(tof)
				var rel := _fcs.get_target_position() - _fcs.get_view_origin()
				var los := rel.normalized()
				var lateral := sqrt(maxf((cov.x.x + cov.y.y + cov.z.z - los.dot(cov * los)) * 0.5, 0.0))
				sum += Vector3(2.0 * lateral, 0.5 * _fcs.get_target_agility() * tof * tof, _fcs.get_target_agility())
			sum /= 120.0
			var miss := sqrt(sum.x * sum.x + sum.y * sum.y)
			print("   true jink (high-passed, across) %.1f m/s²" % sqrt(true_sq))
			print("%-9s %4.0f m: tof %.2f s  prediction 2σ %.1f m  agility %.1f m/s²  dodge %.1f m  miss/R %.2f  circle %.2f× min" % [
				case[0], distance, _fcs.selected.time_of_flight, sum.x, sum.z, sum.y, miss / _fcs.get_target_radius(),
				sqrt(1.0 + pow(miss / _fcs.get_target_radius(), 2.0))])
			_fcs.lock(null)
			drone.queue_free()
			await _ticks(5)
	quit()


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
