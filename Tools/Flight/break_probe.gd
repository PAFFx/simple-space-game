extends SceneTree

## Breaks from different starting states: level and still, mid-boost (auto-rotated), out
## of a held full boost (released, then tapped again), and reversing a full-boost strafe.
## Measures from the tap, against the path the suit would have coasted along (what the
## break changes): distance along the break, distance off it, attitude at the tap, peak
## body rate during the break.
##
##   godot-double --headless --path . -s Tools/Flight/break_probe.gd -- <case> [no_funnels]
## cases: still_right, boost_fwd_right, full_fwd_right, strafe_reverse, boost_fwd_up

class Scripted extends PilotInputSource:
	var t := 0.0
	var case := ""
	const TAP := 2.0       ## When the break is tapped (after the lead-in)
	func poll_command() -> PilotCommand:
		var c := PilotCommand.new()
		var lead := t >= 0.5 and t < TAP
		var after := t >= TAP
		match case:
			"still_right":
				if after: c.translation = Vector3(1, 0, 0)
			"boost_fwd_right", "boost_fwd_up":
				if lead: c.translation = Vector3(0, 0, -1); c.boost = true
				if after: c.translation = Vector3(1, 0, 0) if case == "boost_fwd_right" else Vector3(0, 1, 0)
			"full_fwd_right":
				# Held full boost forward, let go for a moment, then tapped again sideways.
				if lead: c.translation = Vector3(0, 0, -1); c.boost_full = t < TAP - 0.1; c.boost = c.boost_full
				if after: c.translation = Vector3(1, 0, 0)
			"strafe_reverse":
				if lead: c.translation = Vector3(1, 0, 0); c.boost_full = t < TAP - 0.1; c.boost = c.boost_full
				if after: c.translation = Vector3(-1, 0, 0)
		if after and t < TAP + 0.1:
			c.boost_full = true
			c.boost = true
		return c

var fc: FlightComputer
var body: RigidBody3D
var inp: Scripted
var tapped := false
var p0 := Vector3.ZERO
var v0 := Vector3.ZERO
var dir := Vector3.ZERO
var att := Vector3.ZERO
var w_max := 0.0
var d05 := Vector3.ZERO


func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var suit: Node = load("res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn").instantiate()
	if "no_funnels" in args:
		suit.get_node("Loadout/FinFunnels").free()
	root.add_child(suit)
	body = suit as RigidBody3D
	fc = suit.get_node("FlightComputer")
	inp = Scripted.new()
	inp.case = args[0]
	fc.add_child(inp)
	fc.input_source = inp
	physics_frame.connect(_tick)


func _tick() -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	inp.t += dt
	var t := inp.t
	var com := body.global_transform * body.center_of_mass
	if not tapped and t >= Scripted.TAP:
		tapped = true
		p0 = com
		v0 = body.linear_velocity
		# The break's direction in the world: the stick in the pilot frame.
		var pilot := body.global_basis.orthonormalized().get_rotation_quaternion() * fc.get_pilot_offset().inverse()
		dir = (pilot * inp.poll_command().translation).normalized()
		var e := (fc.get_pilot_offset()).get_euler()
		att = Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	if not tapped:
		return
	var since := t - Scripted.TAP
	if since <= 0.7:
		w_max = maxf(w_max, rad_to_deg(body.angular_velocity.length()))
	if since >= 0.5 and d05 == Vector3.ZERO:
		d05 = com - p0 - v0 * since
	if since >= 1.0:
		var d1 := com - p0 - v0 * since
		print("%-15s attitude at tap (pitch %5.1f yaw %5.1f roll %5.1f) | along the break %4.1f m in 0.5 s, %5.1f m in 1 s | off it %4.1f m at 1 s | peak body rate %3.0f°/s | breaking %s" % [
			inp.case, att.x, att.y, att.z, d05.dot(dir), d1.dot(dir), (d1 - dir * d1.dot(dir)).length(), w_max,
			fc.get_break_direction() != Vector3.ZERO or since < 0.75])
		quit()
