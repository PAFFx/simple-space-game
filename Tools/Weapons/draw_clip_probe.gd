extends SceneTree

## Where the rifle or the arm passes through the suit during the draw: the draw is frozen
## at steps of its progress (0 stowed, 1 the grab, 2 held) and points spread over the
## rifle's and the right arm's surfaces are tested against convex hulls of the suit's parts
## (each riding its bone). Prints, per step, how many rifle points are inside each part
## ("rifle>Part") and how many arm points are inside a body part beyond what the idle pose
## has at its joints ("Arm>Part"), then the worst step of each, and the stowed rifle's gap
## to the skirt it hangs on.
##
##   godot-double --headless --path . -s Tools/Weapons/draw_clip_probe.gd -- [step=0.05] [points=4000] [raised] [legs [sweep]] [flight]
##
## `legs`: the rifle stowed, the legs posed through every stance and their AMBAC joints'
## extremes (angles set directly, the flight computer paused): rifle points in each part;
## `sweep` instead steps each thigh and knee through their range, `thighs` each thigh alone,
## `rleg` the right leg, `grid` each leg's thigh × knee over their range; `at=<p>` with the draw frozen at progress p (its skirt held), the
## right leg also checked against the held skirt. `flight draw`: drawn and stowed in turn
## while it flies (logs the right leg's AMBAC swing). `flight`: the rifle
## stowed while the suit flies MANOEUVRES, AMBAC and stances live.

## Leg poses for `legs`: name → [[bone, axis, deg], …] AMBAC offsets (the stances as in
## build_rx93_scene.gd, then the joints' ends).
const LEG_POSES := {
	"climb": [["thigh.R", Vector3.RIGHT, 25.0], ["shin.R", Vector3.RIGHT, -35.0], ["thigh.L", Vector3.RIGHT, 25.0], ["shin.L", Vector3.RIGHT, -35.0]],
	"strafe_right": [["thigh.R", Vector3.RIGHT, 70.0], ["shin.R", Vector3.RIGHT, -95.0], ["thigh.R", Vector3.BACK, 6.0], ["thigh.L", Vector3.RIGHT, 10.0], ["shin.L", Vector3.RIGHT, -15.0]],
	"strafe_left": [["thigh.L", Vector3.RIGHT, 70.0], ["shin.L", Vector3.RIGHT, -95.0], ["thigh.L", Vector3.BACK, -6.0], ["thigh.R", Vector3.RIGHT, 10.0], ["shin.R", Vector3.RIGHT, -15.0]],
	"forward": [["thigh.R", Vector3.RIGHT, -15.0], ["shin.R", Vector3.RIGHT, -25.0], ["thigh.L", Vector3.RIGHT, -15.0], ["shin.L", Vector3.RIGHT, -25.0]],
	"back": [["thigh.R", Vector3.RIGHT, 30.0], ["shin.R", Vector3.RIGHT, -25.0], ["thigh.L", Vector3.RIGHT, 30.0], ["shin.L", Vector3.RIGHT, -25.0]],
	"R knee full": [["shin.R", Vector3.RIGHT, -110.0]],
	"L knee full": [["shin.L", Vector3.RIGHT, -110.0]],
	"R thigh back": [["thigh.R", Vector3.RIGHT, -30.0]],
	"L thigh back": [["thigh.L", Vector3.RIGHT, -30.0]],
	"R kick back": [["thigh.R", Vector3.RIGHT, -30.0], ["shin.R", Vector3.RIGHT, -110.0]],
	"L kick back": [["thigh.L", Vector3.RIGHT, -30.0], ["shin.L", Vector3.RIGHT, -110.0]],
	"R tuck": [["thigh.R", Vector3.RIGHT, 85.0], ["shin.R", Vector3.RIGHT, -110.0]],
	"L tuck": [["thigh.L", Vector3.RIGHT, 85.0], ["shin.L", Vector3.RIGHT, -110.0]],
	"both back bent": [["thigh.R", Vector3.RIGHT, -30.0], ["shin.R", Vector3.RIGHT, -60.0], ["thigh.L", Vector3.RIGHT, -30.0], ["shin.L", Vector3.RIGHT, -60.0]],
	"L in twist": [["thigh.L", Vector3.BACK, 3.0], ["thigh.L", Vector3.UP, 15.0], ["shin.L", Vector3.RIGHT, -60.0]],
	"L in twist2": [["thigh.L", Vector3.BACK, 3.0], ["thigh.L", Vector3.UP, -15.0], ["shin.L", Vector3.RIGHT, -60.0]],
	"R in twist": [["thigh.R", Vector3.BACK, -3.0], ["thigh.R", Vector3.UP, 15.0], ["shin.R", Vector3.RIGHT, -60.0]],
	"R in twist2": [["thigh.R", Vector3.BACK, -3.0], ["thigh.R", Vector3.UP, -15.0], ["shin.R", Vector3.RIGHT, -60.0]],
}

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const PROBE_LAYER := 1 << 30
## Parts tested (meshes under the skeleton). The hand holds the grip: its points are inside
## the fist by design.
## Arm parts whose surface is tested against the body, and the body parts they're tested
## against (the shoulder armour wraps the upper arm by design: not tested).
const ARM := [&"ForearmR", &"UpperArmR", &"HandR"]
const BODY := [&"Chest", &"Pelvis", &"Backpack", &"MainPodR", &"SkirtRearR", &"SkirtSideR", &"SkirtFrontR",
		&"ThighR", &"Head"]
