extends SceneTree

## Renders beam damage on the RX-93 to PNGs: the drilling, the hole from in front and from
## behind, how it cools, a severed limb, the shield's I-field, the drone, the reactor.
## Frames are at exact sim times (run with --fixed-fps 60); cooling is shown by moving the
## holes' clock on (HoleSet.now), not by waiting.
##
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 --fixed-fps 60 -s Tools/Damage/damage_snapshot.gd -- <out_dir> [cases]
##
## cases: comma list of hole,forearm,shin,chest,thigh,back,cool,shield,bareshield,drone,reactor

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const RIFLE := preload("res://Entities/Projectiles/Specs/nu_beam_rifle.tres")

var _out := "user://damage_snapshot"
var _suit: RigidBody3D
var _vehicle: VehicleBase
var _model: DamageModel
var _skel: Skeleton3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var cases := PackedStringArray(["forearm", "shin", "chest", "thigh", "back", "cool", "shield", "bareshield", "drone", "reactor"])
	if args.size() > 1:
		cases = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred(cases)


func _run(cases: PackedStringArray) -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _frames(30)
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_vehicle = node
			break
	_suit = _vehicle as Node as RigidBody3D
	_model = _vehicle.find_component(DamageModel) as DamageModel
	_skel = (_vehicle.find_component(LimbReaction) as LimbReaction).skeleton
	(_vehicle.find_component(FireControl) as FireControl).sensors.enabled = false
	_cam = Camera3D.new()
	_cam.cull_mask = Layers.MASK_THIRD_PERSION
	_cam.fov = 40.0
	_cam.far = 20000.0
	_cam.near = 0.1
	current_scene.add_child(_cam)
	_cam.make_current()
	for c in cases:
		match c:
			"forearm": await _case("forearm", &"forearm.R", Vector3.ZERO, Vector3(-0.5, 0.0, 1.0), Vector3(14, 2, -10), [0.02, 0.05, 0.12, 0.4, 1.5])
			"shin": await _case("shin", &"shin.R", Vector3(0.3, 1.0, 0.0), Vector3(-0.3, 0.1, 1.0), Vector3(12, 3, -16), [0.02, 0.06, 0.15, 0.5, 2.0])
			"chest": await _case("chest", &"chest", Vector3(0.0, 0.4, 0.0), Vector3(0.15, -0.05, 1.0), Vector3(-14, 4, -22), [0.02, 0.06, 0.15, 0.5, 2.0])
			"thigh": await _case("thigh", &"thigh.L", Vector3.ZERO, Vector3(0.3, 0.0, 1.0), Vector3(-22, 2, -24), [0.03, 0.1, 0.3, 1.0, 3.0])
			"back": await _case("back", &"forearm.L", Vector3.ZERO, Vector3(0.6, 0.0, 1.0), Vector3(-12, 3, 14), [0.02, 0.06, 0.2, 0.6, 1.5])
			"cool": await _cool()
			"hole": await _hole()
			"sever": await _sever()
			"shield": await _shield(true)
			"bareshield": await _shield(false)
			"drone": await _drone()
			"reactor": await _case("reactor", &"pelvis", Vector3(0.0, 0.75, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-260, 120, -420), [0.05, 0.12, 0.3, 0.8, 2.0])
	quit()


func _part_centre(part_name: StringName) -> Vector3:
	var p := _model.find_part(part_name)
	return _skel.global_transform * _skel.get_bone_global_pose(p.bone) * p.aabb.get_center()


## Fires at `part` (+ offset, body frame) along `dir_body` (body frame; +z = from the front
## going back), camera at `view` (body frame, from the target), frames `times` s after contact.
func _case(tag: String, part: StringName, offset: Vector3, dir_body: Vector3, view: Vector3, times: Array) -> void:
	_model.repair()
	await _frames(20)
	var basis := _suit.global_basis
	var target := _part_centre(part) + basis * offset
	var dir := (basis * dir_body).normalized()
	_look(target + basis * view, target)
	await _frames(3)
	_save("%s_0before" % tag)
	await _fire(target - dir * 300.0, dir, tag, times)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, _suit.global_basis.y)


func _fire(at: Vector3, dir: Vector3, tag: String, times: Array) -> void:
	var pm := ProjectileManager.of(current_scene)
	var muzzle := Marker3D.new()
	current_scene.add_child(muzzle)
	muzzle.global_position = at
	var shot := pm.spawn(RIFLE, at, _suit.linear_velocity + dir * RIFLE.speed, dir, [], current_scene)
	pm.stream_from(shot, muzzle, func() -> Array: return [muzzle.global_position, _suit.linear_velocity + dir * RIFLE.speed, dir])
	var t := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var contact := 300.0 / RIFLE.speed
	var i := 0
	while i < times.size():
		await physics_frame
		t += dt
		if t >= contact + float(times[i]):
			await process_frame
			_save("%s_%d_%03dms" % [tag, i + 1, roundi(float(times[i]) * 1000.0)])
			i += 1
	muzzle.queue_free()


