class_name StanceController
extends Node

## Commits the limbs to a pose that suits the current push, so fixed and 2D thrusters
## on them point usefully (and their swing helps turn the body), without flailing.
##
## The stance is picked from the pilot's movement request (stick translation, pilot
## frame): the stance whose direction it falls within, else neutral. Releasing the
## stick returns the limbs to neutral, and their swing back helps level the suit. It only changes after the new choice has
## held for confirm_time and the current one for min_dwell, and the current stance
## keeps its pick until the push leaves its cone by hysteresis_deg. Each change is one
## smooth motion (min-jerk, transition_time) fed to AMBAC as joint targets, so the
## limbs' reaction torque acts on the body as it would for any limb motion. Joints in
## locked or occupied groups (see AmbacController) are left alone and ease to
## neutral. The allocator always uses the limbs' real thruster positions; the FBW's
## capability map can optionally be rebuilt for each settled pose (costly, off).

@export var ambac: AmbacController
@export var flight_computer: FlightComputer
@export var stances: Array[MsStance] = []
## Stick deflection below which the suit goes back to neutral.
@export var engage: float = 0.2
@export var hysteresis_deg: float = 25.0
@export var confirm_time: float = 0.15
@export var min_dwell: float = 0.6
@export var transition_time: float = 0.45
## Rebuild the FBW capability map after each pose settles (thrusters ride the limbs).
## Off: a rebuild costs ~1.2 s of allocator probing (spread over ticks, but enough to
## stutter) and changes the map by only a few percent.
@export var rebuild_capability: bool = false

var current: MsStance = null          ## null = neutral
var _pending: MsStance = null
var _pending_time := 0.0
var _dwell := 0.0
var _from := PackedFloat32Array()      ## Joint targets at the start of the transition
var _to := PackedFloat32Array()
var _t := 1.0                          ## Transition progress 0..1
var _settled := true


func _ready() -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		if ambac == null:
			ambac = vehicle.find_component(AmbacController) as AmbacController
		if flight_computer == null:
			flight_computer = vehicle.find_component(FlightComputer) as FlightComputer
	# Before the FlightComputer steps AMBAC this tick.
	process_physics_priority = -5


func get_stance_name() -> StringName:
	return current.stance_name if current != null else &"neutral"


func _physics_process(delta: float) -> void:
	if ambac == null or flight_computer == null or ambac.joints.is_empty():
		return
	var n := ambac.joints.size()
	if _from.size() != n:
		_from.resize(n)
		_to.resize(n)
	_select(delta)
	_drive(delta)


func _select(delta: float) -> void:
	var intent := flight_computer.get_translation_intent()
	var pick: MsStance = null
	if intent.length() >= engage:
		var dir := intent.normalized()
		var best := -2.0
		for s in stances:
			var cone := s.cone_deg + (hysteresis_deg if s == current else 0.0)
			var d := dir.dot(s.direction.normalized())
			if d >= cos(deg_to_rad(cone)) and d + (0.2 if s == current else 0.0) > best:
				best = d + (0.2 if s == current else 0.0)
				pick = s
	_dwell += delta
	if pick == current:
		_pending = null
		_pending_time = 0.0
		return
	if pick != _pending:
		_pending = pick
		_pending_time = 0.0
	_pending_time += delta
	if _pending_time >= confirm_time and _dwell >= min_dwell:
		_begin(pick)


func _begin(stance: MsStance) -> void:
	current = stance
	_pending = null
	_pending_time = 0.0
	_dwell = 0.0
	_t = 0.0
	_settled = false
	for i in ambac.joints.size():
		_from[i] = ambac.targets[i]
		_to[i] = 0.0
	if stance == null:
		return
	for k in stance.bones.size():
		var i := ambac.find_joint(StringName(stance.bones[k]), stance.axes[k])
		if i >= 0:
			_to[i] = deg_to_rad(stance.angles_deg[k])


## Min-jerk blend from _from to _to over transition_time; locked groups go to neutral.
func _drive(delta: float) -> void:
	var T := maxf(transition_time, 0.01)
	_t = minf(_t + delta / T, 1.0)
	var u := _t
	var s := u * u * u * (10.0 + u * (-15.0 + 6.0 * u))
	var ds := 30.0 * u * u * (1.0 - u) * (1.0 - u) / T
	var dds := 60.0 * u * (1.0 - u) * (1.0 - 2.0 * u) / (T * T)
	for i in ambac.joints.size():
		var goal := _to[i]
		var from := _from[i]
		if ambac.is_group_locked(ambac.joints[i].group):
			goal = 0.0
		if _t >= 1.0:
			ambac.set_target(i, goal)
		else:
			var span := goal - from
			ambac.set_target(i, from + span * s, span * ds, span * dds)
	if _t >= 1.0 and not _settled:
		_settled = true
		if rebuild_capability:
			flight_computer.rebuild_capability_map_async()
