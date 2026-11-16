class_name MsLoadout
extends Node3D

## Mounts the MsEquipment children on the suit skeleton (each on its own
## BoneAttachment3D) and toggles them with their input actions.
## Other components query it: occupied AMBAC groups, active poses.

signal equipment_changed(equipment: MsEquipment)
## An item was put on or taken off the suit (set_equipped).
signal equipment_fitted(equipment: MsEquipment, equipped: bool)

@export var skeleton: Skeleton3D
## Toggle equipment from PilotInputActions (e.g. 1 = rifle, 2 = shield).
@export var listen_for_input: bool = true

var equipment: Array[MsEquipment] = []


func _ready() -> void:
	PilotInputActions.ensure_defaults()
	if skeleton == null:
		push_error("MsLoadout: skeleton not assigned")
		return
	for child in get_children():
		if child is MsEquipment:
			_mount(child as MsEquipment)
	var vehicle := VehicleBase.find_vehicle(self)
	var fc := vehicle.find_component(FlightComputer) as FlightComputer if vehicle else null
	if fc != null:
		fc.add_payload_mass(get_total_mass())


func _process(_delta: float) -> void:
	if not listen_for_input:
		return
	for eq in equipment:
		if eq.input_action != &"" and InputMap.has_action(eq.input_action) \
				and Input.is_action_just_pressed(eq.input_action):
			eq.toggle()


func get_total_mass() -> float:
	var total := 0.0
	for eq in equipment:
		if eq.equipped:
			total += eq.mass
	return total


## Puts `eq` on the suit or takes it off (test range): hidden, its mass off the suit and
## its weapons out of the fire control while it is off.
func set_equipped(eq: MsEquipment, on: bool) -> void:
	if eq.equipped == on or not equipment.has(eq):
		return
	if not on:
		eq.set_active(false)
	eq.equipped = on
	eq.visible = on
	eq.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	var vehicle := VehicleBase.find_vehicle(self)
	var fc := vehicle.find_component(FlightComputer) as FlightComputer if vehicle else null
	if fc != null:
		fc.add_payload_mass(eq.mass if on else -eq.mass)
	equipment_fitted.emit(eq, on)


## True while active equipment occupies this AMBAC group.
func is_group_occupied(group: StringName) -> bool:
	for eq in equipment:
		if eq.active and eq.ambac_group == group:
			return true
	return false


## Pose name → true for every active equipment pose.
func get_active_poses() -> Dictionary:
	var poses := {}
	for eq in equipment:
		if eq.active and eq.active_pose != &"":
			poses[eq.active_pose] = true
	return poses


func _mount(eq: MsEquipment) -> void:
	var bone := skeleton.find_bone(eq.mount_bone)
	if bone < 0:
		push_error("MsLoadout: bone '%s' not found for %s" % [eq.mount_bone, eq.name])
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Mount_%s" % eq.name
	attach.bone_name = eq.mount_bone
	skeleton.add_child(attach)
	# mount_transform is in the body frame at rest; re-express it relative to the bone.
	var body := VehicleBase.find_vehicle(self)
	var skel_in_body := body.global_transform.affine_inverse() * skeleton.global_transform
	var bone_in_body := skel_in_body * skeleton.get_bone_global_rest(bone)
	eq.reparent(attach, false)
	eq.transform = bone_in_body.affine_inverse() * eq.mount_transform
	eq.active_changed.connect(func(_a: bool) -> void: equipment_changed.emit(eq))
	equipment.append(eq)
