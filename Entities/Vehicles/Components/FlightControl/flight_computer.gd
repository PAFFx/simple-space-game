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
## Master FCS switch. Off = all thrusters commanded to zero.
@export var fcs_enabled: bool = true
## Force the FBW may ask for in a direction is capped at what the thrusters that can aim
## within acos(this) of it deliver; more would come from pairs cancelling each other.
## 0 = no cap.
@export_range(0.0, 1.0) var min_thrust_alignment: float = 0.7

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
## Reaction torque AMBAC delivered last tick (body frame).
var ambac_torque := Vector3.ZERO
var acceleration_g: float = 0.0

var _prev_velocity := Vector3.ZERO
var _ref_prev_position := Vector3.ZERO
var _ref_velocity := Vector3.ZERO
var _ref_tracking := false
var _depleted_emitted := false
var _hatch: CockpitHatch
var _capability_map: ForceCapabilityMap


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
		_hatch = vehicle.find_component(CockpitHatch) as CockpitHatch
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
	var command := input_source.get_command() if input_source != null else PilotCommand.new()

	if fcs_enabled:
		last_wrench = control_law.compute(state, command)
		var thrust_wrench := last_wrench
		if ambac != null and ambac.enabled:
			# Limbs take what exceeds the thrusters plus a share of the rest.
			var torque := last_wrench.torque
			var limit := last_wrench.thruster_torque_limit
			var beyond := torque - torque.clamp(-limit, limit)
			ambac_torque = ambac.step(beyond + (torque - beyond) * ambac.share, delta)
			body.apply_torque(state.to_global(ambac_torque))
			thrust_wrench = Wrench.new(last_wrench.force, (torque - ambac_torque).clamp(-limit, limit))
			thrust_wrench.torque_priority = last_wrench.torque_priority
		var demand := allocator.allocate(state, thrust_wrench)
		for i in thrusters.size():
			thrusters[i].set_command(demand[i].length(), demand[i], body)
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
		s.thruster_max.append(t.get_available_thrust() if has_propellant else 0.0)
	s.compute_authority()
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
