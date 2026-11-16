extends SceneTree

## RX-93 mass model check:
##   godot-double --headless --path . -s Tools/Flight/mass_model_probe.gd -- [mode] [series]
## Modes:
##   report   part masses, centre of mass and inertia full / empty, AMBAC joint inertias
##   free     FCS off; the legs swing through the climb and strafe stances and the rifle
##            arm aims: nothing pushes the suit, so its centre of mass must stay where it
##            is (the hull moves instead) and its angular momentum must stay constant
##   drain    FCS off; propellant drains from full to empty over 4 s: the suit's centre
##            of mass must not jump

class Idle extends PilotInputSource:
	var t := 0.0
	func poll_command() -> PilotCommand:
		var c := PilotCommand.new()
		if t >= 0.5 and t < 0.6:
			c.master_mode = FireControl.MasterMode.DGFT
		return c

var fc: FlightComputer
var body: RigidBody3D
var limbs: LimbReaction
var ambac: AmbacController
var fcs: FireControl
var inp: Idle
var mode := "report"
var series := false
var t := 0.0
var com0 := Vector3.ZERO
var l0 := Vector3.ZERO
var max_com := 0.0
var max_l := 0.0
var max_hull := 0.0
var hull0 := Vector3.ZERO
var next_log := 0.0
var l_scale := 1.0

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
	limbs = (suit as VehicleBase).find_component(LimbReaction) as LimbReaction
	ambac = (suit as VehicleBase).find_component(AmbacController) as AmbacController
	fcs = (suit as VehicleBase).find_component(FireControl) as FireControl
	inp = Idle.new()
	fc.add_child(inp)
	fc.input_source = inp
	if mode != "report":
		fc.fcs_enabled = false
	physics_frame.connect(_tick)

func _world_com() -> Vector3:
	var ds := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return body.global_position + ds.center_of_mass

func _momentum() -> Vector3:
	var ds := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return ds.inverse_inertia_tensor.inverse() * body.angular_velocity \
			+ body.global_basis.orthonormalized() * limbs.last_momentum

func _tick() -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	t += dt
	inp.t = t
	match mode:
		"report":
			if t >= 0.6:
				_report()
				quit()
			return
		"free":
			_drive_limbs(dt)
		"drain":
			if t >= 1.0:
				fc.propellant = fc.propellant_capacity * clampf(1.0 - (t - 1.0) / 4.0, 0.0, 1.0)
	if t < 0.5:
		com0 = _world_com()
		l0 = _momentum()
		hull0 = body.global_position
		return
	var com_drift := (_world_com() - com0).length()
	var l_drift := (_momentum() - l0).length()
	max_com = maxf(max_com, com_drift)
	max_l = maxf(max_l, l_drift)
	max_hull = maxf(max_hull, (body.global_position - hull0).length())
	if series and t >= next_log:
		next_log += 0.25
		print("%5.2f com(body) %s  world com drift %.4f m  hull moved %.3f m  |ΔL| %.0f  w %.2f°/s" % [
			t, limbs.centre_of_mass, com_drift, (body.global_position - hull0).length(), l_drift,
			rad_to_deg(body.angular_velocity.length())])
	if t >= 10.0:
		var ds := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var peak := ds.inverse_inertia_tensor.inverse() * Vector3(0, 0, deg_to_rad(10.0))
		print("%-6s world com drift max %.4f m, hull moved max %.3f m, momentum drift max %.0f N·m·s (%.2f%% of 10°/s roll), end rate %.3f°/s, body com %s" % [
			mode, max_com, max_hull, max_l, 100.0 * max_l / peak.length(), rad_to_deg(body.angular_velocity.length()), limbs.centre_of_mass])
		quit()

## Climb stance, then strafe right, then back, while the rifle aims around.
func _drive_limbs(dt: float) -> void:
	var poses := []
	if t >= 1.0 and t < 3.5:
		poses = [["thigh.R", Vector3.RIGHT, 25.0], ["shin.R", Vector3.RIGHT, -35.0],
				["thigh.L", Vector3.RIGHT, 25.0], ["shin.L", Vector3.RIGHT, -35.0]]
	elif t >= 3.5 and t < 6.0:
		poses = [["thigh.R", Vector3.RIGHT, 70.0], ["shin.R", Vector3.RIGHT, -95.0],
				["foot.R", Vector3.RIGHT, -30.0], ["thigh.L", Vector3.RIGHT, 10.0], ["shin.L", Vector3.RIGHT, -15.0]]
	for i in ambac.joints.size():
		ambac.set_target(i, 0.0)
	for p in poses:
		var i := ambac.find_joint(p[0], p[1])
		if i >= 0:
			ambac.set_target(i, deg_to_rad(p[2]))
	ambac.step(Vector3.ZERO, dt)
	var rifle := fcs.get_weapon(&"beam_rifle")
	if rifle != null:
		rifle.aim_override = Vector2(50, 10) if t >= 2.0 and t < 4.5 else (Vector2(-20, 30) if t >= 4.5 and t < 7.0 else null)

func _report() -> void:
	var masses := limbs.get_part_masses()
	var line := "parts (kg, full):"
	var sum := 0.0
	for k in masses:
		line += " %s %.0f," % [k, masses[k]]
		sum += masses[k]
	print(line)
	var ds := PhysicsServer3D.body_get_direct_state(body.get_rid())
	print("full   mass %.0f kg (parts %.0f) com %s inertia diag %s" % [limbs.total_mass, sum, limbs.centre_of_mass,
			Vector3(limbs.inertia_tensor.x.x, limbs.inertia_tensor.y.y, limbs.inertia_tensor.z.z)])
	print("       off-diagonal xy %.0f xz %.0f yz %.0f | physics body com %s inertia %s" % [limbs.inertia_tensor.y.x,
			limbs.inertia_tensor.z.x, limbs.inertia_tensor.z.y, ds.center_of_mass_local, body.inertia])
	var line2 := "AMBAC joint inertia (kg·m²):"
	for j in ambac.joints:
		line2 += " %s%s %.0f," % [j.bone_name, _axis(j.axis), j.inertia]
	print(line2)
	fc.propellant = 0.0
	fc.body.mass = fc.get_total_mass()
	limbs.take_torque(1.0 / 60.0)
	print("empty  mass %.0f kg com %s inertia diag %s" % [limbs.total_mass, limbs.centre_of_mass,
			Vector3(limbs.inertia_tensor.x.x, limbs.inertia_tensor.y.y, limbs.inertia_tensor.z.z)])

func _axis(a: Vector3) -> String:
	return "x" if absf(a.x) > 0.5 else ("y" if absf(a.y) > 0.5 else "z")
