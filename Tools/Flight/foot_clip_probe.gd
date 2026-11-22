extends SceneTree

## How far the RX-93's feet can turn at the ankle before they meet the leg: each foot is
## turned through a pitch × roll grid (on top of the pose, by a modifier that runs last)
## and points spread over its surface are tested against convex hulls of the shin, calf
## plate, thigh, rear/side skirts and the other leg. Points already inside a hull at 0/0
## (the ankle joint itself) don't count. Prints a table per foot and leg pose; `render`
## also saves close views of the feet at the given angles. `flight`: the suit flies
## MANOEUVRES and prints how far and fast each foot eases after its sole nozzle, and how
## far the nozzle swings on top; `foot.<ThrusterGuard property>=<value>` overrides the
## feet's follow (e.g. foot.smoothing_time=0.2); with `render` it also saves shots
## mid-manoeuvre.
##
##   godot-double --headless --path . -s Tools/Flight/foot_clip_probe.gd -- [step=10] [points=3000] [poses=neutral,strafe,tuck]
##   bspc rule -a 'Simple Space Game:Godot_Engine' -o desktop=^7 follow=off focus=off state=floating rectangle=1280x720+0+0
##   godot-double --path . --resolution 1280x720 -s Tools/Flight/foot_clip_probe.gd -- render=<dir> [angles=p,r;p,r;...]
##   godot-double --headless --path . -s Tools/Flight/foot_clip_probe.gd -- flight [foot.<property>=<value> ...] [render=<dir>]
##
## Pitch: + toe up, − toe down. Roll: + the sole turns to face outward (eversion), − inward.
## The counts include the ankle block nesting inside the hollow shin cuff, which can't be
## seen: judge visible clipping from the renders (2026-11-22: pitch −40…+30 and roll ±15
## clean; from ±20 roll the ankle block pokes out through the side of the shin).

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const PROBE_LAYER := 1 << 30
const HULLS := [&"ShinR", &"ShinL", &"CalfGuardR", &"CalfGuardL", &"ThighR", &"ThighL",
		&"FootR", &"FootL", &"SkirtRearR", &"SkirtRearL", &"SkirtSideR", &"SkirtSideL"]
## Leg poses: AMBAC offsets [bone, axis, deg] (the stances' leg angles, both legs).
const LEG_POSES := {
	"neutral": [],
	"strafe": [["thigh.R", Vector3.RIGHT, 70.0], ["shin.R", Vector3.RIGHT, -95.0], ["thigh.R", Vector3.BACK, 6.0],
			["thigh.L", Vector3.RIGHT, 70.0], ["shin.L", Vector3.RIGHT, -95.0], ["thigh.L", Vector3.BACK, -6.0]],
	"tuck": [["thigh.R", Vector3.RIGHT, 85.0], ["shin.R", Vector3.RIGHT, -110.0],
			["thigh.L", Vector3.RIGHT, 85.0], ["shin.L", Vector3.RIGHT, -110.0]],
	"climb": [["thigh.R", Vector3.RIGHT, 25.0], ["shin.R", Vector3.RIGHT, -35.0],
			["thigh.L", Vector3.RIGHT, 25.0], ["shin.L", Vector3.RIGHT, -35.0]],
	"kick": [["thigh.R", Vector3.RIGHT, -30.0], ["shin.R", Vector3.RIGHT, -110.0],
			["thigh.L", Vector3.RIGHT, -30.0], ["shin.L", Vector3.RIGHT, -110.0]],
}
## Eye / target in the suit's frame (front −Z, right +X), around the right foot.
const VIEWS := {
	front = [Vector3(4.0, 2.6, -11.0), Vector3(4.0, 2.4, -1.0)],
	outside = [Vector3(13.0, 3.0, -1.0), Vector3(4.2, 2.4, -0.8)],
	back = [Vector3(4.0, 3.5, 10.0), Vector3(4.0, 2.6, 0.0)],
	inside = [Vector3(-3.0, 2.8, -4.0), Vector3(3.6, 2.4, -0.6)],
}
## Whole legs, for flight shots.
const FLIGHT_VIEWS := {
	legs_front = [Vector3(6.0, 9.0, -30.0), Vector3(0.0, 5.0, 0.0)],
	legs_right = [Vector3(28.0, 8.0, -6.0), Vector3(0.0, 5.0, 0.0)],
}
## Flight mode: name, seconds, translation, rotation, boost, full boost.
const MANOEUVRES := [
	["rest", 1.0, Vector3.ZERO, Vector3.ZERO, false, false],
	["boost_up", 1.5, Vector3.UP, Vector3.ZERO, true, false],
	["full_up", 1.5, Vector3.UP, Vector3.ZERO, true, true],
	["boost_right", 1.5, Vector3.RIGHT, Vector3.ZERO, true, false],
	["full_left", 1.5, Vector3.LEFT, Vector3.ZERO, true, true],
	["boost_fwd", 1.5, Vector3.FORWARD, Vector3.ZERO, true, false],
	["boost_back", 1.5, Vector3.BACK, Vector3.ZERO, true, false],
	["full_down", 1.5, Vector3.DOWN, Vector3.ZERO, true, true],
	["pitch", 1.0, Vector3.ZERO, Vector3(1, 0, 0), false, false],
	["roll", 1.0, Vector3.ZERO, Vector3(0, 0, 1), false, false],
	["yaw", 1.0, Vector3.ZERO, Vector3(0, 1, 0), false, false],
	["up_right_roll", 1.5, Vector3(1, 1, 0), Vector3(0, 0, -1), true, false],
	["coast", 1.5, Vector3.ZERO, Vector3.ZERO, false, false],
]


