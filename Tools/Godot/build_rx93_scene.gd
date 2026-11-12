extends SceneTree

## Generates the RX-93 ν Gundam vehicle scene and its animation library from the
## tables below. Run after rebuilding the GLBs (Tools/Blender/build_mobile_suit_nu.py):
##
##   godot-mono --headless --path . -s Tools/Godot/build_rx93_scene.gd
##
## Same components as MSP-02 (same bone names). Thrusters sit on the nozzles the
## model actually has; see THRUSTERS.
##
## All positions/directions are in the suit's body frame (Godot: +Y up, front −Z)
## with the skeleton at rest. The output is a normal scene: tweak it in the
## editor, or edit the tables here and regenerate.

const DIR := "res://Entities/Vehicles/MobileSuits/RX93/"
const SCENE_PATH := DIR + "mobile_suit_rx93.tscn"
const ANIM_PATH := DIR + "Animations/rx93_animations.tres"
const MODEL := DIR + "Arts/mobile_suit_nu.glb"
const EQUIPMENT := "res://Entities/Equipment/RX93/"
const SKELETON := ^"Model/Armature/Skeleton3D"
const COM := Vector3(0.0, 14.6, 0.8)
const SENSOR_SCENE := \
		"res://Entities/Vehicles/Cockpits/Components/PanoramicDisplay/sensor_head.tscn"
const COCKPIT_SCENE := "res://Entities/Vehicles/Cockpits/CockpitLinearSeat/cockpit_linear_seat.tscn"
const THRUSTER_SCENE := "res://Entities/Vehicles/Components/FlightControl/Thruster/thruster.tscn"

# name, bone, position, exhaust direction, thrust kN, gimbal: [cone, fore/aft, sideways] deg,
# plume m, nozzle scale. Positions/exhausts measured from the model's nozzles (body frame).
# Total main thrust matches MSP-02 (anime-strong); the split follows the nozzle sizes.
const BACKPACK_EXHAUST := Vector3(0.0, -0.7, 0.7)
const MAIN_GIMBAL := [25.0, 25.0, 0.0]   # pods hinge fore/aft only (one-plane vectoring)
const FIXED := [0.0, 0.0, 0.0]
const MAIN_RATING_KN := 200.0
const MAIN_DYNAMICS := {spool_up_time = 0.12, spool_down_time = 0.08, gimbal_rate_deg = 240.0}
const VERNIER_DYNAMICS := {spool_up_time = 0.06, spool_down_time = 0.04, gimbal_rate_deg = 360.0}
const THRUSTERS := [
	["MainRU", "backpack", Vector3(1.25, 16.83, 3.05), BACKPACK_EXHAUST, 450.0, MAIN_GIMBAL, 14.0, 1.1],
	["MainRL", "backpack", Vector3(1.25, 15.78, 2.83), BACKPACK_EXHAUST, 450.0, MAIN_GIMBAL, 14.0, 1.1],
	["MainLU", "backpack", Vector3(-1.23, 16.83, 3.05), BACKPACK_EXHAUST, 450.0, MAIN_GIMBAL, 14.0, 1.1],
	["MainLL", "backpack", Vector3(-1.23, 15.78, 2.83), BACKPACK_EXHAUST, 450.0, MAIN_GIMBAL, 14.0, 1.1],
	["FootR", "foot.R", Vector3(4.2, 0.43, 0.38), Vector3(0, -1, 0), 300.0, FIXED, 11.0, 1.1],
	["FootL", "foot.L", Vector3(-4.18, 0.43, 0.38), Vector3(0, -1, 0), 300.0, FIXED, 11.0, 1.1],
	# Four small ports on top of the backpack's centre column; they fire up.
	["TopA", "backpack", Vector3(0.0, 20.72, 5.36), Vector3(0, 1, 0), 40.0, FIXED, 3.0, 0.4],
	["TopB", "backpack", Vector3(0.0, 20.58, 4.95), Vector3(0, 1, 0), 40.0, FIXED, 3.0, 0.4],
	["TopC", "backpack", Vector3(0.0, 20.43, 4.54), Vector3(0, 1, 0), 40.0, FIXED, 3.0, 0.4],
	["TopD", "backpack", Vector3(0.0, 20.29, 4.13), Vector3(0, 1, 0), 40.0, FIXED, 3.0, 0.4],
]

