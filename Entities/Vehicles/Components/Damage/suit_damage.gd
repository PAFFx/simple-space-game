class_name SuitDamage
extends Node

## Armour by location. A shot that reaches the body hurts the part whose hitbox is nearest
## the point it landed (the suit's CollisionShape3D children, by name), so one hit is a
## cost, not the end:
##
##   head      the vulcans and the head's main camera (its angles 5× worse)
##   arm R/L   the weapons that arm carries or aims (rifle; shield missiles and saber)
##   leg R/L   the thrusters on that leg
##   backpack  the mains at half thrust
##   torso     the core: when it goes, the suit is out (FCS off, weapons dead)
##
## A part already gone passes half of what hits it on to the torso. The shield has its own
## integrity: blocks wear it down, and when it is gone it comes off the suit. MobileSuitBody
## makes one of these if the suit has none; repair() puts it all back (the range's rearm).

signal part_damaged(part: StringName, hit_points: float)
signal part_destroyed(part: StringName)
signal suit_destroyed

const CORE := &"torso"

## Part → full hit points.
@export var max_hit_points := {
	&"head": 150.0, &"torso": 600.0, &"backpack": 300.0,
	&"arm_r": 200.0, &"arm_l": 200.0, &"leg_r": 250.0, &"leg_l": 250.0,
}
## Hitbox name → [[part, share of the damage], …].
@export var hitboxes := {
	&"ColHead": [[&"head", 1.0]],
	&"ColTorso": [[&"torso", 1.0]],
	&"ColPelvis": [[&"torso", 1.0]],
	&"ColBackpack": [[&"backpack", 1.0]],
	&"ColShoulderR": [[&"arm_r", 0.5], [&"torso", 0.5]],
	&"ColShoulderL": [[&"arm_l", 0.5], [&"torso", 0.5]],
	&"ColArmR": [[&"arm_r", 1.0]],
	&"ColArmL": [[&"arm_l", 1.0]],
	&"ColLegR": [[&"leg_r", 1.0]],
	&"ColFootR": [[&"leg_r", 1.0]],
	&"ColLegL": [[&"leg_l", 1.0]],
	&"ColFootL": [[&"leg_l", 1.0]],
}
@export var shield_integrity: float = 1200.0
## How much worse the sensors' angles get with the head gone.
@export var head_sensor_penalty: float = 5.0

var hit_points := {}
var shield := 0.0
var destroyed := false
## Last part hit (the range panel shows it).
var last_part: StringName = &""

var _vehicle: VehicleBase
var _shapes: Array[CollisionShape3D] = []
var _thrust := {}            ## Thruster → max_thrust when whole
var _sigmas := []            ## sensor angles when whole


func _ready() -> void:
	_vehicle = VehicleBase.find_vehicle(self)
	for child in _vehicle.get_children():
		if child is CollisionShape3D and hitboxes.has(StringName(child.name)):
			_shapes.append(child)
	repair()


func is_destroyed(part: StringName) -> bool:
	return hit_points.get(part, 1.0) <= 0.0


## 0..1 of each part's hit points, and the shield's.
func get_fraction(part: StringName) -> float:
	return clampf(hit_points.get(part, 0.0) / maxf(max_hit_points.get(part, 1.0), 1.0), 0.0, 1.0)


func get_shield_fraction() -> float:
	return clampf(shield / maxf(shield_integrity, 1.0), 0.0, 1.0)


## A shot reached the body at `position` (world).
func apply_hit(damage: float, position: Vector3) -> void:
	if destroyed:
		return
	var box := _nearest_hitbox(position)
	if box == null:
		_hurt(CORE, damage)
		return
	for entry: Array in hitboxes[StringName(box.name)]:
		_hurt(entry[0], damage * entry[1])


## The shield stopped a shot.
func apply_shield_hit(damage: float, shield_node: MsEquipment) -> void:
	if shield <= 0.0:
		return
	shield -= damage
	if shield > 0.0:
		return
	shield = 0.0
	ProjectileManager.of(self).explode(shield_node.global_position, _velocity(), 8.0)
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	if loadout != null:
		loadout.set_equipped(shield_node, false)
	part_destroyed.emit(&"shield")


func repair() -> void:
	for part: StringName in max_hit_points:
		hit_points[part] = max_hit_points[part]
	shield = shield_integrity
	destroyed = false
	last_part = &""
	var loadout := _vehicle.find_component(MsLoadout) as MsLoadout
	if loadout != null:
		for eq in loadout.equipment:
			if eq is MsShield and not eq.equipped:
				loadout.set_equipped(eq, true)
	var thrust_back := not _thrust.is_empty()
	for thruster: Thruster in _thrust:
		thruster.max_thrust = _thrust[thruster]
		thruster.enabled = true
	_thrust.clear()
	var sensors := _sensors()
	if sensors != null and not _sigmas.is_empty():
		sensors.narrow_sigma_mrad = _sigmas[0]
		sensors.wide_sigma_mrad = _sigmas[1]
		sensors.body_sigma_mrad = _sigmas[2]
	_sigmas.clear()
	var fcs := _fire_control()
	if fcs != null:
		for weapon: MsWeapon in fcs.weapons.values():
			weapon.broken = false
	var fc := _flight_computer()
	if fc != null:
		fc.fcs_enabled = true
		if thrust_back:
			fc.rebuild_capability_map_async()