class ScriptedInput extends PilotInputSource:
	var hold := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := PilotCommand.new()
		out.translation = hold.translation
		out.rotation = hold.rotation
		out.boost = hold.boost
		out.boost_full = hold.boost_full
		return out


class FootTurn extends SkeletonModifier3D:
	## bone → [pitch rad, roll rad]; roll is mirrored on the left so + is outward.
	var turns := {}

	func _process_modification_with_delta(_delta: float) -> void:
		var skel := get_skeleton()
		for bone: StringName in turns:
			var idx := skel.find_bone(bone)
			var g := skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
			var side := 1.0 if String(bone).ends_with(".R") else -1.0
			var a: Vector2 = turns[bone]
			var q := Quaternion(Vector3.BACK, a.y * side) * Quaternion(Vector3.RIGHT, a.x)
			skel.set_bone_pose_rotation(idx, skel.get_bone_pose_rotation(idx) * (g.inverse() * q * g))


var _turn := FootTurn.new()



func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var step := 10.0
	var count := 3000
	var poses := PackedStringArray(["neutral", "strafe", "tuck", "climb", "kick"])
	var render := ""
	var angles: Array[Vector2] = [Vector2(0, 0), Vector2(30, 0), Vector2(-40, 0), Vector2(0, 20), Vector2(0, -20),
			Vector2(0, 30), Vector2(0, -30), Vector2(-30, 20), Vector2(25, -20)]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("step="):
			step = a.substr(5).to_float()
		elif a.begins_with("points="):
			count = a.substr(7).to_int()
		elif a.begins_with("poses="):
			poses = a.substr(6).split(",")
		elif a.begins_with("render="):
			render = a.substr(7)
		elif a.begins_with("angles="):
			angles.clear()
			for pr in a.substr(7).split(";"):
				var v := pr.split(",")
				angles.append(Vector2(v[0].to_float(), v[1].to_float()))
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	await _frames(20)
	var vehicle: VehicleBase
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			vehicle = node
	var fc := vehicle.find_component(FlightComputer) as FlightComputer
	var ambac := vehicle.find_component(AmbacController) as AmbacController
	var skel := (vehicle.find_component(MsLoadout) as MsLoadout).skeleton
	for eq in vehicle.find_children("*", "MsEquipment", true, false):
		if "Funnel" in eq.name or "Bazooka" in eq.name:
			(eq as Node3D).visible = false
	if OS.get_cmdline_user_args().has("flight"):
		await _flight(vehicle, fc, skel, render)
		quit()
		return
	fc.process_mode = Node.PROCESS_MODE_DISABLED
	skel.add_child(_turn)

	if render != "":
		await _render(vehicle, ambac, skel, render, angles)
		quit()
		return

	# Each part: its convex hull (cheap first test, on PROBE_LAYER) and its real triangles
	# (on a layer of its own) for the inside test.
	var layers := {}   # part name → mesh layer
	for k in HULLS.size():
		var part: StringName = HULLS[k]
		var mesh := skel.get_node_or_null(NodePath(String(part))) as MeshInstance3D
		if mesh == null:
			print("FOOT skip ", part)
			continue
		var attach := _attach(skel, part)
		var to_bone := _to_bone(skel, mesh, attach.bone_name)
		var pts := PackedVector3Array()
		var faces := PackedVector3Array()
		for s in mesh.mesh.get_surface_count():
			var arr := mesh.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for x in v:
				pts.append(to_bone * x)
			for i: int in arr[Mesh.ARRAY_INDEX]:
				faces.append(to_bone * v[i])
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		var tri := ConcavePolygonShape3D.new()
		tri.set_faces(faces)
		tri.backface_collision = true
		layers[String(part)] = 1 << (8 + k)
		for spec in [[hull, PROBE_LAYER], [tri, layers[String(part)]]]:
			var body := StaticBody3D.new()
			body.name = String(part)
			body.collision_layer = spec[1]
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			shape.shape = spec[0]
			body.add_child(shape)
			attach.add_child(body)

	seed(3)
	var feet := {}   # side → [attach, points]
	for side in ["R", "L"]:
		var part := StringName("Foot" + side)
		var mesh := skel.get_node(NodePath(String(part))) as MeshInstance3D
		var attach := _attach(skel, part)
		feet[side] = [attach, _surface_points(mesh.mesh, _to_bone(skel, mesh, attach.bone_name), count)]
	await _frames(3)

	var space := vehicle.get_world_3d().direct_space_state
	var pitches: Array[float] = []
	var p := -50.0
	while p <= 40.0 + 0.01:
		pitches.append(p)
		p += step
	var rolls: Array[float] = []
	var r := -40.0
	while r <= 40.0 + 0.01:
		rolls.append(r)
		r += step

	print("FOOT cells: points inside another part / deepest (m). Pitch + toe up, roll + sole faces out.")
	for pose in poses:
		_pose_legs(ambac, LEG_POSES[pose])
		for side: String in feet:
			var bone := StringName("foot." + side)
			var entry: Array = feet[side]
			_turn.turns = {bone: Vector2.ZERO}
			await _frames(3)
			# Points inside something at 0/0 are the joint itself.
			var base := {}
			var xf := (entry[0] as Node3D).global_transform
			for i in (entry[1] as Array).size():
				if _inside(space, xf * (entry[1][i] as Vector3), layers, "Foot" + side) != "":
					base[i] = true
			print("FOOT %s %s: %d points, %d inside at rest (skipped)" % [pose, side, (entry[1] as Array).size(), base.size()])
			var header := "FOOT   roll→ "
			for rl in rolls:
				header += "%10.0f" % rl
			print(header)
			var parts := {}
			for pt in pitches:
				var line := "FOOT p%+4.0f    " % pt
				for rl in rolls:
					_turn.turns = {bone: Vector2(deg_to_rad(pt), deg_to_rad(rl))}
					await _frames(1)
					xf = (entry[0] as Node3D).global_transform
					var hits := 0
					var deepest := 0.0
					for i in (entry[1] as Array).size():
						if base.has(i):
							continue
						var at := xf * (entry[1][i] as Vector3)
						var n := _inside(space, at, layers, "Foot" + side)
						if n == "":
							continue
						hits += 1
						parts[n] = true
						deepest = maxf(deepest, _depth(space, at, layers[n]))
					line += "%10s" % ("-" if hits == 0 else "%d/%.2f" % [hits, deepest])
				print(line)
			print("FOOT %s %s parts hit: %s" % [pose, side, " ".join(parts.keys())])
	_turn.turns = {}
	quit()


