class_name MobileSuitBody
extends VehicleBase

## Generic mobile suit root. Attach to a RigidBody3D (VehicleBase only requires
## Node3D) so the whole suit — cockpit, sensor head, thrusters — is simulated.
## Expects children: Model (GLB), CockpitMount, SensorHeadMount.

## A shot landed on the suit: `direction` is the way it was flying.
signal hit_taken(damage: float, position: Vector3, direction: Vector3)

## Model meshes the pilot sees from inside through the open hatch (cavity + flaps).
@export var first_person_parts: Array[StringName] = [&"Chest", &"HatchUpper", &"HatchLower"]
## Model meshes the sensor head never sees, even with the body shown on the panoramic
## screen in a weapons mode: the head it sits in would wall it in.
@export var sensor_hidden_parts: Array[StringName] = [&"Head"]
## What shots physically do to it (DamageModel, Docs/Damage): made at start if it has none.
@export var damage_model: bool = true

var damage: DamageModel


func _ready() -> void:
	for mesh in get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var layers := Layers.VEHICLE_EXT
		if mesh.name in first_person_parts:
			layers |= Layers.VEHICLE_FP
		if not mesh.name in sensor_hidden_parts:
			layers |= Layers.SENSOR_BODY_PARTS
		(mesh as MeshInstance3D).layers = layers
	damage = find_component(DamageModel) as DamageModel
	if damage == null and damage_model:
		damage = DamageModel.new()
		damage.name = "Damage"
		add_child(damage)
	if damage != null:
		damage.hit.connect(func(at: Vector3, dir: Vector3) -> void: hit_taken.emit(1.0, at, dir))
		add_to_group(ProjectileManager.DAMAGEABLE)


func get_cockpit_mount() -> Marker3D:
	return get_node("CockpitMount") as Marker3D


func get_sensor_head_mount() -> Marker3D:
	return get_node("SensorHeadMount") as Marker3D


func get_body() -> RigidBody3D:
	return self as Node as RigidBody3D


## A beam on the suit, one tick (ProjectileManager): it drills (DamageModel). Without a
## damage model the hull just stops it.
func beam_contact(contact: ProjectileManager.BeamContact) -> void:
	if damage != null and damage.is_built():
		damage.beam_contact(contact)
		return
	contact.absorbed = contact.energy


## A bullet or a missile burst (ProjectileManager).
func apply_impact(spec: ProjectileSpec, at: Vector3, relative_velocity: Vector3, burst_distance: float, source: Node) -> void:
	if damage != null:
		damage.apply_impact(spec, at, relative_velocity, burst_distance, source)
	if burst_distance <= 0.0 or burst_distance < spec.blast_radius:
		hit_taken.emit(spec.damage, at, relative_velocity.normalized())


## A flash's radiant fluence, J/m² (another suit's reactor).
func apply_radiation(fluence: float, from: Vector3) -> void:
	if damage != null:
		damage.apply_radiation(fluence, from)


## Anything else that lands on the suit (a beam swept across it, old-style shots).
func apply_hit(amount: float, position: Vector3, direction: Vector3, _source: Node) -> void:
	hit_taken.emit(amount, position, direction)