func _hurt(part: StringName, amount: float) -> void:
	if amount <= 0.0 or destroyed:
		return
	if is_destroyed(part) and part != CORE:
		_hurt(CORE, amount * 0.5)
		return
	last_part = part
	hit_points[part] = maxf(hit_points[part] - amount, 0.0)
	part_damaged.emit(part, hit_points[part])
	if hit_points[part] <= 0.0:
		_lose(part)


func _lose(part: StringName) -> void:
	part_destroyed.emit(part)
	match part:
		&"head":
			_break_weapons(func(w: MsWeapon) -> bool: return w.mount_bone == &"head")
			var sensors := _sensors()
			if sensors != null and _sigmas.is_empty():
				_sigmas = [sensors.narrow_sigma_mrad, sensors.wide_sigma_mrad, sensors.body_sigma_mrad]
				sensors.narrow_sigma_mrad *= head_sensor_penalty
				sensors.wide_sigma_mrad *= head_sensor_penalty
		&"arm_r":
			_break_weapons(func(w: MsWeapon) -> bool: return _weapon_side(w) == "R")
		&"arm_l":
			_break_weapons(func(w: MsWeapon) -> bool: return _weapon_side(w) == "L")
		&"leg_r":
			_cut_thrusters(["Attach_shin_R", "Attach_foot_R"], 0.0)
		&"leg_l":
			_cut_thrusters(["Attach_shin_L", "Attach_foot_L"], 0.0)
		&"backpack":
			_cut_thrusters(["Attach_backpack"], 0.5)
		CORE:
			_destroy_suit()


## The arm a weapon depends on, "R" / "L", or "" (head, none).
static func _weapon_side(w: MsWeapon) -> String:
	for bone: StringName in [w.aim_bone, w.mount_bone, w.equipment.mount_bone if w.equipment != null else &""]:
		var name := String(bone)
		if name.begins_with("head"):
			return ""
		if name.ends_with(".R"):
			return "R"
		if name.ends_with(".L"):
			return "L"
	return ""


func _break_weapons(which: Callable) -> void:
	var fcs := _fire_control()
	if fcs == null:
		return
	for weapon: MsWeapon in fcs.weapons.values():
		if which.call(weapon):
			weapon.broken = true


## Thrusters under the named attachments: off (scale 0) or weaker.
func _cut_thrusters(attachments: Array, scale: float) -> void:
	var root := _vehicle.get_node_or_null(^"Thrusters")
	if root == null:
		return
	for attach_name: String in attachments:
		var attach := root.get_node_or_null(attach_name)
		if attach == null:
			continue
		for node in attach.find_children("*", "", true, false):
			var thruster := node as Thruster
			if thruster == null:
				continue
			if not _thrust.has(thruster):
				_thrust[thruster] = thruster.max_thrust
			if scale <= 0.0:
				thruster.enabled = false
			else:
				thruster.max_thrust = _thrust[thruster] * scale
	var fc := _flight_computer()
	if fc != null:
		fc.rebuild_capability_map_async()


func _destroy_suit() -> void:
	destroyed = true
	var body := _vehicle as Node as RigidBody3D
	var at := body.global_transform * body.center_of_mass if body != null else _vehicle.global_position
	ProjectileManager.of(self).explode(at, _velocity(), 18.0)
	var fc := _flight_computer()
	if fc != null:
		fc.fcs_enabled = false
	_break_weapons(func(_w: MsWeapon) -> bool: return true)
	suit_destroyed.emit()


func _nearest_hitbox(position: Vector3) -> CollisionShape3D:
	var best: CollisionShape3D = null
	var best_d := INF
	for shape in _shapes:
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		# Signed distance to the box: negative inside, so the one it is deepest in wins.
		var q := (shape.global_transform.affine_inverse() * position).abs() - box.size * 0.5
		var d := q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
		if d < best_d:
			best_d = d
			best = shape
	return best


func _velocity() -> Vector3:
	var body := _vehicle as Node as RigidBody3D
	return body.linear_velocity if body != null else Vector3.ZERO


func _fire_control() -> FireControl:
	return _vehicle.find_component(FireControl) as FireControl


func _flight_computer() -> FlightComputer:
	return _vehicle.find_component(FlightComputer) as FlightComputer


func _sensors() -> SensorSuite:
	return _vehicle.find_component(SensorSuite) as SensorSuite