# name, center, size
const COLLIDERS := [
	["Torso", Vector3(0, 17.1, -0.8), Vector3(4.0, 4.2, 4.7)],
	["Backpack", Vector3(0, 17.5, 3.6), Vector3(4.0, 7.0, 4.0)],
	["Head", Vector3(0, 20.2, -0.4), Vector3(1.6, 2.0, 2.2)],
	["Pelvis", Vector3(0, 12.8, -0.6), Vector3(5.0, 3.6, 4.6)],
	["ShoulderR", Vector3(3.35, 18.6, 0.4), Vector3(3.0, 3.0, 2.9)],
	["ShoulderL", Vector3(-3.35, 18.6, 0.4), Vector3(3.0, 3.0, 2.9)],
	["ArmR", Vector3(4.2, 14.4, 0.1), Vector3(1.8, 6.2, 2.0)],
	["ArmL", Vector3(-4.2, 14.4, 0.1), Vector3(1.8, 6.2, 2.0)],
	["LegR", Vector3(2.8, 6.8, 0.1), Vector3(3.0, 11.0, 3.2)],
	["LegL", Vector3(-2.8, 6.8, 0.1), Vector3(3.0, 11.0, 3.2)],
	["FootR", Vector3(4.35, 1.3, -1.5), Vector3(2.8, 2.6, 4.5)],
	["FootL", Vector3(-4.35, 1.3, -1.5), Vector3(2.8, 2.6, 4.5)],
]

# bone, axis (skeleton space), group, inertia kg·m², min angle, max angle, priority
# Human-like ranges, offsets from the animated pose. Signs: +X swings a hanging limb
# forward (hip flex, elbow bend), knees bend back (−X), +Z swings a right limb outward
# (left limbs mirror), +Y twists. Inertias are about the joint: a whole leg about the
# hip is ~1.6e5 kg·m² (6 t, 11 m), an arm about the shoulder ~6e4. Twists move
# little mass, so they mostly add natural motion. The side hip swing stays small.
const AMBAC := [
	["upper_arm.R", Vector3.RIGHT, &"arm_r", 6.0e4, -35.0, 45.0, 0.7],
	["upper_arm.R", Vector3.BACK, &"arm_r", 6.0e4, -8.0, 35.0, 0.6],
	["upper_arm.R", Vector3.UP, &"arm_r", 1.0e4, -25.0, 25.0, 0.4],
	["forearm.R", Vector3.RIGHT, &"arm_r", 2.5e4, -5.0, 50.0, 0.6],
	["upper_arm.L", Vector3.RIGHT, &"arm_l", 6.0e4, -35.0, 45.0, 0.7],
	["upper_arm.L", Vector3.BACK, &"arm_l", 6.0e4, -35.0, 8.0, 0.6],
	["upper_arm.L", Vector3.UP, &"arm_l", 1.0e4, -25.0, 25.0, 0.4],
	["forearm.L", Vector3.RIGHT, &"arm_l", 2.5e4, -5.0, 50.0, 0.6],
	["thigh.R", Vector3.RIGHT, &"leg_r", 1.6e5, -20.0, 35.0, 1.0],
	["thigh.R", Vector3.BACK, &"leg_r", 1.6e5, -3.0, 6.0, 0.4],
	["thigh.R", Vector3.UP, &"leg_r", 2.0e4, -15.0, 15.0, 0.5],
	["shin.R", Vector3.RIGHT, &"leg_r", 4.5e4, -45.0, 5.0, 0.9],
	["thigh.L", Vector3.RIGHT, &"leg_l", 1.6e5, -20.0, 35.0, 1.0],
	["thigh.L", Vector3.BACK, &"leg_l", 1.6e5, -6.0, 3.0, 0.4],
	["thigh.L", Vector3.UP, &"leg_l", 2.0e4, -15.0, 15.0, 0.5],
	["shin.L", Vector3.RIGHT, &"leg_l", 4.5e4, -45.0, 5.0, 0.9],
	["spine", Vector3.UP, &"torso", 1.2e5, -12.0, 12.0, 0.8],
	["spine", Vector3.RIGHT, &"torso", 1.5e5, -10.0, 6.0, 0.5],
]

