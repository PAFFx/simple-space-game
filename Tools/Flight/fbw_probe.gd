extends SceneTree

## FBW response probe (RX-93, scripted input):
##   godot-double --headless --path . -s Tools/Flight/fbw_probe.gd -- <scenario> [series]
## Tools/Flight/run_fbw_probe.sh runs every scenario.

class Scripted extends PilotInputSource:
	var t := 0.0
	var scenario := ""
	func poll_command() -> PilotCommand:
		var c := PilotCommand.new()
		var on := t >= 0.5
		match scenario:
			"cruise_fwd":
				if on: c.translation = Vector3(0, 0, -1)
			"boost_fwd":
				if on: c.translation = Vector3(0, 0, -1); c.boost = true
			"full_fwd":
				if on: c.translation = Vector3(0, 0, -1); c.boost = true; c.boost_full = true
			"boost_right":
				if on: c.translation = Vector3(1, 0, 0); c.boost = true
			"full_right":
				if on: c.translation = Vector3(1, 0, 0); c.boost = true; c.boost_full = true
			"boost_down":
				if on: c.translation = Vector3(0, -1, 0); c.boost = true
			"full_down":
				if on: c.translation = Vector3(0, -1, 0); c.boost = true; c.boost_full = true
			"full_back":
				if on: c.translation = Vector3(0, 0, 1); c.boost = true; c.boost_full = true
			"boost_diag":
				if on: c.translation = Vector3(1, 0, -1); c.boost = true
			"boost_fwd_yaw", "full_fwd_yaw", "cruise_fwd_yaw":
				if on:
					c.translation = Vector3(0, 0, -1)
					c.boost = scenario != "cruise_fwd_yaw"
					c.boost_full = scenario == "full_fwd_yaw"
				if t >= 2.5 and t < 3.5: c.rotation = Vector3(0, 1, 0)
			"full_fwd_pitch":
				if on: c.translation = Vector3(0, 0, -1); c.boost = true; c.boost_full = true
				if t >= 2.5 and t < 3.5: c.rotation = Vector3(1, 0, 0)
			"reversal", "reversal_full":
				if on:
					c.translation = Vector3(1 if t < 2.0 else -1, 0, 0)
					c.boost = true
					c.boost_full = scenario == "reversal_full"
			"brake_yaw", "brake_full_yaw", "brake_full_pitch", "brake_full_only":
				if on and t < 3.5:
					c.translation = Vector3(0, 0, -1); c.boost = true; c.boost_full = true
				if t >= 3.5:
					c.brake = true
					c.brake_full = scenario != "brake_yaw"
				if t >= 4.0 and t < 5.0 and scenario != "brake_full_only":
					c.rotation = Vector3(1, 0, 0) if scenario == "brake_full_pitch" else Vector3(0, 1, 0)
		return c

var fc: FlightComputer
var body: RigidBody3D
var inp: Scripted
var started := false
var v_prev := Vector3.ZERO
var w_prev := Vector3.ZERO
var series := false
var next_log := 0.0
var duration := 6.0
# accumulators
var a_final := 0.0
var t50 := -1.0
var t90 := -1.0
var max_perp_g := 0.0
var max_fpm := 0.0
var max_rate := 0.0
var max_lag := 0.0
var max_rate_after := 0.0
var settle_t := -1.0
var a_hist: Array = []
var brake_dev := 0.0
var brake_ferr := 0.0
var stop_t := -1.0

func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var suit: Node = load("res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn").instantiate()
	root.add_child(suit)
	fc = suit.get_node("FlightComputer")
	inp = Scripted.new()
	inp.scenario = args[0]
	series = args.size() > 1
	if args[0].begins_with("brake"): duration = 12.0
	fc.add_child(inp)
	fc.input_source = inp
	body = suit as RigidBody3D
	physics_frame.connect(_tick)
	started = true

