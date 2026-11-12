class_name CockpitSwitchPanel
extends Node3D

## The left console's switch panel: settings that rarely change mid-fight (so no
## HOTAS buttons), on the console's front face (the model's SwitchPanelMount):
##   FCS on/off · rotation ATT-HOLD/RATE · horizon LOCK/FREE · movement NORM/PREC · AMBAC on/off
## Each switch follows the state it controls every frame, and a throw changes that state
## (mode toggles go through FlightComputer.request_toggle, so the control law's own
## handling runs). Lay the panel's local −Z forward, +Y out of the panel.

const SPACING := 0.027
const ROW := 0.08

var _fc: FlightComputer
var _ambac: AmbacController
var _switches := {}   # id → CockpitSwitch
var _hold := {}       # id → s left before following the state again (a throw lands next tick)


func _ready() -> void:
	_mount()
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_fc = vehicle.find_component(FlightComputer) as FlightComputer
		_ambac = vehicle.find_component(AmbacController) as AmbacController
	_group("FCS", 0.0, [
		[&"fcs", "FCS", ["ON", "OFF"]],
		[&"rot", "ROT", ["ATT", "RATE"]],
		[&"horizon", "HRZN", ["LOCK", "FREE"]],
		[&"move", "MOVE", ["NORM", "PREC"]],
		[&"ambac", "AMBAC", ["ON", "OFF"]],
	])
	CockpitLinearSeat._set_layers(self, Layers.COCKPIT | Layers.VEHICLE_EXT)


## Sits on the cockpit model's SwitchPanelMount (the left console's front face).
func _mount() -> void:
	var mount := get_parent().find_child("SwitchPanelMount", true, false) as Node3D
	if mount == null:
		push_warning("CockpitSwitchPanel: no SwitchPanelMount in the cockpit model")
		return
	transform = (get_parent() as Node3D).global_transform.affine_inverse() * mount.global_transform


func _process(delta: float) -> void:
	for id: StringName in _switches:
		if float(_hold.get(id, 0.0)) > 0.0:
			_hold[id] = float(_hold[id]) - delta
			continue
		(_switches[id] as CockpitSwitch).set_index(0 if _state(id) else 1)


func _group(title: String, z: float, list: Array) -> void:
	var width := SPACING * list.size()
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width + 0.012, 0.004, ROW - 0.008)
	plate.mesh = box
	plate.position = Vector3(0, -0.006, z + 0.006)
	plate.material_override = CockpitSwitch._material(Color(0.1, 0.11, 0.13))
	add_child(plate)
	var label := Label3D.new()
	label.text = title
	label.font_size = 26
	label.pixel_size = 0.00018
	label.modulate = Color(0.4, 0.82, 1.0)
	label.position = Vector3(-width * 0.5 + 0.004, -0.0035, z - ROW * 0.5 + 0.009)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	add_child(label)
	for i in list.size():
		var spec: Array = list[i]
		var sw := CockpitSwitch.new()
		sw.name = "Switch_" + String(spec[0])
		sw.title = spec[1]
		sw.positions = PackedStringArray(spec[2])
		sw.tooltip = "%s  %s / %s" % [spec[1], spec[2][0], spec[2][1]]
		sw.position = Vector3(-width * 0.5 + SPACING * (i + 0.5), 0, z)
		sw.index = 0 if _state(spec[0]) else 1
		sw.switched.connect(_on_switched.bind(spec[0]))
		add_child(sw)
		_switches[spec[0]] = sw


## The setting's "first position" state (ON / ATT / LOCK / NORM / AUTO) is true.
func _state(id: StringName) -> bool:
	var law := _fc.control_law as RateCommandControlLaw if _fc != null else null
	match id:
		&"fcs":
			return _fc != null and _fc.fcs_enabled
		&"rot":
			return law != null and law.rotation_mode == RateCommandControlLaw.RotationMode.ATTITUDE_HOLD
		&"horizon":
			return law != null and law.horizon_lock
		&"move":
			return law == null or not law.precision
		&"ambac":
			return _ambac != null and _ambac.enabled
	return false


func _on_switched(index: int, id: StringName) -> void:
	var want := index == 0
	if want == _state(id):
		return
	_hold[id] = 0.2
	match id:
		&"fcs":
			_fc.fcs_enabled = want
		&"rot":
			_fc.request_toggle(&"toggle_rotation_mode")
		&"horizon":
			_fc.request_toggle(&"toggle_horizon_lock")
		&"move":
			_fc.request_toggle(&"toggle_precision")
		&"ambac":
			_ambac.enabled = want
