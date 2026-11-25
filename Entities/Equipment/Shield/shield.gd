class_name MsShield
extends MsEquipment

## Arm shield. "Active" = guard position. The sensor never renders the suit or its
## equipment, so the pilot sees the shield as a HudSilhouette outline on the HUD.
##
## It is solid: a static body hull around each of its meshes, on the shield physics layer
## (Layers.PHYS_SHIELD) with no mask, so it never pushes the suit carrying it, but every
## shot ray and sensor sight line meets it. The suit's own shots exclude only its hull, so
## its vulcans can't fire through its own shield. Weapons mounted on the shield (its
## missiles) skip it (get_solid_rids).
##
## Beams (Docs/Damage): three large E-pac charges each raise an I-field for `field_time`
## just before a beam lands. A detector ring on the face sees the glowing beam front cross a
## shell `detector_range` ahead; if that leaves the field time to rise (`field_rise`) and the
## beam comes onto the face (not past its edge), the field takes the beam: it disperses in a
## flash, a little of its heat (`field_leak`) boils the anti-beam coating (the smoke). With
## no charge left the beam drills the plate (`areal_density` kg/m², coating included) in a
## few hundredths of a second and goes on into whatever is behind. Holes that leave too
## little of the plate break it off.

@export_group("I-field")
@export var field_charges: int = 3
@export var field_time: float = 0.2
@export var detector_range: float = 20.0
@export var field_rise: float = 0.005
@export var field_leak: float = 0.07
## The detector sees beams arriving within this angle of the face's normal, deg.
@export var detector_cone_deg: float = 80.0
@export_group("Plate")
## Kg per m² a beam has to remove to get through (plate × anti-beam coating). A rifle shot
## melts ~800 kg in all: 250 takes ~35% of it head-on, ~70% at a steep slant.
@export var areal_density: float = 250.0
@export var plate_width: float = 4.0

var charges := 3
var left := 1.0
var _bodies: Array[StaticBody3D] = []
var _field_until := -1.0
var _clock := 0.0
var _drills := {}   ## shot → [kg needed, kg removed, hole, mesh, entry, exit, counted]


func _ready() -> void:
	super()
	charges = field_charges
	var model := get_node_or_null(^"Model")
	for mesh: MeshInstance3D in (model.find_children("*", "MeshInstance3D", true, false) if model else []):
		if mesh.mesh == null or mesh.name.begins_with("ShieldMissile"):
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


func _physics_process(delta: float) -> void:
	_clock += delta
	for key in _drills.keys():
		if _clock - float(_drills[key][7]) > 0.3:
			_drills.erase(key)


## Charges and plate back as new (the range's rearm).
func repair() -> void:
	charges = field_charges
	left = 1.0
	_drills.clear()
	_field_until = -1.0


func is_field_up() -> bool:
	return _clock < _field_until