const PARTS := [&"ForearmR", &"UpperArmR", &"ShoulderR", &"Chest", &"Pelvis", &"Backpack",
		&"MainPodR", &"MainPodL", &"SkirtRearR", &"SkirtRearL", &"SkirtSideR", &"ThighR", &"ThighL",
		&"ShinR", &"ShinL", &"CalfGuardR", &"CalfGuardL", &"FootR", &"FootL", &"Head", &"SkirtFrontR", &"HandR"]

class ScriptedInput extends PilotInputSource:
	var cmd := PilotCommand.new()
	## Held each tick (flight mode): translation, rotation, boost.
	var hold := PilotCommand.new()
	func poll_command() -> PilotCommand:
		var out := cmd
		cmd = PilotCommand.new()
		out.translation = hold.translation
		out.rotation = hold.rotation
		out.boost = hold.boost
		out.boost_full = hold.boost_full
		out.brake = hold.brake
		return out

## Flight mode: [seconds, translation, rotation, boost, brake] held in turn.
const MANOEUVRES := [
	[1.5, Vector3(1, 0, 0), Vector3.ZERO, true, false], [1.5, Vector3(-1, 0, 0), Vector3.ZERO, true, false],
	[1.5, Vector3(0, 1, 0), Vector3.ZERO, true, false], [1.5, Vector3(0, 0, -1), Vector3.ZERO, true, false],
	[1.5, Vector3.ZERO, Vector3.ZERO, false, true], [1.5, Vector3(0, 0, 1), Vector3.ZERO, true, false],
	[1.5, Vector3.ZERO, Vector3(1, 0, 0), false, false], [1.5, Vector3.ZERO, Vector3(-1, 0, 0), false, false],
	[1.5, Vector3.ZERO, Vector3(0, 1, 0), false, false], [1.5, Vector3.ZERO, Vector3(0, -1, 0), false, false],
	[1.5, Vector3.ZERO, Vector3(0, 0, 1), false, false], [1.5, Vector3.ZERO, Vector3(0, 0, -1), false, false],
	[1.5, Vector3(0, -1, 0), Vector3(1, 0, 0), true, false], [1.5, Vector3(1, 0, -1), Vector3(0, 1, 0), true, false],
	[2.0, Vector3.ZERO, Vector3.ZERO, false, true],
]