# Poses: bone → list of [axis, degrees] rotations in skeleton space (applied in order).
const POSE_RIFLE := {
	"upper_arm.R": [[Vector3.RIGHT, 75.0], [Vector3.BACK, -8.0]],
	"forearm.R": [[Vector3.RIGHT, 15.0]],
	"hand.R": [],
}
const POSE_SHIELD := {
	"upper_arm.L": [[Vector3.RIGHT, 25.0], [Vector3.BACK, 10.0]],
	"forearm.L": [[Vector3.RIGHT, 65.0], [Vector3.UP, -80.0]],
	"hand.L": [],
}
const IDLE_BONES := ["upper_arm.R", "upper_arm.L", "forearm.R", "forearm.L", "hand.R", "hand.L",
		"thigh.R", "thigh.L", "shin.R", "shin.L", "spine", "head"]
const IDLE_LENGTH := 8.0

var _skel: Skeleton3D
var _skel_in_body := Transform3D.IDENTITY


func _initialize() -> void:
	var model: Node3D = load(MODEL).instantiate()
	_skel = model.get_node(^"Armature/Skeleton3D")
	_skel_in_body = model.get_node(^"Armature").transform * _skel.transform

	DirAccess.make_dir_recursive_absolute(DIR + "Animations")
	var library := _build_animations()
	ResourceSaver.save(library, ANIM_PATH)
	library = load(ANIM_PATH)

	var root := _build_scene(library)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
	ResourceSaver.save(packed, SCENE_PATH)
	print("[build_rx93_scene] wrote %s and %s" % [SCENE_PATH, ANIM_PATH])
	model.free()
	root.free()
	quit()


# --- Scene ---

func _build_scene(library: AnimationLibrary) -> RigidBody3D:
	var root := RigidBody3D.new()
	root.name = "MobileSuitRX93"
	root.set_script(load("res://Entities/Vehicles/MobileSuits/Common/mobile_suit_body.gd"))
	root.gravity_scale = 0.0
	root.can_sleep = false
	root.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	root.center_of_mass = COM
	root.mass = 46400.0
	# The model has no hatch or open cockpit cavity, so the pilot never sees the hull.
	root.set("first_person_parts", [] as Array[StringName])

	var model: Node3D = load(MODEL).instantiate()
	model.name = "Model"
	_add(root, root, model)

	for c in COLLIDERS:
		var shape := CollisionShape3D.new()
		shape.name = "Col" + c[0]
		var box := BoxShape3D.new()
		box.size = c[2]
		shape.shape = box
		shape.position = c[1]
		_add(root, root, shape)

	var sensor_mount := _marker(root, "SensorHeadMount", Vector3(0, 20.0, -1.4))
	_add(root, sensor_mount, load(SENSOR_SCENE).instantiate())
	var cockpit_mount := _marker(root, "CockpitMount", Vector3(0, 17.2, -0.5))
	_add(root, cockpit_mount, load(COCKPIT_SCENE).instantiate())

	_build_thrusters(root)
	_build_flight_computer(root)
	_build_ambac(root)
	_build_loadout(root)
	_build_animation(root, library)

	var cam := Camera3D.new()
	cam.name = "ExternalCamera"
	cam.set_script(load("res://Common/Controls/OrbitCamera/orbit_camera.gd"))
	cam.far = 8000.0
	_add(root, root, cam)
	cam.set("focus_offset", Vector3(0, 13.0, 0))
	cam.set("distance", 45.0)
	var views := Node.new()
	views.name = "ViewSwitcher"
	views.set_script(load("res://Entities/Vehicles/Components/ViewSwitcher/view_switcher.gd"))
	_add(root, root, views)
	views.set("external_camera", cam)
	return root


