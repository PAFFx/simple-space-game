extends SceneTree

## Cost of an RX-93 physics tick, with parts switched off one at a time. Flies 15 s of
## alternating left / right breaks in DGFT with a drone locked (sensors live), at a fixed
## 60 Hz as fast as the CPU allows, and reports wall time and Godot's physics-process time.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Profiling/tick_cost_probe.gd -- <variant>
## variants: base, no_map_rebuild, coarse_com, no_body_mass, no_limb_reaction, no_sensors,
##           no_stances, no_ambac

const SIM_TIME := 15.0

class Scripted extends PilotInputSource:
	var t := 0.0
	func poll_command() -> PilotCommand:
		var c := PilotCommand.new()
		if t < 0.6:
			c.master_mode = FireControl.MasterMode.DGFT
			return c
		var phase := fmod(t - 0.6, 3.0)
		c.translation = Vector3(1, 0, 0) if phase < 1.5 else Vector3(-1, 0, 0)
		c.boost_full = fmod(phase, 1.5) < 0.1
		c.boost = c.boost_full
		return c

var _suit: RigidBody3D
var _fc: FlightComputer
var _inp := Scripted.new()
var _variant := "base"
var _ticks := 0
var _phys_ms := 0.0
var _start_us := 0
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_variant = args[0]
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	_suit = load("res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn").instantiate()
	root.add_child(_suit)
	var vehicle := _suit as Node as VehicleBase
	_fc = vehicle.find_component(FlightComputer) as FlightComputer
	_fc.add_child(_inp)
	_fc.input_source = _inp
	var limbs := vehicle.find_component(LimbReaction) as LimbReaction
	var fcs := vehicle.find_component(FireControl) as FireControl
	match _variant:
		"no_map_rebuild": limbs.map_rebuild_distance = INF
		"coarse_com": limbs.com_tolerance = 0.05
		"no_body_mass": limbs.drive_body_mass = false
		"no_limb_reaction": limbs.enabled = false
		"no_sensors": fcs.sensors.enabled = false
		"no_stances": (vehicle.find_component(StanceController) as StanceController).enabled = false
		"no_ambac": _fc.ambac.enabled = false
	var drone := TargetDrone.new()
	drone.hit_points = 1e12
	root.add_child(drone)
	drone.global_position = _suit.global_position + Vector3(150, 40, -1200)
	await physics_frame
	await physics_frame
	fcs.lock(drone)
	_start_us = Time.get_ticks_usec()
	physics_frame.connect(_tick)


func _tick() -> void:
	if _done:
		return
	_inp.t += 1.0 / Engine.physics_ticks_per_second
	_ticks += 1
	_phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if _inp.t >= SIM_TIME:
		_done = true
		var wall := (Time.get_ticks_usec() - _start_us) / 1e6
		print("%-17s %5.1f s wall for %.0f s simulated (%.2f× real time) | physics process %.2f ms/tick avg" % [
			_variant, wall, SIM_TIME, SIM_TIME / wall, _phys_ms / maxf(_ticks, 1)])
		quit()
