extends SceneTree

## FBW response probe (RX-93, scripted input):
##   godot-double --headless --path . -s Tools/Flight/fbw_probe.gd -- <scenario> [series] [law_property=value ...]
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
			"full_fwd_roll", "boost_fwd_roll", "cruise_fwd_roll":
				if on:
					c.translation = Vector3(0, 0, -1)
					c.boost = scenario != "cruise_fwd_roll"
					c.boost_full = scenario == "full_fwd_roll"
				if t >= 2.5 and t < 3.5: c.rotation = Vector3(0, 0, 1)
			"cruise_boost_fwd", "cruise_boost_right", "cruise_boost_down":
				if t >= 0.5:
					c.translation = Vector3(0, 0, -1) if scenario.ends_with("fwd") \
							else (Vector3(1, 0, 0) if scenario.ends_with("right") else Vector3(0, -1, 0))
					c.boost = t >= 2.0
			"brake_yaw", "brake_roll", "brake_full_yaw", "brake_full_pitch", "brake_full_roll", "brake_full_only":
				if on and t < 3.5:
					c.translation = Vector3(0, 0, -1); c.boost = true; c.boost_full = true
				if t >= 3.5:
					c.brake = true
					c.brake_full = scenario.begins_with("brake_full")
				if t >= 4.0 and t < 5.0 and scenario != "brake_full_only":
					c.rotation = Vector3(1, 0, 0) if scenario == "brake_full_pitch" \
							else (Vector3(0, 0, 1) if scenario.ends_with("roll") else Vector3(0, 1, 0))
		return c

var fc: FlightComputer
var body: RigidBody3D
var inp: Scripted
var started := false
var v_prev := Vector3.ZERO
var w_prev := Vector3.ZERO
var series := false
var next_log := 0.0
var duration := 4.0
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
var overrides := PackedStringArray()
var applied := false
var alloc_perp := 0.0
var real_perp := 0.0
var sum_alloc := 0.0
var sum_real := 0.0
var n_perp := 0
var dodge := 0.0
var dodge05 := 0.0
var dodge10 := 0.0
var dodge_v0 := 0.0
var dodge_started := false
var pilot_prev := Quaternion.IDENTITY
var view_turn := 0.0
var view_off := 0.0
var view_coast := 0.0
var view_off_after := 0.0
var view_still := 0.0
var turn_dev := 0.0
var turn_settle := 3.5

func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var suit: Node = load("res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn").instantiate()
	root.add_child(suit)
	fc = suit.get_node("FlightComputer")
	inp = Scripted.new()
	inp.scenario = args[0]
	series = "series" in args
	overrides = args
	if args[0].begins_with("brake"): duration = 10.0
	elif args[0].ends_with("_yaw") or args[0].ends_with("_pitch") or args[0].ends_with("_roll"): duration = 6.5
	fc.add_child(inp)
	fc.input_source = inp
	body = suit as RigidBody3D
	physics_frame.connect(_tick)
	started = true

