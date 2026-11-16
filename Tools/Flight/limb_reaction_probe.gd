extends SceneTree

## Newton's third law check for limb motion on the RX-93: raise the rifle (DGFT), sweep
## its aim, raise the shield guard, stow everything, and watch the body.
##   godot-double --headless --path . -s Tools/Flight/limb_reaction_probe.gd -- <mode> [series]
## Modes:
##   free       FCS off: nothing counters, the body must turn and angular momentum
##              (body + limbs) must stay constant
##   counter    FCS on, the limbs' reaction countered by AMBAC + thrusters (default)
##   hold       FCS on, no feed-forward: only the attitude hold reacts
##   off        LimbReaction disabled (the old behaviour: limbs push nothing)

class Scripted extends PilotInputSource:
	var t := 0.0
	var mode_sent := {}
	func poll_command() -> PilotCommand:
		var c := PilotCommand.new()
		if t >= 0.5 and not mode_sent.has(0):
			mode_sent[0] = true
			c.master_mode = FireControl.MasterMode.DGFT
		if t >= 9.0 and not mode_sent.has(1):
			mode_sent[1] = true
			c.master_mode = FireControl.MasterMode.NAV
		c.shield_block = t >= 6.5 and t < 8.5
		return c

var fc: FlightComputer
var body: RigidBody3D
var inp: Scripted
var fcs: FireControl
var limbs: LimbReaction
var mode := "counter"
var series := false
var q0 := Quaternion.IDENTITY
var max_dev := 0.0
var max_rate := 0.0
var max_drift := 0.0
var l_start := Vector3.ZERO
var started := false
var next_log := 0.0
var max_thrust := 0.0
var sum_thrust := 0.0
var ticks := 0

func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mode = args[0]
	series = "series" in args
	var suit: Node = load("res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn").instantiate()
	root.add_child(suit)
	body = suit as RigidBody3D
	fc = suit.get_node("FlightComputer")
	fcs = (suit as VehicleBase).find_component(FireControl) as FireControl
	limbs = (suit as VehicleBase).find_component(LimbReaction) as LimbReaction
	inp = Scripted.new()
	fc.add_child(inp)
	fc.input_source = inp
	match mode:
		"free": fc.fcs_enabled = false
		"hold": fc.counter_limb_reaction = false
		"off": limbs.enabled = false
	physics_frame.connect(_tick)

func _tick() -> void:
	if fc.body == null: return
	var dt := 1.0 / Engine.physics_ticks_per_second
	inp.t += dt
	var t := inp.t
	var rifle := fcs.get_weapon(&"beam_rifle")
	if rifle != null:
		if t >= 2.5 and t < 4.0: rifle.aim_override = Vector2(60, 0)
		elif t >= 4.0 and t < 5.5: rifle.aim_override = Vector2(-30, 30)
		else: rifle.aim_override = null
	var q := body.global_basis.orthonormalized().get_rotation_quaternion()
	if t < 0.3:
		q0 = q
		l_start = _total_momentum()
		return
	var dev := rad_to_deg(AttitudeOffsetSolver.shortest(q * q0.inverse()).get_angle())
	var w := rad_to_deg(body.angular_velocity.length())
	max_dev = maxf(max_dev, dev)
	max_rate = maxf(max_rate, w)
	var drift := (_total_momentum() - l_start).length()
	max_drift = maxf(max_drift, drift)
	var thrust := fc.get_thrust_fraction()
	max_thrust = maxf(max_thrust, thrust)
	sum_thrust += thrust
	ticks += 1
	if series and t >= next_log:
		next_log += 0.25
		var w_loc := body.global_basis.orthonormalized().transposed() * body.angular_velocity
		print("%5.2f dev %6.2f° w(%6.2f %6.2f %6.2f)°/s limbL(%8.0f %8.0f %8.0f) dist(%7.0f %7.0f %7.0f) |ΔL| %7.0f thr %.3f" % [
			t, dev, rad_to_deg(w_loc.x), rad_to_deg(w_loc.y), rad_to_deg(w_loc.z),
			limbs.last_momentum.x, limbs.last_momentum.y, limbs.last_momentum.z,
			fc.limb_disturbance.x, fc.limb_disturbance.y, fc.limb_disturbance.z, drift, thrust])
	if t >= 11.0:
		print("%-8s max attitude change %.2f°, max rate %.2f°/s, end rate %.3f°/s, end change %.2f° | momentum drift max %.0f N·m·s | thrust max %.3f avg %.4f" % [
			mode, max_dev, max_rate, w, dev, max_drift, max_thrust, sum_thrust / maxi(ticks, 1)])
		quit()

## Body + tracked limbs angular momentum in the world (about the body's COM).
func _total_momentum() -> Vector3:
	var ds := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var l_body := ds.inverse_inertia_tensor.inverse() * body.angular_velocity
	return l_body + body.global_basis.orthonormalized() * limbs.last_momentum
