extends SceneTree

## Visible aim jitter: with the suit and a locked target both still, how much the drawn
## rifle muzzle and the right shoulder armour move from frame to frame (their nodes ride
## the bones after every skeleton modifier). A steady hold should be near zero.
##   godot-double --headless --path . -s Tools/Weapons/muzzle_jitter_probe.gd -- [variant] [az,el]
## Variants: normal (default), nosensor (perfect track), noambac (AMBAC off), block (shield up).
## Measured per drawn frame: run it alone (with other Godot runs, several ticks land in one
## frame and the numbers grow several times).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class Still extends PilotInputSource:
	var cmd := PilotCommand.new()
	var block := false
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.shield_block = block
		return out

var _input := Still.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var variant := args[0] if args.size() > 0 else "normal"
	var at := Vector2(25, 8)
	if args.size() > 1:
		var p := args[1].split(",")
		at = Vector2(float(p[0]), float(p[1]))
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	for i in 10:
		await physics_frame
	var vehicle: VehicleBase
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			vehicle = node
	var suit := vehicle as Node as RigidBody3D
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	fc.add_child(_input)
	fc.input_source = _input
	var fcs := vehicle.find_component(FireControl) as FireControl
	if variant == "nosensor":
		fcs.sensors.enabled = false
	if variant == "noambac":
		(vehicle.find_component(AmbacController) as AmbacController).enabled = false
	_input.block = variant == "block"
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	for i in 2:
		await physics_frame
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.STATIC
	drone.quarry = suit
	drone.velocity = suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = fcs.get_view_origin() + suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(at) * 800.0
	drone.hit_points = 1e9
	fcs.lock(drone)
	for i in 240:
		await physics_frame

	var rifle := fcs.get_weapon(&"beam_rifle")
	var muzzle := rifle.get_muzzle()
	var armour := vehicle.find_child("ShUpR", true, false) as Node3D
	var last_dir := Vector3.ZERO
	var last_pos := Vector3.ZERO
	var last_arm := Vector3.ZERO
	var n := 0
	var d_sq := 0.0
	var d_max := 0.0
	var p_sq := 0.0
	var a_sq := 0.0
	var a_max := 0.0
	var aim_sq := 0.0
	var last_aim := rifle.aim
	var sources := {}
	var aim_start := rifle.aim
	for i in 300:
		await process_frame
		if fcs.sensors.enabled:
			var src: String = SensorSuite.Source.keys()[fcs.sensors.source]
			sources[src] = sources.get(src, 0) + 1
		var to_body := suit.global_transform.affine_inverse()
		var dir := (to_body.basis * -muzzle.global_basis.z).normalized()
		var pos := to_body * muzzle.global_position
		var arm := (to_body.basis * armour.global_basis.z).normalized()
		if i > 0:
			var d := rad_to_deg(dir.angle_to(last_dir))
			var a := rad_to_deg(arm.angle_to(last_arm))
			d_sq += d * d
			d_max = maxf(d_max, d)
			p_sq += pos.distance_squared_to(last_pos)
			a_sq += a * a
			a_max = maxf(a_max, a)
			aim_sq += (rifle.aim - last_aim).length_squared()
			n += 1
		last_dir = dir
		last_pos = pos
		last_arm = arm
		last_aim = rifle.aim
	print("  sensor sources %s, aim drift %s over the run, frames %d in %.2f s" % [sources, rifle.aim - aim_start, n, Time.get_ticks_msec() / 1000.0])
	print("%-9s at %s | muzzle dir per frame rms %.4f° max %.4f°, pos rms %.4f m | commanded aim per frame rms %.4f° | shoulder armour rms %.4f° max %.4f°" % [
		variant, at, sqrt(d_sq / n), d_max, sqrt(p_sq / n), sqrt(aim_sq / n), sqrt(a_sq / n), a_max])
	quit()