## One hole seen close up as it cools: frames at hole ages 0.1 … 60 s.
func _cool() -> void:
	_model.repair()
	await _frames(20)
	var basis := _suit.global_basis
	var target := _part_centre(&"shin.L") + basis * Vector3(-0.4, 1.5, 0.0)
	var dir := (basis * Vector3(0.0, 0.0, 1.0)).normalized()
	_look(target + basis * Vector3(-6, 1.5, -7), target)
	await _fire(target - dir * 300.0, dir, "cool", [0.1, 0.5])
	# Let the flash and the spray clear, then move the holes' clock on.
	for i in 150:
		await physics_frame
	for age in [3.0, 8.0, 15.0, 30.0, 60.0]:
		_model.holes.now = _hole_birth() + age
		await _frames(3)
		_save("cool_%02ds" % age)


## A through-hole in a shin, close up: drilling from the entry side, then both faces as it
## cools (hole ages 3 … 45 s).
func _hole() -> void:
	_model.repair()
	await _frames(20)
	var basis := _suit.global_basis
	var target := _part_centre(&"shin.R") + basis * Vector3(0.2, 0.8, 0.0)
	var dir := (basis * Vector3(-0.25, 0.0, 1.0)).normalized()
	var entry_view := target + basis * Vector3(5.5, 1.5, -7.5)
	var exit_view := target + basis * Vector3(6.5, 1.2, 8.0)
	_look(entry_view, target)
	await _fire(target - dir * 300.0, dir, "hole", [0.03, 0.12, 0.5])
	for i in 150:
		await physics_frame
	for age in [3.0, 8.0, 20.0, 45.0]:
		_model.holes.now = _hole_birth() + age
		_look(entry_view, target)
		await _frames(3)
		_save("hole_in_%02ds" % age)
		_look(exit_view, target)
		await _frames(3)
		_save("hole_out_%02ds" % age)


## A forearm shot off: the torn socket at the elbow and the piece tumbling away.
func _sever() -> void:
	_model.repair()
	await _frames(20)
	var basis := _suit.global_basis
	var p := _model.find_part(&"forearm.R")
	var joint := _skel.global_transform * _skel.get_bone_global_pose(p.bone)
	var dir := (basis * Vector3(-0.2, 0.0, 1.0)).normalized()
	var target := _part_centre(&"forearm.R")
	var view := joint.origin + basis * Vector3(10.0, 3.0, -7.0)
	_look(view, joint.origin)
	await _fire(target - dir * 300.0, dir, "sever", [0.1, 0.6, 1.5])
	for i in 60:
		await physics_frame
	_look(joint.origin + basis * Vector3(4.5, 1.0, -3.0), joint.origin)
	await _frames(3)
	_save("sever_stump_close")
	for child in current_scene.get_children():
		if child is RigidBody3D and child.name.begins_with("Debris"):
			var at := (child as RigidBody3D).global_transform * (child as RigidBody3D).center_of_mass
			_look(at + basis * Vector3(-6.0, 3.0, -6.0), at)
			await _frames(3)
			_save("sever_piece")
			break


func _hole_birth() -> float:
	var latest := -INF
	for p in _model.parts:
		if p.mesh != null:
			for h in _model.holes.get_holes(p.mesh):
				latest = maxf(latest, h.time)
	return latest


func _shield(charged: bool) -> void:
	_model.repair()
	await _frames(20)
	var shield := _suit.find_children("*", "MsShield", true, false)[0] as MsShield
	if not charged:
		shield.charges = 0
	var target := shield.global_transform * MsLoadout.local_box(shield).get_center()
	var basis := _suit.global_basis
	var dir := (basis * Vector3(0.8, 0.0, 0.6)).normalized()
	_look(target + basis * Vector3(-18, 4, -16), target)
	await _frames(3)
	await _fire(target - dir * 300.0, dir, "shield" if charged else "bareshield", [0.02, 0.06, 0.15, 0.5, 1.5])


func _drone() -> void:
	var drone := TargetDrone.new()
	drone.behaviour = TargetDrone.Behaviour.STATIC
	drone.control_chance = 0.0
	current_scene.add_child(drone)
	var at := _suit.global_position + _suit.global_basis * Vector3(60, 25, -160)
	drone.global_position = at
	await _frames(5)
	var dir := (_suit.global_basis * Vector3(0.4, 0, -1)).normalized()
	var aim := at + _suit.global_basis * Vector3(0, 2.5, 0)
	_look(at + _suit.global_basis * Vector3(-12, 7, 26), at)
	await _fire(aim - dir * 300.0, dir, "drone", [0.02, 0.08, 0.3, 1.0])
	drone.queue_free()


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