func _flight(vehicle: VehicleBase, fc: FlightComputer, skel: Skeleton3D, render: String) -> void:
	var input := ScriptedInput.new()
	fc.add_child(input)
	fc.input_source = input
	var cam: Camera3D
	if render != "":
		DirAccess.make_dir_recursive_absolute(render)
		cam = Camera3D.new()
		cam.cull_mask = Layers.MASK_THIRD_PERSION
		cam.fov = 40.0
		cam.far = 20000.0
		vehicle.add_child(cam)
		cam.make_current()
	var guards := vehicle.find_component(ThrusterGuards) as ThrusterGuards
	var feet: Array = []   # [side, guard index, thruster, last turn]
	for i in guards.guards.size():
		var g := guards.guards[i]
		if not g.follow_aim:
			continue
		for a in OS.get_cmdline_user_args():
			if a.begins_with("foot."):
				var kv := a.substr(5).split("=")
				g.set(kv[0], kv[1].to_float())
		feet.append([String(g.bone_name).right(1), i, vehicle.find_child(String(g.thrusters[0]), true, false) as Thruster, Quaternion.IDENTITY])
	await _frames(30)
	print("FLIGHT  manoeuvre        side  foot pitch° / tilt° (min..max)      foot °/s max  rms   nozzle on foot max°  throttle")
	var all_rate := 0.0
	var all_n := 0
	var all_max := 0.0
	for m: Array in MANOEUVRES:
		input.hold.translation = m[2]
		input.hold.rotation = m[3]
		input.hold.boost = m[4]
		input.hold.boost_full = m[5]
		var stats := {}
		for f: Array in feet:
			stats[f[0]] = [INF, -INF, INF, -INF, 0.0, 0.0, 0.0, 0.0, 0]
		var frames := int(m[1] * 60.0)
		for i in frames:
			await process_frame
			var dt := 1.0 / 60.0   # headless frames advance one physics tick
			for f: Array in feet:
				var st: Array = stats[f[0]]
				var t: Thruster = f[2]
				var q: Quaternion = guards._smoothed[f[1]]
				var d := q * Vector3.FORWARD
				var pitch := rad_to_deg(atan2(d.y, -d.z))
				var tilt := rad_to_deg(atan2(d.x, -d.z))
				var rate := rad_to_deg((f[3] as Quaternion).angle_to(q)) / dt
				f[3] = q
				st[0] = minf(st[0], pitch)
				st[1] = maxf(st[1], pitch)
				st[2] = minf(st[2], tilt)
				st[3] = maxf(st[3], tilt)
				st[4] = maxf(st[4], rate)
				st[5] += rate * rate
				st[6] = maxf(st[6], rad_to_deg(t.get_gimbal_rotation().get_angle()))
				st[7] += t.throttle
				st[8] += 1
			if cam != null and i == frames * 2 / 3:
				for view: String in FLIGHT_VIEWS:
					var v: Array = FLIGHT_VIEWS[view]
					cam.transform = Transform3D(Basis.IDENTITY, v[0]).looking_at(v[1], Vector3.UP)
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("%s/flight_%s_%s.png" % [render, m[0], view])
		for f: Array in feet:
			var st: Array = stats[f[0]]
			var n := maxi(st[8], 1)
			all_rate += st[5]
			all_n += n
			all_max = maxf(all_max, st[4])
			print("FLIGHT  %-15s %s   %+6.1f..%+6.1f / %+6.1f..%+6.1f      %6.1f  %5.1f   %6.1f              %.2f" % [m[0], f[0],
					st[0], st[1], st[2], st[3], st[4], sqrt(st[5] / n), st[6], st[7] / n])
	print("FLIGHT feet: rate rms %.1f °/s, max %.1f °/s" % [sqrt(all_rate / maxi(all_n, 1)), all_max])