func _build_thrusters(root: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Thrusters"
	_add(root, root, group)
	var thruster_scene: PackedScene = load(THRUSTER_SCENE)
	var attachments := {}
	for t in THRUSTERS:
		var bone: String = t[1]
		if not attachments.has(bone):
			var attach := BoneAttachment3D.new()
			attach.name = "Attach_" + bone.replace(".", "_")
			attach.bone_name = bone
			attach.use_external_skeleton = true
			attach.external_skeleton = NodePath("../../" + String(SKELETON))
			_add(root, group, attach)
			attachments[bone] = attach
		var pos: Vector3 = t[2]
		var exhaust: Vector3 = (t[3] as Vector3).normalized()
		var up := Vector3.UP if absf(exhaust.dot(Vector3.UP)) < 0.95 else Vector3.BACK
		# Thruster −Z = thrust direction = opposite of the exhaust.
		var body_xf := Transform3D(Basis.looking_at(-exhaust, up), pos)
		var node: Node3D = thruster_scene.instantiate()
		node.name = t[0]
		_add(root, attachments[bone], node)
		node.transform = _bone_rest_in_body(bone).affine_inverse() * body_xf
		var rating: float = t[4]
		var is_main := rating >= MAIN_RATING_KN
		node.set("max_thrust", rating * 1000.0)
		var dynamics: Dictionary = MAIN_DYNAMICS if is_main else VERNIER_DYNAMICS
		for key: String in dynamics:
			node.set(key, dynamics[key])
		var gimbal: Array = t[5]
		node.set("gimbal_limit_deg", gimbal[0])
		node.set("gimbal_pitch_limit_deg", gimbal[1])
		node.set("gimbal_yaw_limit_deg", gimbal[2])
		node.set("plume_length", t[6])
		node.set("nozzle_scale", t[7])
		node.set("hud_label", _short_label(t[0]))


func _build_flight_computer(root: Node3D) -> void:
	var fc := Node.new()
	fc.name = "FlightComputer"
	fc.set_script(load("res://Entities/Vehicles/Components/FlightControl/flight_computer.gd"))
	_add(root, root, fc)
	var law := RateCommandControlLaw.new()
	law.attitude_solver = ThrustVectoringAttitudeSolver.new()
	fc.set("control_law", law)
	var alloc := ConeProjectedAllocator.new()
	alloc.iterations = 60
	fc.set("allocator", alloc)
	fc.set("dry_mass", 30000.0)
	fc.set("propellant_capacity", 10000.0)
	fc.set("propellant", 10000.0)

	var input := Node.new()
	input.name = "PilotInput"
	input.set_script(load("res://Common/Controls/PilotInput/hotas_pilot_input.gd"))
	_add(root, fc, input)
	var bindings: Array[JoyAxisBinding] = []
	for b in [[JoyAxisBinding.Channel.ROLL, 0, 0.05], [JoyAxisBinding.Channel.PITCH, 1, 0.05],
			[JoyAxisBinding.Channel.YAW, 5, 0.08]]:
		var binding := JoyAxisBinding.new()
		binding.channel = b[0]
		binding.axis = b[1]
		binding.deadzone = b[2]
		bindings.append(binding)
	input.set("axis_bindings", bindings)


func _build_ambac(root: Node3D) -> void:
	var ambac := AmbacController.new()
	ambac.name = "Ambac"
	_add(root, root, ambac)
	ambac.skeleton = root.get_node(SKELETON)
	var joints: Array[AmbacJoint] = []
	for a in AMBAC:
		var j := AmbacJoint.new()
		j.bone_name = a[0]
		j.axis = a[1]
		j.group = a[2]
		j.inertia = a[3]
		j.min_angle_deg = a[4]
		j.max_angle_deg = a[5]
		j.priority = a[6]
		joints.append(j)
	ambac.joints = joints


## Weapons are exported where they sit on the suit, so they mount with an identity
## transform on the bone that carries them.
func _build_loadout(root: Node3D) -> void:
	var loadout := MsLoadout.new()
	loadout.name = "Loadout"
	_add(root, root, loadout)
	loadout.skeleton = root.get_node(SKELETON)
	for e in [["rx93_beam_rifle", &"hand.R", &"arm_r"], ["rx93_shield", &"forearm.L", &"arm_l"],
			["rx93_hyper_bazooka", &"backpack", &""], ["rx93_beam_saber", &"backpack", &""],
			["rx93_fin_funnels", &"backpack", &""]]:
		var eq: MsEquipment = load(EQUIPMENT + e[0] + ".tscn").instantiate()
		_add(root, loadout, eq)
		eq.mount_bone = e[1]
		eq.mount_transform = Transform3D.IDENTITY
		eq.ambac_group = e[2]


func _build_animation(root: Node3D, library: AnimationLibrary) -> void:
	var player := AnimationPlayer.new()
	player.name = "PoseAnimations"
	_add(root, root, player)
	player.root_node = ^"../Model"
	player.add_animation_library(&"", library)
	var animator := MsPoseAnimator.new()
	animator.name = "PoseAnimator"
	_add(root, root, animator)
	animator.animation_player = player
	var layers: Array[MsPoseLayer] = []
	for p in [[&"rifle_ready", POSE_RIFLE], [&"shield_guard", POSE_SHIELD]]:
		var layer := MsPoseLayer.new()
		layer.pose = p[0]
		layer.bones = PackedStringArray((p[1] as Dictionary).keys())
		layers.append(layer)
	animator.layers = layers


# --- Animations ---

func _build_animations() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle())
	lib.add_animation(&"rifle_ready", _pose(POSE_RIFLE))
	lib.add_animation(&"shield_guard", _pose(POSE_SHIELD))
	return lib


