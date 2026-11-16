class_name FlightComputer
extends Node

## Fly-by-wire flight computer. Each physics tick:
##
##   PilotInputSource ─► ControlLaw ─► ThrustAllocator ─► Thruster × N ─► RigidBody3D
##     (intent)          (wrench)       (per-thruster)     (lagged force)
##
## Every stage is swappable: assign a different input node, ControlLaw or
## ThrustAllocator resource in the Inspector (or via set_control_law() /
## set_allocator() at runtime). Thrusters are discovered automatically anywhere
## under the RigidBody3D, so they may sit on animated bones.

signal propellant_depleted

const G0 := 9.80665

## Optional override — defaults to the first PilotInputSource child.
@export var input_source: PilotInputSource
@export var control_law: ControlLaw
@export var allocator: ThrustAllocator
## Optional limb balancing. Auto-discovered on the vehicle if left empty.
@export var ambac: AmbacController
## Optional mass model and reaction torque of the moving parts. Auto-discovered.
@export var limb_reaction: LimbReaction
## Cancel the limbs' measured reaction with AMBAC and the thrusters (feed-forward, a
## tick late) instead of waiting for the attitude hold to notice the body turning.
@export var counter_limb_reaction: bool = true
## Low-pass on that measured disturbance, s (skeleton updates and physics ticks don't line up).
@export var limb_disturbance_smoothing: float = 0.03
## Master FCS switch. Off = all thrusters commanded to zero.
@export var fcs_enabled: bool = true
## Force the FBW may ask for in a direction is capped at what the thrusters that can aim
## within acos(this) of it deliver; more would come from pairs cancelling each other.
## 0 = no cap.
@export_range(0.0, 1.0) var min_thrust_alignment: float = 0.7
## Set the throttles against where the nozzles really are each tick (see
## _trim_to_actuators). Off = thrusters get the ideal allocation as is.
@export var actuator_trim: bool = true

@export_group("Mass & Propellant")
@export var dry_mass: float = 36000.0             ## kg
@export var propellant_capacity: float = 9000.0   ## kg
@export var propellant: float = 9000.0            ## kg
@export var specific_impulse: float = 3000.0      ## s

@export_group("Reference Frame")
## Velocities are reported and held relative to this node (e.g. a station). Empty = world.
@export var reference_frame: Node3D

var body: RigidBody3D
## Mass carried in addition to dry mass + propellant (equipment), kg.
var payload_mass: float = 0.0
var thrusters: Array[Thruster] = []
var state := FlightState.new()
var last_wrench := Wrench.new()
var _pending_toggles := {}
## Reaction torque AMBAC delivered last tick (body frame).
var ambac_torque := Vector3.ZERO
## Limbs' reaction torque on the body last tick, and the part of it AMBAC didn't plan
## (pose blends, weapon aim, model error), smoothed (body frame).
var limb_torque := Vector3.ZERO
var limb_disturbance := Vector3.ZERO
var _ambac_measured := Vector3.ZERO
var _ambac_measured_smoothed := Vector3.ZERO
var acceleration_g: float = 0.0

var _prev_velocity := Vector3.ZERO
var _ref_prev_position := Vector3.ZERO
var _ref_velocity := Vector3.ZERO
var _ref_tracking := false
var _depleted_emitted := false
var _hatch: CockpitHatch
var _capability_map: ForceCapabilityMap
var _map_build: ForceCapabilityMap      ## Rebuild in progress (replaces the map when done)
var _stance: StanceController
## Directions of the capability map measured per tick while rebuilding in flight.
@export var capability_rebuild_per_tick: int = 2


func _ready() -> void:
	body = _find_body()
	if body == null:
		push_error("FlightComputer: no RigidBody3D ancestor found")
		set_physics_process(false)
		return
	if input_source == null:
		input_source = _find_input_source()
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		if ambac == null:
			ambac = vehicle.find_component(AmbacController) as AmbacController
		if limb_reaction == null:
			limb_reaction = vehicle.find_component(LimbReaction) as LimbReaction
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
		_stance = vehicle.find_component(StanceController) as StanceController
	set_control_law(control_law if control_law != null else RateCommandControlLaw.new())
	set_allocator(allocator if allocator != null else ConeProjectedAllocator.new())
	_collect_thrusters(body)
	body.mass = get_total_mass()
	_prev_velocity = body.linear_velocity