func _tick() -> void:
	if fc.body == null: return
	if not applied:
		applied = true
		for o in overrides:
			if "=" in o:  # control law property override, e.g. rate_gain=9
				var key := o.get_slice("=", 0)
				var value := float(o.get_slice("=", 1))
				# A vector component: solver.axis_limit_deg.z=40
				var comp := key.get_slice(".", key.get_slice_count(".") - 1)
				if comp in ["x", "y", "z"] and key.get_slice_count(".") >= 3:
					var target: Object = fc.control_law
					var path := key.trim_suffix("." + comp)
					if path.begins_with("solver."):
						target = (fc.control_law as RateCommandControlLaw).attitude_solver
						path = path.trim_prefix("solver.")
					var vec: Vector3 = target.get(path)
					vec["xyz".find(comp)] = value
					target.set(path, vec)
					continue
				if key.begins_with("fc."):
					fc.set(key.trim_prefix("fc."), value)
				elif key.begins_with("solver."):
					(fc.control_law as RateCommandControlLaw).attitude_solver.set(key.trim_prefix("solver."), value)
				elif key.begins_with("alloc."):
					fc.allocator.set(key.trim_prefix("alloc."), value)
				else:
					fc.control_law.set(key, value)
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
	if t >= 2.5: turn_dev = maxf(turn_dev, (law._deviation(body_q) as Vector3).length() * (180.0 / PI))
	if t >= 3.5 and (law._deviation(body_q) as Vector3).length() > deg_to_rad(15.0): turn_settle = t
	# Dodge distance: metres moved along the command 0.5 s and 1 s after it starts
	# (after the reversal at 2.0 s in the reversal scenarios, from the speed held then).
	var t0 := 2.0 if inp.scenario.begins_with("rev") or inp.scenario.begins_with("cruise_boost") else 0.5
	if has_dir and t >= t0 + 2.0 * dt and t < t0 + 1.0 + dt:
		var d := (pilot * cmd.translation).normalized()
		if not dodge_started:
			dodge_started = true
			dodge_v0 = v.dot(d)
		dodge += (v.dot(d) - dodge_v0) * dt
		if t < t0 + 0.5: dodge05 = dodge
		dodge10 = dodge
	# What the pilot sees: the pilot frame's own rotation, split into the commanded axis
	# and everything else, during the turn and after the stick is released.
	var turning := inp.scenario.ends_with("_yaw") or inp.scenario.ends_with("_pitch") or inp.scenario.ends_with("_roll")
	if turning:
		var ts := 4.0 if inp.scenario.begins_with("brake") else 2.5
		var dq := AttitudeOffsetSolver.shortest(pilot_prev.inverse() * pilot)
		var rot := AttitudeOffsetSolver.to_rotation_vector(dq) * (180.0 / PI)   # deg this tick, pilot axes
		var k := 0 if inp.scenario.ends_with("_pitch") else (1 if inp.scenario.ends_with("_yaw") else 2)
		var off_axis := rot
		off_axis[k] = 0.0
		if t >= ts and t < ts + 1.0:
			view_turn += absf(rot[k])
			view_off += off_axis.length()
		elif t >= ts + 1.0:
			view_coast += absf(rot[k])
			view_off_after += off_axis.length()
			if rot.length() / dt > 3.0: view_still = t - ts - 1.0
	pilot_prev = pilot
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
	# Allocation error (ideal actuators) against the demand, and the real force against it.
	var alloc := ConeProjectedAllocator._wrench_of(fc.state, (fc.allocator as ConeProjectedAllocator)._u)
	var aerr := 0.0
	var rerr := 0.0
	if f_cmd.length() > 0.3 * 9.80665 * body.mass:
		aerr = (alloc[0] - f_cmd * (alloc[0].dot(f_cmd) / f_cmd.length_squared())).length() / body.mass / 9.80665
		rerr = (f_act - f_cmd * (f_act.dot(f_cmd) / f_cmd.length_squared())).length() / body.mass / 9.80665
		if t > 0.55:
			alloc_perp = maxf(alloc_perp, aerr)
			real_perp = maxf(real_perp, rerr)
			sum_alloc += aerr; sum_real += rerr; n_perp += 1
	if series and t >= next_log:
		next_log += 0.1
		print("%5.2f tgt %5.1f vel %5.1f |v| %6.1f off %5.1f dev(%5.1f %5.1f %5.1f) lock %d%d%d w(%6.1f %6.1f %6.1f) tq_cmd/max(%5.2f %5.2f %5.2f) tq_act/max(%5.2f %5.2f %5.2f) F %5.2fg(%.2fcap) Fact %5.2fg ferr %4.1f° prio %.2f thr %.2f" % [
			t, rad_to_deg(law._offset_target_r.length()), rad_to_deg(law._offset_vel.length()), v.length(), off, dev.x, dev.y, dev.z, law._locked.x, law._locked.y, law._locked.z,
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
		var from_t := 0.5
		if inp.scenario.begins_with("cruise_boost"):
			end_t = 3.9
			from_t = 2.0
		var sum := 0.0; var n := 0
		for e in a_hist:
			if e[0] > end_t - 0.4 and e[0] <= end_t: sum += e[1]; n += 1
		a_final = sum / maxi(n, 1)
		for e in a_hist:
			if e[0] < from_t: continue
			if t50 < 0.0 and e[1] >= 0.5 * a_final: t50 = e[0] - from_t
			if t90 < 0.0 and e[1] >= 0.9 * a_final: t90 = e[0] - from_t
		s += " a=%5.2fg t50=%.2fs t90=%.2fs  max a⊥=%.2fg  max fpm err=%5.1f°" % [a_final, t50, t90, max_perp_g, max_fpm]
		if inp.scenario.begins_with("rev"):
			var r50 := -1.0; var r90 := -1.0
			for e in a_hist:
				if e[0] >= 2.0:
					if r50 < 0.0 and e[1] >= 0.5 * a_final: r50 = e[0] - 2.0
					if r90 < 0.0 and e[1] >= 0.9 * a_final: r90 = e[0] - 2.0
			s += "  reversal t50=%.2fs t90=%.2fs" % [r50, r90]
	s += "  max ω=%.0f°/s max lag=%.1f°" % [max_rate, max_lag]
	if inp.scenario.ends_with("_yaw") or inp.scenario.ends_with("_pitch") or inp.scenario.ends_with("_roll"):
		s += "  turn: max dev %.1f°, dev>15° until +%.2fs after release" % [turn_dev, turn_settle - 3.5]
	if inp.scenario.begins_with("brake"):
		s = "%-16s brake: max dev %.1f°, dev>15° until +%.2fs after release, max force err %.1f°, stopped (<5 m/s) %.2fs after braking, |v| end %.1f" % [
			inp.scenario, brake_dev, maxf(settle_t - 5.0, 0.0), brake_ferr, stop_t - 3.5 if stop_t > 0.0 else -1.0, body.linear_velocity.length()]
	if not inp.scenario.begins_with("brake"):
		s += "  | moved %.1f m in 0.5 s, %.1f m in 1 s" % [dodge05, dodge10]
	if inp.scenario.ends_with("_yaw") or inp.scenario.ends_with("_pitch") or inp.scenario.ends_with("_roll"):
		s = "%-16s VIEW: turned %.0f° in 1 s, wandered %.1f° off-axis; after release coasted %.1f°, wandered %.1f°, still after %.2fs | body max dev %.0f°" % [
			inp.scenario, view_turn, view_off, view_coast, view_off_after, view_still, maxf(turn_dev, brake_dev)]
	s += "  | off-demand force: alloc max %.2fg avg %.2fg, real max %.2fg avg %.2fg" % [
		alloc_perp, sum_alloc / maxi(n_perp, 1), real_perp, sum_real / maxi(n_perp, 1)]
	print(s)