## A beam on the shield, one tick (ProjectileManager).
func beam_contact(contact: ProjectileManager.BeamContact) -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle == null or contact.source == vehicle:
		contact.absorbed = contact.energy
		return
	var model := vehicle.find_component(DamageModel) as DamageModel
	var fcs := vehicle.find_component(FireControl) as FireControl
	var d: Array = _drills.get(contact.key, [])
	var fresh := d.is_empty()
	if fresh:
		# The detector: the beam's front crossing its shell gives detector_range / speed of
		# warning; the field needs field_rise of it. Beams past the edge it doesn't see.
		var onto_face := contact.normal.dot(-contact.direction) >= cos(deg_to_rad(detector_cone_deg))
		var warned := detector_range / maxf(contact.spec.speed, 1.0) >= field_rise
		var caught := is_field_up() or (charges > 0 and onto_face and warned)
		var mesh := contact.collider.get_parent() as MeshInstance3D if contact.collider != null else null
		d = [0.0, 0.0, null, mesh, contact.point, contact.point, false, _clock, caught]
		if not caught:
			var area := PI * contact.radius * contact.radius
			# A slanted hit crosses more plate, at most twice it (a glancing one bites in steeply).
			d[0] = areal_density * area / maxf(absf(contact.normal.dot(contact.direction)), 0.5)
			d[5] = _exit_point(contact)
		elif not is_field_up():
			charges -= 1
			_field_until = _clock + field_time
		_drills[contact.key] = d
	d[7] = _clock
	if d[8]:
		# Taken by the field: the beam disperses at its edge, a little heat on the face.
		contact.absorbed = contact.energy
		contact.front = contact.point - contact.direction * 2.5
		if fresh:
			var fx := DamageFx.of(self)
			if fx != null:
				fx.i_field(contact.point - contact.direction * 2.5, -contact.direction, _velocity(vehicle), contact.spec.color)
			if model != null and d[3] != null:
				# The field held: no melt, soot where the beam's edge reached the coating.
				var h := model.holes.add_hole(d[3], null, -1, contact.point, contact.direction, 1.6, 0.4, 290.0)
				h.s_drill = -1.0
			if fcs != null:
				fcs.register_hit(true)
		return
	# No field: drill the plate.
	var kg := contact.energy * DamageModel.COUPLING / DamageModel.REMOVAL_ENERGY
	var need: float = d[0] - d[1]
	if fresh and model != null and d[3] != null:
		d[2] = model.holes.add_hole(d[3], null, -1, contact.point, contact.direction, contact.radius * HoleSet.BEAM_GROW,
				maxf((d[5] as Vector3).distance_to(contact.point), 0.1))
		var fx := DamageFx.of(self)
		if fx != null:
			fx.drill_in(contact.point, contact.direction, _velocity(vehicle), contact.radius, self)
	if kg < need:
		d[1] = float(d[1]) + kg
		contact.absorbed = contact.energy
		contact.front = contact.point
		if d[2] != null:
			(d[2] as HoleSet.Hole).s_drill = (d[2] as HoleSet.Hole).s_out * float(d[1]) / maxf(d[0], 1.0)
		return
	d[1] = d[0]
	contact.through = true
	contact.absorbed = need * DamageModel.REMOVAL_ENERGY / DamageModel.COUPLING
	contact.exit_point = (d[5] as Vector3) + contact.direction * 0.05
	if not d[6]:
		d[6] = true
		if d[2] != null:
			(d[2] as HoleSet.Hole).s_drill = (d[2] as HoleSet.Hole).s_out
		var fx := DamageFx.of(self)
		if fx != null:
			fx.blow_out(d[5], contact.direction, _velocity(vehicle), contact.radius, self)
		left -= 2.0 * contact.radius / plate_width
		if model != null and randf() < 0.6:
			model.shield_camera_lost(self)
		if left < 0.35 and model != null:
			model.break_shield(self)


## Where a beam entering at the contact comes out of the plate's far side.
func _exit_point(contact: ProjectileManager.BeamContact) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(contact.point + contact.direction * 8.0, contact.point, Layers.PHYS_SHIELD)
	var r := space.intersect_ray(q)
	return r.position if not r.is_empty() else contact.point + contact.direction * 0.3


static func _velocity(vehicle: Node) -> Vector3:
	var body := vehicle as RigidBody3D
	return body.linear_velocity if body != null else Vector3.ZERO


func get_solid_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for body in _bodies:
		rids.append(body.get_rid())
	return rids


## Stowed (hidden by MsLoadout): nothing to hit.
func _sync_solid() -> void:
	for body in _bodies:
		body.collision_layer = Layers.PHYS_SHIELD if is_visible_in_tree() else 0


## A shot stopped on the shield (bullets, missiles, beams without energy). The suit's own
## (a vulcan burst into its own shield) just ends there; anyone else's counts as blocked.
func apply_hit(_damage: float, _at: Vector3, _direction: Vector3, source: Node) -> void:
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle == null or source == vehicle:
		return
	var fcs := vehicle.find_component(FireControl) as FireControl
	if fcs != null:
		fcs.register_hit(true)