## Re-measures the clean force authority (call after thrusters are added, removed
## or disabled). Takes a few hundred ms for ~30 thrusters.
func rebuild_capability_map() -> void:
	_capability_map = ForceCapabilityMap.build(state, allocator, min_thrust_alignment)
	state.capability_map = _capability_map


## Rebuilds the capability map for the current pose over the next few ticks (the old
## map stays in use until then). Used when limbs carrying thrusters change pose.
func rebuild_capability_map_async() -> void:
	if not thrusters.is_empty():
		_map_build = ForceCapabilityMap.start(state, allocator.duplicate(), min_thrust_alignment)


## Drops the capability map so the next tick measures it again at once (e.g. the mass
## model moved the centre of mass far from where the map was built).
func invalidate_capability_map() -> void:
	_capability_map = null
	_map_build = null


func get_total_mass() -> float:
	return dry_mass + propellant + payload_mass


func add_payload_mass(kg: float) -> void:
	payload_mass += kg
	if body != null:
		body.mass = get_total_mass()


func set_control_law(law: ControlLaw) -> void:
	# Duplicate so vehicles sharing a .tres never share hold/integrator state.
	control_law = law.duplicate()
	control_law.reset()


func set_allocator(new_allocator: ThrustAllocator) -> void:
	allocator = new_allocator.duplicate()


func _physics_process(delta: float) -> void:
	_build_state(delta)
	if _map_build != null and _map_build.step(capability_rebuild_per_tick):
		_capability_map = _map_build
		state.capability_map = _capability_map
		_map_build = null
	var command := input_source.get_command() if input_source != null else PilotCommand.new()
	for toggle: StringName in _pending_toggles:
		command.set(toggle, true)
	_pending_toggles.clear()

	_apply_limb_reaction(delta)
	_ambac_measured = Vector3.ZERO

	if fcs_enabled:
		last_wrench = control_law.compute(state, command)
		var thrust_wrench := last_wrench
		var torque := last_wrench.torque
		# Countering goes through the normal split, not all to AMBAC: a waist swing makes the
		# aimed arm swing back in the chest, which reads as a new disturbance (loop gain ~1).
		if counter_limb_reaction:
			torque -= limb_disturbance
		if ambac != null and ambac.enabled:
			# Limbs take what exceeds the thrusters plus a share of the rest.
			var limit := last_wrench.thruster_torque_limit
			var beyond := torque - ControlLaw.scale_to_box(torque, limit)
			ambac_torque = ambac.step(beyond + (torque - beyond) * ambac.share, delta)
			_ambac_measured = ambac.last_measured_torque
			# Measured joints push the body through LimbReaction instead.
			body.apply_torque(state.to_global(ambac_torque - _ambac_measured))
			thrust_wrench = Wrench.new(last_wrench.force, ControlLaw.scale_to_box(torque - ambac_torque, limit))
			thrust_wrench.torque_priority = last_wrench.torque_priority
		elif torque != last_wrench.torque:
			thrust_wrench = Wrench.new(last_wrench.force, torque)
			thrust_wrench.torque_priority = last_wrench.torque_priority
			thrust_wrench.thruster_torque_limit = last_wrench.thruster_torque_limit
		var demand := allocator.allocate(state, thrust_wrench)
		for i in thrusters.size():
			thrusters[i].set_command(demand[i].length(), demand[i], body)
		if actuator_trim:
			_trim_to_actuators(thrust_wrench, demand, delta)
	else:
		last_wrench = Wrench.new()
		for t in thrusters:
			t.set_command(0.0, Vector3.ZERO, body)

	var has_propellant := propellant > 0.0
	var thrust_sum := 0.0
	for t in thrusters:
		t.step(delta, body, has_propellant)
		thrust_sum += t.get_thrust()
	_consume_propellant(thrust_sum, delta)

	var accel := (body.linear_velocity - _prev_velocity) / delta
	_prev_velocity = body.linear_velocity
	acceleration_g = lerpf(acceleration_g, accel.length() / G0, 0.15)


## Newton's third law for the limbs: the body gets their measured reaction whatever the
## FCS does. What AMBAC didn't plan itself is the disturbance to counter.
func _apply_limb_reaction(delta: float) -> void:
	if limb_reaction == null or not limb_reaction.enabled:
		limb_torque = Vector3.ZERO
		limb_disturbance = Vector3.ZERO
		return
	limb_torque = limb_reaction.take_torque(delta)
	body.apply_torque(state.to_global(limb_torque))
	# AMBAC's own share of it (last tick's plan), through the same low-pass the measured
	# momentum goes through, or its own arm swing would read as a disturbance for a moment.
	var km := 1.0 if limb_reaction.momentum_smoothing <= 0.0 \
			else 1.0 - exp(-delta / limb_reaction.momentum_smoothing)
	_ambac_measured_smoothed = _ambac_measured_smoothed.lerp(_ambac_measured, km)
	var unplanned := limb_torque - _ambac_measured_smoothed
	var k := 1.0 if limb_disturbance_smoothing <= 0.0 else 1.0 - exp(-delta / limb_disturbance_smoothing)
	limb_disturbance = limb_disturbance.lerp(unplanned, k)


## The allocation assumes every nozzle is already aimed and every throttle already
## there. Thrusters spool and slew at different speeds, so in a transient their sum
## points somewhere else. This sets the throttles for where the nozzles really will be
## this tick, within what each can reach.
func _trim_to_actuators(wrench: Wrench, demand: PackedVector3Array, delta: float) -> void:
	var n := thrusters.size()
	var dirs := PackedVector3Array()
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	var start := PackedFloat32Array()
	dirs.resize(n)
	lo.resize(n)
	hi.resize(n)
	start.resize(n)
	var live := propellant > 0.0
	for i in n:
		dirs[i] = thrusters[i].predict_direction_in(body, delta)
		var reach := thrusters[i].reachable_throttle(delta) if live else Vector2.ZERO
		lo[i] = reach.x
		hi[i] = reach.y
		start[i] = demand[i].length()
	var throttles := allocator.trim(state, wrench, dirs, lo, hi, start)
	for i in n:
		thrusters[i].set_throttle_now(throttles[i], delta)


# --- Telemetry (used by the HUD) ---

func get_propellant_fraction() -> float:
	return propellant / propellant_capacity if propellant_capacity > 0.0 else 0.0


## Current total thrust as a fraction of the combined maximum.
func get_thrust_fraction() -> float:
	var now := 0.0
	var total := 0.0
	for t in thrusters:
		now += t.get_thrust()
		total += t.max_thrust
	return now / total if total > 0.0 else 0.0


## The pilot's movement request (stick translation) in the pilot frame; zero when
## released. Stances follow this, not the FBW's force (which also brakes) or the body
## frame (auto-rotation tilts it, which would make a strafe look like a climb).
func get_translation_intent() -> Vector3:
	if input_source == null or input_source.last_command == null:
		return Vector3.ZERO
	return input_source.last_command.translation


## Global "up" the HUD's attitude is shown against: the horizon lock's when it's on,
## else the reference frame's (world up without one).
func get_attitude_up() -> Vector3:
	var up: Variant = control_law.get_horizon_up() if fcs_enabled and control_law != null else null
	if up != null:
		return up
	return reference_frame.global_basis.y.normalized() if reference_frame != null else Vector3.UP


## Frame the attitude displays use (y = get_attitude_up(), −z = north): north is the
## reference frame's −Z (world −Z without one), flattened onto the horizon.
func get_attitude_basis() -> Basis:
	var up := get_attitude_up()
	var north := -reference_frame.global_basis.z if reference_frame != null else Vector3.FORWARD
	north -= up * north.dot(up)
	if north.length_squared() < 1e-6:
		north = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.BACK)
	var back := -north.normalized()
	return Basis(up.cross(back).normalized(), up, back)


## Queues a one-shot PilotCommand toggle (e.g. &"toggle_precision") for the next tick,
## for cockpit switches: they reuse the control law's own toggle handling.
func request_toggle(toggle: StringName) -> void:
	_pending_toggles[toggle] = true


## Whether the pilot is boosting (Shift, or full boost).
func is_boosting() -> bool:
	return input_source != null and input_source.last_command != null \
			and input_source.last_command.boost


## Body relative to the pilot frame (body = pilot · offset); the cockpit counter-rotates by it.
func get_pilot_offset() -> Quaternion:
	return control_law.get_pilot_offset() if fcs_enabled else Quaternion.IDENTITY


## Pilot frame relative to the body *now* (cockpit local rotation). Unlike the commanded
## offset this includes the body's tracking lag, so the cockpit holds still in the world
## while the body swings into a new attitude.
func get_cockpit_rotation() -> Quaternion:
	if not fcs_enabled or control_law == null:
		return Quaternion.IDENTITY
	# Compare against where the body will be after this tick's physics step, or held
	# axes trail it by one tick. Locked axes follow that same predicted body exactly.
	var body_q := state.basis.get_rotation_quaternion()
	var w := state.angular_velocity
	if w.length_squared() > 1e-10:
		body_q = Quaternion(w.normalized(), w.length() * state.delta) * body_q
	var pilot: Variant = control_law.get_cockpit_orientation(body_q)
	if pilot == null:
		return Quaternion.IDENTITY
	return (body_q.inverse() * pilot).normalized()


func get_mode_labels() -> PackedStringArray:
	if not fcs_enabled:
		return PackedStringArray(["FCS OFF"])
	return control_law.get_mode_labels()


## Direction of a break (dodge) in progress, pilot frame; zero when none.
func get_break_direction() -> Vector3:
	return control_law.get_break_direction() if fcs_enabled else Vector3.ZERO


## Boost / brake for the HUD: 0 off, 1 on, 2 full. 0 with the FCS off.
func get_boost_level() -> int:
	return control_law.get_boost_level() if fcs_enabled else 0


func get_brake_level() -> int:
	return control_law.get_brake_level() if fcs_enabled else 0


# --- Private ---

func _build_state(delta: float) -> void:
	var ds := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var s := FlightState.new()
	s.delta = delta
	s.mass = body.mass
	s.basis = body.global_basis.orthonormalized()
	s.com_position = body.global_position + ds.center_of_mass

	s.reference_velocity = _reference_velocity(delta)
	s.linear_velocity = body.linear_velocity - s.reference_velocity
	s.local_linear_velocity = s.to_local(s.linear_velocity)
	s.angular_velocity = body.angular_velocity
	s.local_angular_velocity = s.to_local(s.angular_velocity)
	s.inertia_local = s.basis.transposed() * ds.inverse_inertia_tensor.inverse() * s.basis

	var com_local := body.to_local(s.com_position)
	var has_propellant := propellant > 0.0
	for t in thrusters:
		s.thruster_positions.append(t.get_position_in(body) - com_local)
		s.thruster_axes.append(t.get_axis_in(body))
		s.thruster_cone.append(t.get_cone_rad())
		s.thruster_planes.append_array(t.get_limit_planes_in(body))
		s.thruster_max.append(t.get_available_thrust() if has_propellant else 0.0)
	s.compute_authority()
	if _capability_map != null:
		s.max_torque = _capability_map.clean_torque.min(s.max_torque_ideal)
	if ambac != null and ambac.enabled:
		s.ambac_torque = ambac.get_capacity()
	# The cockpit must line up with the hull opening while the hatch is unsealed.
	s.allow_attitude_offset = _hatch == null or not _hatch.is_unsealed()
	s.capability_map = _capability_map
	state = s
	if _capability_map == null and not thrusters.is_empty():
		rebuild_capability_map()


func _reference_velocity(delta: float) -> Vector3:
	if reference_frame == null:
		return Vector3.ZERO
	var pos := reference_frame.global_position
	if _ref_tracking:
		# Low-pass: the reference may move in _process, which is jittery per physics tick.
		_ref_velocity = _ref_velocity.lerp((pos - _ref_prev_position) / delta, 0.1)
	_ref_prev_position = pos
	_ref_tracking = true
	return _ref_velocity


func _consume_propellant(thrust_sum: float, delta: float) -> void:
	if propellant <= 0.0:
		return
	propellant = maxf(0.0, propellant - thrust_sum / (specific_impulse * G0) * delta)
	var mass := get_total_mass()
	if absf(body.mass - mass) > 10.0:
		body.mass = mass
	if propellant <= 0.0 and not _depleted_emitted:
		_depleted_emitted = true
		propellant_depleted.emit()


func _find_body() -> RigidBody3D:
	var node := get_parent()
	while node != null:
		if node is RigidBody3D:
			return node as RigidBody3D
		node = node.get_parent()
	return null


func _find_input_source() -> PilotInputSource:
	for child in get_children():
		if child is PilotInputSource:
			return child as PilotInputSource
	return null


func _collect_thrusters(node: Node) -> void:
	for child in node.get_children():
		if child is Thruster:
			thrusters.append(child as Thruster)
		_collect_thrusters(child)