## Name of the part whose real surface encloses `at` (odd crossings along most of three
## rays), "" if none. Only parts whose hull holds the point are ray-tested.
func _inside(space: PhysicsDirectSpaceState3D, at: Vector3, layers: Dictionary, own: String) -> String:
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = PROBE_LAYER
	query.position = at
	for hit in space.intersect_point(query, 8):
		var n := String((hit.collider as Node).name)
		if n == own:
			continue
		var odd := 0
		for dir: Vector3 in RAY_DIRS:
			if _crossings(space, at, dir, layers[n]) % 2 == 1:
				odd += 1
		if odd >= 2:
			return n
	return ""


const RAY_DIRS := [Vector3(1.0, 0.13, 0.07), Vector3(-0.11, 1.0, 0.05), Vector3(0.06, -0.09, 1.0)]


static func _crossings(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, mask: int) -> int:
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = mask
	ray.hit_back_faces = true
	var d := dir.normalized()
	var n := 0
	ray.from = from
	for i in 32:
		ray.to = ray.from + d * 40.0
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			break
		n += 1
		ray.from = (hit.position as Vector3) + d * 0.002
	return n


## Shortest way out of a part along the six axes, m (how deep a point sits).
static func _depth(space: PhysicsDirectSpaceState3D, at: Vector3, mask: int) -> float:
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = mask
	ray.hit_back_faces = true
	ray.from = at
	var best := INF
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		ray.to = at + d * 10.0
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			best = minf(best, at.distance_to(hit.position))
	return best if best < INF else 0.0