func _tick() -> void:
	if fc.body == null: return
	var dt := 1.0 / Engine.physics_ticks_per_second
	inp.t += dt
	var t := inp.t
	var v := body.linear_velocity
	var a := (v - v_prev) / dt
	v_prev = v
	var law := fc.control_law as RateCommandControlLaw
	var pilot: Quaternion = law._pilot
	var cmd := inp.last_command
	var w := rad_to_deg(body.angular_velocity.length())
	var body_q := body.global_basis.orthonormalized().get_rotation_quaternion()
	var lag := rad_to_deg(AttitudeOffsetSolver.shortest((pilot * law._offset) * body_q.inverse()).get_angle())
	var off := rad_to_deg(law._offset.get_angle())
	var along := 0.0
	var perp := 0.0
	var fpm := 0.0
	var has_dir := cmd.translation.length() > 0.1
	if has_dir:
		var dir := (pilot * cmd.translation).normalized()
		along = a.dot(dir) / 9.80665
		perp = (a - dir * a.dot(dir)).length() / 9.80665
		if v.length() > 2.0:
			fpm = rad_to_deg(v.angle_to(dir))
		if t > 0.5:
			a_hist.append([t, along])
			max_perp_g = maxf(max_perp_g, perp)
			if t > 1.0: max_fpm = maxf(max_fpm, fpm)
	max_rate = maxf(max_rate, w)
	max_lag = maxf(max_lag, lag)
	if inp.scenario.begins_with("brake"):
		var d := (law._deviation(body_q) as Vector3).length() * (180.0 / PI)
		if stop_t < 0.0 and t >= 3.5 and v.length() < 5.0: stop_t = t
		if t >= 3.8:
			var f_c := fc.last_wrench.force
			var f_a := body.global_basis.orthonormalized().transposed() * a * body.mass
			if f_c.length() > body.mass and f_a.length() > body.mass:
				brake_ferr = maxf(brake_ferr, rad_to_deg(f_c.angle_to(f_a)))
		if t >= 4.0: brake_dev = maxf(brake_dev, d)
		if t >= 5.0:
			max_rate_after = maxf(max_rate_after, w)
			if d > 15.0: settle_t = t
	var w_loc := body.global_basis.orthonormalized().transposed() * body.angular_velocity
	var alpha := (w_loc - w_prev) / dt
	w_prev = w_loc
	var tq_act: Vector3 = fc.state.inertia_local * alpha
	var tq_cmd := fc.last_wrench.torque
	var mt: Vector3 = fc.state.max_torque
	var dev: Vector3 = law._deviation(body_q) * (180.0 / PI)
	var f_cmd := fc.last_wrench.force
	var f_act := body.global_basis.orthonormalized().transposed() * a * body.mass
	var capf := 0.0
	if f_cmd.length() > 1.0: capf = f_cmd.length() / fc.state.force_capability(f_cmd.normalized())
	if series and t >= next_log:
		next_log += 0.1
		print("%5.2f |v| %6.1f off %5.1f dev(%5.1f %5.1f %5.1f) lock %d%d%d w(%6.1f %6.1f %6.1f) tq_cmd/max(%5.2f %5.2f %5.2f) tq_act/max(%5.2f %5.2f %5.2f) F %5.2fg(%.2fcap) Fact %5.2fg ferr %4.1f° prio %.2f thr %.2f" % [
			t, v.length(), off, dev.x, dev.y, dev.z, law._locked.x, law._locked.y, law._locked.z,
			rad_to_deg(w_loc.x), rad_to_deg(w_loc.y), rad_to_deg(w_loc.z),
			tq_cmd.x / mt.x, tq_cmd.y / mt.y, tq_cmd.z / mt.z, tq_act.x / mt.x, tq_act.y / mt.y, tq_act.z / mt.z,
			f_cmd.length() / body.mass / 9.80665, capf, f_act.length() / body.mass / 9.80665,
			rad_to_deg(f_cmd.angle_to(f_act)) if f_cmd.length() > 1.0 and f_act.length() > 1.0 else 0.0,
			fc.last_wrench.torque_priority, fc.get_thrust_fraction()])
	if t >= duration:
		_report()
		quit()

func _report() -> void:
	var s := "%-16s" % inp.scenario
	if a_hist.size() > 10:
		# steady accel = mean of the last 0.5 s before any change at t=2.0
		var end_t := 2.0 if inp.scenario.begins_with("rev") else 2.4
		var sum := 0.0; var n := 0
		for e in a_hist:
			if e[0] > end_t - 0.4 and e[0] <= end_t: sum += e[1]; n += 1
		a_final = sum / maxi(n, 1)
		for e in a_hist:
			if t50 < 0.0 and e[1] >= 0.5 * a_final: t50 = e[0] - 0.5
			if t90 < 0.0 and e[1] >= 0.9 * a_final: t90 = e[0] - 0.5
		s += " a=%5.2fg t50=%.2fs t90=%.2fs  max a⊥=%.2fg  max fpm err=%5.1f°" % [a_final, t50, t90, max_perp_g, max_fpm]
		if inp.scenario.begins_with("rev"):
			var r50 := -1.0; var r90 := -1.0
			for e in a_hist:
				if e[0] >= 2.0:
					if r50 < 0.0 and e[1] >= 0.5 * a_final: r50 = e[0] - 2.0
					if r90 < 0.0 and e[1] >= 0.9 * a_final: r90 = e[0] - 2.0
			s += "  reversal t50=%.2fs t90=%.2fs" % [r50, r90]
	s += "  max ω=%.0f°/s max lag=%.1f°" % [max_rate, max_lag]
	if inp.scenario.begins_with("brake"):
		s = "%-16s brake: max dev %.1f°, dev>15° until +%.2fs after release, max force err %.1f°, stopped (<5 m/s) %.2fs after braking, |v| end %.1f" % [
			inp.scenario, brake_dev, maxf(settle_t - 5.0, 0.0), brake_ferr, stop_t - 3.5 if stop_t > 0.0 else -1.0, body.linear_velocity.length()]
	print(s)