var _input := ScriptedInput.new()
var grip_frame := Transform3D.IDENTITY
var hatch_at := Vector3.ZERO
var hatch_n := Vector3.BACK


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var step := 0.05
	var count := 4000
	var raised := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("step="):
			step = a.substr(5).to_float()
		elif a.begins_with("points="):
			count = a.substr(7).to_int()
		elif a == "raised":
			raised = true
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
	fc.add_child(_input)
	fc.input_source = _input
	var fcs := vehicle.find_component(FireControl) as FireControl
	var loadout := vehicle.find_component(MsLoadout) as MsLoadout
	var skel := loadout.skeleton
	var rifle := fcs.get_weapon(&"beam_rifle")
	var eq := rifle.equipment

	# Part hulls on their bones.
	for part: StringName in PARTS:
		var mesh := skel.get_node_or_null(NodePath(String(part))) as MeshInstance3D
		var bone := skel.find_bone(_bone_name(part))
		if mesh == null or bone < 0:
			print("CLIP skip ", part)
			continue
		var to_bone := skel.get_bone_global_rest(bone).affine_inverse() * skel.global_transform.affine_inverse() * mesh.global_transform
		var pts := PackedVector3Array()
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(to_bone * v)
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		var attach := BoneAttachment3D.new()
		attach.bone_name = _bone_name(part)
		skel.add_child(attach)
		var body := StaticBody3D.new()
		body.name = String(part)
		body.collision_layer = PROBE_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = hull
		body.add_child(shape)
		attach.add_child(body)

	# The backpack's equipment (hyper bazooka, fin funnels, saber) as hulls too ("eq:<mesh>").
	for e in loadout.equipment:
		if e.mount_bone != &"backpack":
			continue
		for vi in e.find_children("*", "MeshInstance3D", true, false):
			var mi := vi as MeshInstance3D
			if String(mi.name).begins_with("SensorOutline") or mi.mesh == null:
				continue
			var pts := PackedVector3Array()
			for si in mi.mesh.get_surface_count():
				pts.append_array(mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
			var hull := ConvexPolygonShape3D.new()
			hull.points = pts
			var body := StaticBody3D.new()
			body.name = "eq:" + String(mi.name)
			body.collision_layer = PROBE_LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			shape.shape = hull
			body.add_child(shape)
			mi.add_child(body)

	# Points on the arm's surface, in its bones' frames (the meshes are bound at rest).
	var arm_samples: Array = []   # [part, BoneAttachment3D, Array of points]
	seed(2)
	for part: StringName in ARM:
		var mesh := skel.get_node_or_null(NodePath(String(part))) as MeshInstance3D
		var attach := BoneAttachment3D.new()
		attach.bone_name = _bone_name(part)
		skel.add_child(attach)
		var to_bone := skel.get_bone_global_rest(skel.find_bone(attach.bone_name)).affine_inverse() \
				* skel.global_transform.affine_inverse() * mesh.global_transform
		arm_samples.append([String(part), attach, _surface_points(mesh.mesh, to_bone, 800)])

	# Points on the stow arm's parts (its links and clamp), in their frames.
	var stow_arm_samples: Array = []   # [MeshInstance3D, points]
	for arm in skel.find_children("StowArm_*", "", true, false):
		for mi in (arm as Node).get_children():
			if mi is MeshInstance3D:
				stow_arm_samples.append([mi, _surface_points((mi as MeshInstance3D).mesh, Transform3D.IDENTITY, 150)])

	# Points on the rifle's surface, by area, in its meshes' frames.
	var samples: Array = []   # [MeshInstance3D, PackedVector3Array]
	var meshes := eq.find_children("*", "MeshInstance3D", true, false)
	print("CLIP rifle meshes ", meshes.size())
	var area := 0.0
	var tris: Array = []
	for mi: MeshInstance3D in meshes:
		if String(mi.name).begins_with("SensorOutline"):
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var a := v[idx[t]]
				var b := v[idx[t + 1]]
				var c := v[idx[t + 2]]
				var ar := (b - a).cross(c - a).length() * 0.5
				tris.append([mi, a, b, c, ar])
				area += ar
	seed(1)
	var by_mesh := {}
	for tri: Array in tris:
		var n: float = tri[4] / area * count
		var k := int(n) + (1 if randf() < n - int(n) else 0)
		for i in k:
			var r1 := sqrt(randf())
			var r2 := randf()
			var p: Vector3 = (tri[1] as Vector3) * (1.0 - r1) + (tri[2] as Vector3) * (r1 * (1.0 - r2)) + (tri[3] as Vector3) * (r1 * r2)
			if not by_mesh.has(tri[0]):
				by_mesh[tri[0]] = []
			(by_mesh[tri[0]] as Array).append(p)
	for mi in by_mesh:
		samples.append([mi, by_mesh[mi]])
		print("CLIP samples on %s: %d (index-less surfaces have none)" % [mi.name, (by_mesh[mi] as Array).size()])

	await _frames(3)
	var sanity := PhysicsPointQueryParameters3D.new()
	sanity.collision_mask = PROBE_LAYER
	for b in skel.find_children("*", "StaticBody3D", true, false):
		var sh := ((b as Node).get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D
		var c := Vector3.ZERO
		for q in sh.points:
			c += q
		c /= maxf(sh.points.size(), 1)
		sanity.position = (b as Node3D).global_transform * c
		var got := vehicle.get_world_3d().direct_space_state.intersect_point(sanity, 4)
		print("CLIP sanity %s points %d hit %s" % [b.name, sh.points.size(), got.map(func(h: Dictionary) -> String: return String((h.collider as Node).name))])
	if OS.get_cmdline_user_args().has("flight"):
		await _flight(vehicle, samples)
		quit()
		return
	if OS.get_cmdline_user_args().has("legs"):
		await _legs(vehicle, fc, samples)
		quit()
		return
	# The rifle's own frame at rest in the hand (wrist end; side, top, back), which its
	# sample points are in: its grip is under the body (top < 1.7 m).
	var muzzle_node := rifle.get_node(^"Muzzle") as Node3D
	grip_frame = Transform3D((rifle.transform * muzzle_node.transform).basis.orthonormalized(),
			skel.get_bone_global_rest(skel.find_bone(&"hand.R")).origin)
	var body_xf := vehicle.global_transform
	hatch_at = body_xf * eq.draw_motion.hatch_centre
	hatch_n = (body_xf.basis * eq.draw_motion.hatch_normal).normalized()
	_input.cmd.master_mode = FireControl.MasterMode.DGFT
	await _frames(2)
	loadout.draw_frozen = true
	var space := vehicle.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = PROBE_LAYER
	var worst := {}
	var baseline := {}
	var progress := []
	var p := 0.0
	while p <= 2.0001:
		progress.append(p)
		p += step
	if raised:
		progress.append(-1.0)
	for value: float in progress:
		if value < 0.0:
			loadout.set_draw_progress(eq, 2.0)
			rifle.aim_override = Vector2.ZERO
		else:
			loadout.set_draw_progress(eq, value)
		await _frames(40 if value < 0.0 else 4)
		var hits := {}
		for entry: Array in samples:
			var xf := (entry[0] as MeshInstance3D).global_transform
			for local: Vector3 in entry[1]:
				query.position = xf * local
				for hit in space.intersect_point(query, 8):
					var part := "rifle>" + String((hit.collider as Node).name)
					# The hand holds the grip from the grab on.
					if part == "rifle>HandR" and (value < 0.0 or value >= 0.95):
						continue
					# Into the fist before the grab: just the grip (under the rifle's body), or more?
					if part == "rifle>HandR" and (grip_frame.affine_inverse() * local).y < 1.7:
						part = "grip>HandR"
					hits[part] = hits.get(part, 0) + 1
		for entry: Array in arm_samples:
			var xf := (entry[1] as Node3D).global_transform
			for local: Vector3 in entry[2]:
				query.position = xf * local
				for hit in space.intersect_point(query, 8):
					var body_part := String((hit.collider as Node).name)
					if BODY.has(StringName(body_part)) or body_part.begins_with("eq:"):
						var key := "%s>%s" % [String(entry[0]).trim_suffix("R"), body_part]
						hits[key] = hits.get(key, 0) + 1
		for entry: Array in stow_arm_samples:
			if not (entry[0] as MeshInstance3D).is_visible_in_tree():
				continue
			var xf := (entry[0] as MeshInstance3D).global_transform
			for local: Vector3 in entry[1]:
				query.position = xf * local
				# Behind the hatch's plate it is stowed inside the suit, not clipping.
				if (query.position - hatch_at).dot(hatch_n) < 0.05:
					continue
				for hit in space.intersect_point(query, 8):
					var body_part := String((hit.collider as Node).name)
					# Its base stands on the skirt; it holds the rifle until the grab.
					if body_part != "SkirtRearR":
						var key := "stowarm>" + body_part
						hits[key] = hits.get(key, 0) + 1
		if value == 0.0:
			baseline = hits.duplicate()
			_gap(space, samples, vehicle)
		for key: String in hits.keys():
			if key.contains(">"):
				hits[key] -= baseline.get(key, 0)
				if hits[key] <= 2:
					hits.erase(key)
		var tag := "up" if value < 0.0 else "%.2f" % value
		var line := "CLIP p %s:" % tag
		for part: String in hits:
			line += " %s %d" % [part, hits[part]]
			if hits[part] > (worst.get(part, [0, ""]) as Array)[0]:
				worst[part] = [hits[part], tag]
		print(line)
	print("CLIP worst: ", worst)
	quit()


## The stowed rifle against the suit while it flies MANOEUVRES (AMBAC and stances live):
## the worst sample of each manoeuvre.
func _flight(vehicle: VehicleBase, samples: Array) -> void:
	var space := vehicle.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = PROBE_LAYER
	var total := 0
	# draw: switch DGFT / NAV at each manoeuvre, so the rifle is drawn and stowed in flight.
	var draws := OS.get_cmdline_user_args().has("draw")
	if OS.get_cmdline_user_args().has("holdleg"):
		# Comparison: the right leg held out of AMBAC during the draw, as it used to be.
		var eq := (vehicle.find_component(FireControl) as FireControl).get_weapon(&"beam_rifle").equipment
		eq.draw_motion.held_groups.append(&"leg_r")
		eq.draw_motion.drawing_leg_limits = []
	var ambac := vehicle.find_component(AmbacController) as AmbacController
	var thigh := ambac.find_joint(&"thigh.R", Vector3.RIGHT)
	var knee := ambac.find_joint(&"shin.R", Vector3.RIGHT)
	for k in MANOEUVRES.size():
		var m: Array = MANOEUVRES[k]
		if draws:
			_input.cmd.master_mode = FireControl.MasterMode.DGFT if k % 2 == 0 else FireControl.MasterMode.NAV
		var leg := Vector4(INF, -INF, INF, -INF)
		_input.hold.translation = m[1]
		_input.hold.rotation = m[2]
		_input.hold.boost = m[3]
		_input.hold.brake = m[4]
		var worst := {}
		var ticks := int(m[0] * 60.0)
		if draws:
			ticks = maxi(ticks, 200)   # a whole draw or stow (3.3 s)
		for t in range(0, ticks, 3):
			await _frames(3)
			var th := rad_to_deg(ambac.angles[thigh])
			var kn := rad_to_deg(ambac.angles[knee])
			leg = Vector4(minf(leg.x, th), maxf(leg.y, th), minf(leg.z, kn), maxf(leg.w, kn))
			var hits := {}
			for entry: Array in samples:
				var xf := (entry[0] as MeshInstance3D).global_transform
				for local: Vector3 in entry[1]:
					query.position = xf * local
					for hit in space.intersect_point(query, 8):
						var part := String((hit.collider as Node).name)
						if part != "SkirtRearR":
							hits[part] = hits.get(part, 0) + 1
			for part: String in hits:
				worst[part] = maxi(worst.get(part, 0), hits[part])
		var line := "CLIP flight %2d %s rot %s%s%s, R thigh %.0f…%.0f° knee %.0f…%.0f°:" % [k, m[1], m[2],
				" boost" if m[3] else (" brake" if m[4] else ""), (" (draw)" if k % 2 == 0 else " (stow)") if draws else "",
				leg.x, leg.y, leg.z, leg.w]
		for part: String in worst:
			line += " %s %d" % [part, worst[part]]
			total += worst[part]
		print(line)
	print("CLIP flight total %d" % total)


## The stowed rifle against the legs in each of LEG_POSES.
func _legs(vehicle: VehicleBase, fc: FlightComputer, samples: Array) -> void:
	var ambac := vehicle.find_component(AmbacController) as AmbacController
	var args := OS.get_cmdline_user_args()
	# at=<p>: the draw frozen there (its skirt held as in the real draw), not stowed.
	var leg_parts: Array = []
	for a in args:
		if a.begins_with("at="):
			var loadout := vehicle.find_component(MsLoadout) as MsLoadout
			var eq := (vehicle.find_component(FireControl) as FireControl).get_weapon(&"beam_rifle").equipment
			loadout.draw_frozen = true
			loadout.set_draw_progress(eq, a.substr(3).to_float())
			var followers := vehicle.find_component(LimbFollowers) as LimbFollowers
			for bone in eq.draw_motion.held_followers:
				followers.hold_bone(bone, true)
			await _frames(40)
			# The right leg against the held skirt too.
			var skel := loadout.skeleton
			for part: StringName in [&"ThighR", &"ShinR", &"CalfGuardR"]:
				var mesh := skel.get_node_or_null(NodePath(String(part))) as MeshInstance3D
				var attach := BoneAttachment3D.new()
				attach.bone_name = _bone_name(part)
				skel.add_child(attach)
				var to_bone := skel.get_bone_global_rest(skel.find_bone(attach.bone_name)).affine_inverse() \
						* skel.global_transform.affine_inverse() * mesh.global_transform
				leg_parts.append([String(part), attach, _surface_points(mesh.mesh, to_bone, 600)])
	fc.process_mode = Node.PROCESS_MODE_DISABLED
	var space := vehicle.get_world_3d().direct_space_state
	var query := PhysicsPointQueryParameters3D.new()
	query.collision_mask = PROBE_LAYER
	var total := 0
	var poses := LEG_POSES.duplicate()
	if args.has("grid"):
		poses.clear()
		for side in ["R", "L"]:
			for thigh in [-30, -20, -10, 0, 15, 30, 45, 60, 85]:
				for knee in [0, -20, -40, -60, -80, -110]:
					poses["%s t%+d k%+d" % [side, thigh, knee]] = [["thigh." + side, Vector3.RIGHT, float(thigh)],
							["shin." + side, Vector3.RIGHT, float(knee)]]
	if args.has("rleg"):
		poses.clear()
		for thigh in range(30, -21, -5):
			poses["R thigh %+d" % thigh] = [["thigh.R", Vector3.RIGHT, float(thigh)]]
		for thigh in [0.0, 30.0]:
			for knee in range(0, -111, -10):
				poses["R t%+.0f k%+d" % [thigh, knee]] = [["thigh.R", Vector3.RIGHT, thigh], ["shin.R", Vector3.RIGHT, float(knee)]]
	if OS.get_cmdline_user_args().has("thighs"):
		poses.clear()
		for side in ["R", "L"]:
			for thigh in range(-5, -31, -5):
				poses["%s thigh %+d" % [side, thigh]] = [["thigh." + side, Vector3.RIGHT, float(thigh)]]
	if OS.get_cmdline_user_args().has("sweep"):
		poses.clear()
		for side in ["R", "L"]:
			for twist in [0.0, -15.0, 15.0]:
				for thigh in [-30.0, -15.0, 0.0, 15.0, 30.0]:
					for knee in range(0, -111, -10):
						poses["%s t%+.0f k%+d w%+.0f" % [side, thigh, knee, twist]] = [["thigh." + side, Vector3.RIGHT, thigh],
								["shin." + side, Vector3.RIGHT, float(knee)], ["thigh." + side, Vector3.UP, twist]]
	for pose: String in poses:
		for i in ambac.angles.size():
			ambac.angles[i] = 0.0
			ambac.rates[i] = 0.0
		for j: Array in poses[pose]:
			var i := ambac.find_joint(j[0], j[1])
			if i < 0:
				print("CLIP no joint ", j)
				continue
			ambac.angles[i] = deg_to_rad(j[2])
		await _frames(3)
		var hits := {}
		for entry: Array in samples:
			var xf := (entry[0] as MeshInstance3D).global_transform
			for local: Vector3 in entry[1]:
				query.position = xf * local
				for hit in space.intersect_point(query, 8):
					var part := String((hit.collider as Node).name)
					hits[part] = hits.get(part, 0) + 1
		for entry: Array in leg_parts:
			var lxf := (entry[1] as Node3D).global_transform
			for local: Vector3 in entry[2]:
				query.position = lxf * local
				for hit in space.intersect_point(query, 8):
					if String((hit.collider as Node).name) == "SkirtRearR":
						var key := "%s>SkirtRearR" % entry[0]
						hits[key] = hits.get(key, 0) + 1
		var line := "CLIP legs %-14s:" % pose
		for part: String in hits:
			line += " %s %d" % [part, hits[part]]
			total += hits[part]
		print(line)
	print("CLIP legs total %d" % total)


## Stowed rifle to the skirt plate it hangs on: rays from its surface points toward the
## suit's front (−Z), the closest hit and how many points sit within 0.2 m of the plate.
func _gap(space: PhysicsDirectSpaceState3D, samples: Array, vehicle: Node3D) -> void:
	var fwd := -vehicle.global_basis.z.normalized()
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = PROBE_LAYER
	var closest := INF
	var near := 0
	for entry: Array in samples:
		var xf := (entry[0] as MeshInstance3D).global_transform
		for local: Vector3 in entry[1]:
			ray.from = xf * local
			ray.to = ray.from + fwd * 2.0
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or String((hit.collider as Node).name) != "SkirtRearR":
				continue
			var d := ray.from.distance_to(hit.position)
			closest = minf(closest, d)
			if d < 0.2:
				near += 1
	print("CLIP stowed gap to SkirtRearR: closest %.2f m, %d rifle points within 0.2 m" % [closest, near])


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