func _render(vehicle: VehicleBase, ambac: AmbacController, skel: Skeleton3D, out: String, angles: Array[Vector2]) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.cull_mask = Layers.MASK_THIRD_PERSION
	cam.fov = 40.0
	cam.far = 20000.0
	vehicle.add_child(cam)
	cam.make_current()
	# Only the suit: nothing behind the feet.
	for n in vehicle.get_parent().get_children():
		if n != vehicle and n is Node3D:
			(n as Node3D).visible = false
	_pose_legs(ambac, [])
	for a in angles:
		_turn.turns = {&"foot.R": a * PI / 180.0, &"foot.L": a * PI / 180.0}
		for view: String in VIEWS:
			for part in [&"ThighL", &"ShinL", &"CalfGuardL", &"FootL", &"SkirtFrontL", &"SkirtSideL"]:
				var mi := skel.get_node_or_null(NodePath(String(part))) as Node3D
				if mi:
					mi.visible = view != "inside"
			var v: Array = VIEWS[view]
			cam.transform = Transform3D(Basis.IDENTITY, v[0]).looking_at(v[1], Vector3.UP)
			await _frames(3)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/foot_p%+03.0f_r%+03.0f_%s.png" % [out, a.x, a.y, view])


func _pose_legs(ambac: AmbacController, joints: Array) -> void:
	for i in ambac.angles.size():
		ambac.angles[i] = 0.0
		ambac.rates[i] = 0.0
	for j: Array in joints:
		var i := ambac.find_joint(j[0], j[1])
		if i >= 0:
			ambac.angles[i] = deg_to_rad(j[2])


static func _attach(skel: Skeleton3D, part: StringName) -> BoneAttachment3D:
	var attach := BoneAttachment3D.new()
	attach.bone_name = _bone_name(part)
	skel.add_child(attach)
	return attach


static func _to_bone(skel: Skeleton3D, mesh: MeshInstance3D, bone: String) -> Transform3D:
	return skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse() \
			* skel.global_transform.affine_inverse() * mesh.global_transform


## About `count` points spread over a mesh's surface by area, through `xf`.
static func _surface_points(mesh: Mesh, xf: Transform3D, count: int) -> Array:
	var tris: Array = []
	var area := 0.0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var a := xf * v[idx[t]]
			var b := xf * v[idx[t + 1]]
			var c := xf * v[idx[t + 2]]
			var ar := (b - a).cross(c - a).length() * 0.5
			tris.append([a, b, c, ar])
			area += ar
	var out: Array = []
	for tri: Array in tris:
		var n: float = tri[3] / area * count
		for i in int(n) + (1 if randf() < n - int(n) else 0):
			var r1 := sqrt(randf())
			var r2 := randf()
			out.append((tri[0] as Vector3) * (1.0 - r1) + (tri[1] as Vector3) * (r1 * (1.0 - r2)) + (tri[2] as Vector3) * (r1 * r2))
	return out


static func _bone_name(part: StringName) -> String:
	var s := String(part)
	var side := ""
	if s.ends_with("R") or s.ends_with("L"):
		side = "." + s.right(1)
		s = s.left(-1)
	return s.to_snake_case() + side


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame
