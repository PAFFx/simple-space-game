class_name MsShield
extends MsEquipment

## Arm shield. "Active" = guard position. The sensor never renders the suit or its
## equipment, so the pilot sees the shield as a HudSilhouette outline on the HUD.
##
## It is solid: a static body hull around each of its meshes, on the shield physics layer
## (Layers.PHYS_SHIELD) with no mask, so it never pushes the suit carrying it, but every
## shot ray and sensor sight line meets it. The suit's own shots exclude only its hull, so
## its vulcans can't fire through its own shield.

var _bodies: Array[StaticBody3D] = []


func _ready() -> void:
	super()
	var model := get_node_or_null(^"Model")
	for mesh: MeshInstance3D in (model.find_children("*", "MeshInstance3D", true, false) if model else []):
		if mesh.mesh == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = Layers.PHYS_SHIELD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.mesh.create_convex_shape(true, true)
		body.add_child(shape)
		mesh.add_child(body)
		_bodies.append(body)
	visibility_changed.connect(_sync_solid)


## Stowed (hidden by MsLoadout): nothing to hit.
func _sync_solid() -> void:
	for body in _bodies:
		body.collision_layer = Layers.PHYS_SHIELD if is_visible_in_tree() else 0


## A shot stopped on the shield. The suit's own (a vulcan burst into its own shield) just
## ends there; anyone else's counts as a blocked hit.
func apply_hit(_damage: float, _at: Vector3, _direction: Vector3, source: Node) -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle == null or source == vehicle:
		return
	var fcs := vehicle.find_component(FireControl) as FireControl
	if fcs != null:
		fcs.register_hit(true)