## Relaxed zero-g float: slightly bent knees and elbows, held still (no sway, so the
## suit never looks like it's drifting).
func _idle() -> Animation:
	var anim := Animation.new()
	anim.length = IDLE_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	for bone: String in IDLE_BONES:
		var track := _track(anim, bone)
		anim.rotation_track_insert_key(track, 0.0, _local(bone, _idle_rotations(bone)))
	return anim


func _idle_rotations(bone: String) -> Array:
	var side := 1.0 if bone.ends_with(".R") else -1.0
	var table := {
		"upper_arm": [[Vector3.RIGHT, 4.0], [Vector3.BACK, 6.0 * side]],
		"forearm": [[Vector3.RIGHT, 12.0]],
		"thigh": [[Vector3.RIGHT, 8.0], [Vector3.BACK, 3.0 * side]],
		"shin": [[Vector3.RIGHT, -14.0]],
		"head": [[Vector3.RIGHT, -3.0]],
	}
	return table.get(bone.get_slice(".", 0), [])


func _pose(pose: Dictionary) -> Animation:
	var anim := Animation.new()
	anim.length = 0.1
	for bone: String in pose:
		anim.rotation_track_insert_key(_track(anim, bone), 0.0, _local(bone, pose[bone]))
	return anim


func _track(anim: Animation, bone: String) -> int:
	var track := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(track, NodePath("Armature/Skeleton3D:" + bone))
	return track


## Skeleton-space rotations (applied in order) → bone-local pose rotation.
func _local(bone: String, rotations: Array) -> Quaternion:
	var idx := _skel.find_bone(bone)
	var q := Quaternion.IDENTITY
	for r in rotations:
		q = Quaternion((r[0] as Vector3).normalized(), deg_to_rad(r[1])) * q
	var g := _skel.get_bone_global_rest(idx).basis.get_rotation_quaternion()
	var rest := _skel.get_bone_rest(idx).basis.get_rotation_quaternion()
	return rest * (g.inverse() * q * g)


# --- Helpers ---

func _bone_rest_in_body(bone: String) -> Transform3D:
	return _skel_in_body * _skel.get_bone_global_rest(_skel.find_bone(bone))


func _marker(root: Node3D, node_name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	m.position = pos
	_add(root, root, m)
	return m


func _add(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root


static func _short_label(node_name: String) -> String:
	return node_name.to_upper().replace("FRONT", "F").replace("REAR", "B").replace("SIDE", "S") \
			.replace("MAIN", "MN").replace("TOP", "T").replace("CHEST", "CH").replace("FOOT", "FT")
