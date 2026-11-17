extends SceneTree

## Headless check of the sensors' search tracks (every contact the head's wide field or a
## body camera sees): what they know of each contact against the truth, how a new contact
## settles, the hand-over on lock and back, a contact hidden behind a wall going, and
## what a scan costs.
##
##   godot-double --headless --path . -s Tools/Weapons/search_probe.gd

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"


class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		return out

var _suit: RigidBody3D
var _fcs: FireControl
var _sensors: SensorSuite
var _input := ScriptedInput.new()
var _failures := 0


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
	_sensors = _fcs.sensors
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _ticks(2)

	# A far drone, ahead: the head's wide field sees it.
	var drone := _spawn(2000.0, Vector2(10, 5))
	await _ticks(3)
	var early := _report("1st looks", drone)
	await _ticks(180)
	var settled := _report("after 3 s", drone)
	_check("new contact tracked", _fcs.can_see(drone))
	_check("its angle error shrinks as it settles", settled.x < early.x * 0.5)
	_check("its range within 15%", settled.y < 0.15)
	for node in get_nodes_in_group(&"hud_contacts"):
		if node != _suit and node != drone:
			_report("  " + String(node.name), node as Node3D)

	# Lock: the search track carries on as the lock's (no fresh start).
	_fcs.lock(drone)
	await _ticks(1)
	_check("lock takes over the search track", _sensors.track != null and _sensors.track.hits > 10)
	_fcs.lock(null)
	await _ticks(7)
	_check("unlock hands it back to the search", _fcs.can_see(drone) and not _sensors.get_search_estimate(drone).is_empty())

	# Behind a wall: the cameras lose it and the suit forgets it.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 300, 20)
	shape.shape = box
	wall.add_child(shape)
	_suit.get_parent().add_child(wall)
	var dir := (drone.global_position - _fcs.get_view_origin()).normalized()
	wall.global_transform = Transform3D(Basis.looking_at(dir), drone.global_position - dir * 300.0)
	await _ticks(120)
	_check("hidden contact forgotten", not _fcs.can_see(drone))
	wall.queue_free()
	await _ticks(60)
	_check("back once in sight", _fcs.can_see(drone))

	# Cost of a scan, all contacts.
	var t0 := Time.get_ticks_usec()
	for i in 20:
		_sensors._scan()
	print("scan: %.3f ms for %d search tracks" % [(Time.get_ticks_usec() - t0) / 20000.0, _sensors.get_search_contacts().size()])

	print("RESULT: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit()


## Prints what the suit knows of `node`; returns (angle error deg, range error share).
func _report(what: String, node: Node3D) -> Vector2:
	if not _fcs.can_see(node):
		print("%s: not tracked" % what)
		return Vector2(INF, INF)
	var origin := _fcs.get_view_origin()
	var est := _fcs.get_contact_position_now(node)
	var truth := node.global_position
	var angle := rad_to_deg((est - origin).angle_to(truth - origin))
	var range_err := absf((est - origin).length() / (truth - origin).length() - 1.0)
	print("%s: range %.0f m (true %.0f, %.1f%% off), angle off %.3f°, 2σ %.3f°" % [what, (est - origin).length(),
			(truth - origin).length(), range_err * 100.0, angle, _fcs.get_contact_angular_error_deg(node)])
	return Vector2(_fcs.get_contact_angular_error_deg(node), range_err)


func _spawn(distance: float, angles: Vector2) -> TargetDrone:
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.STATIC
	drone.quarry = _suit
	drone.velocity = _suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(angles) * distance
	return drone


func _check(what: String, ok: bool) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
