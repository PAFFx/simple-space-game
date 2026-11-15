extends SceneTree

## Holding a lock at rest must not keep the thrusters firing. DGFT, a static drone locked off
## the nose, the suit at rest; after the aim settles, measures thrust, body rate and the
## limbs' reaction.
##   godot-double --headless --path . -s Tools/Flight/aim_jitter_probe.gd -- [mode] [fps=N]
## Modes: counter (default), hold (no feed-forward), off (LimbReaction disabled).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

class Still extends PilotInputSource:
	var cmd := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		cmd.vulcan_ready = out.vulcan_ready
		return out

var _suit: RigidBody3D
var _fc: FlightComputer
var _fcs: FireControl
var _limbs: LimbReaction
var _input := Still.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "counter"
	for a in args:
		if a.begins_with("fps="):
			Engine.max_fps = int(a.trim_prefix("fps="))
		elif a in ["counter", "hold", "off"]:
			mode = a
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
	_fc = vehicle.find_component(FlightComputer) as FlightComputer
	_fc.add_child(_input)
	_fc.input_source = _input
	_fcs = vehicle.find_component(FireControl) as FireControl
	_limbs = vehicle.find_component(LimbReaction) as LimbReaction
	match mode:
		"hold": _fc.counter_limb_reaction = false
		"off": _limbs.enabled = false

	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	_input.cmd.vulcan_ready = true
	await _ticks(2)
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.STATIC
	drone.quarry = _suit
	drone.velocity = _suit.linear_velocity
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis.orthonormalized() \
			* SpatialMath.angles_to_direction(Vector2(25, 8)) * 800.0
	drone.hit_points = 1e9
	_fcs.lock(drone)
	await _ticks(180)   # aim and body settle

	var rifle := _fcs.get_weapon(&"beam_rifle")
	var n := 0
	var thrust_sum := 0.0
	var thrust_max := 0.0
	var w_sq := 0.0
	var w_max := 0.0
	var tq_sq := 0.0
	var aim_rate_sq := 0.0
	var firing_ticks := 0
	var aim_min := Vector2(INF, INF)
	var aim_max := Vector2(-INF, -INF)
	var max_single := 0.0
	var l_max := 0.0
	var l_sq := 0.0
	var visible_ticks := 0
	for i in 240:
		await physics_frame
		n += 1
		var thrust := _fc.get_thrust_fraction()
		thrust_sum += thrust
		thrust_max = maxf(thrust_max, thrust)
		var on := 0
		for t in _fc.thrusters:
			if t.get_thrust() > 0.002 * t.max_thrust:
				on += 1
		if on > 0:
			firing_ticks += 1
		var shown := false
		for t in _fc.thrusters:
			max_single = maxf(max_single, t.throttle)
			shown = shown or t.throttle > t.park_throttle
		if shown:
			visible_ticks += 1
		var w := rad_to_deg(_suit.angular_velocity.length())
		w_sq += w * w
		w_max = maxf(w_max, w)
		tq_sq += _fc.limb_torque.length_squared()
		l_max = maxf(l_max, _limbs.last_momentum.length())
		l_sq += _limbs.last_momentum.length_squared()
		aim_rate_sq += rifle.aim_rate.length_squared()
		aim_min = aim_min.min(rifle.aim)
		aim_max = aim_max.max(rifle.aim)
	print("%-8s fps %s | thrust avg %.4f max %.4f, firing %d%% of ticks, any above park throttle %d%%, max single %.3f | body rate rms %.3f max %.3f °/s | limb τ rms %.0f N·m, |L| rms %.0f max %.0f N·m·s | rifle aim rate rms %.3f °/s, aim span %s" % [
		mode, str(Engine.max_fps) if Engine.max_fps > 0 else "free", thrust_sum / n, thrust_max, 100 * firing_ticks / n, 100 * visible_ticks / n, max_single,
		sqrt(w_sq / n), w_max, sqrt(tq_sq / n), sqrt(l_sq / n), l_max, sqrt(aim_rate_sq / n), (aim_max - aim_min)])
	quit()


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
