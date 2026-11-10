extends SceneTree

## Generates the MSP-02 vehicle scene and its animation library from the tables
## below. Run after rebuilding the GLB (see Tools/Blender):
##
##   godot-mono --headless --path . -s Tools/Godot/build_msp02_scene.gd
##
## All positions/directions are in the suit's body frame (Godot: +Y up, front −Z)
## with the skeleton at rest. The output is a normal scene: tweak it in the
## editor, or edit the tables here and regenerate.

const DIR := "res://Entities/Vehicles/MobileSuits/MSP02/"
const SCENE_PATH := DIR + "mobile_suit_msp02.tscn"
const ANIM_PATH := DIR + "Animations/msp02_animations.tres"
const MODEL := DIR + "Arts/mobile_suit_msp02.glb"
const SKELETON := ^"Model/Armature/Skeleton3D"
const COM := Vector3(0.0, 14.6, 0.2)
const SENSOR_SCENE := \
		"res://Entities/Vehicles/Cockpits/Components/PanoramicDisplay/sensor_head.tscn"
const COCKPIT_SCENE := "res://Entities/Vehicles/Cockpits/CockpitLinearSeat/cockpit_linear_seat.tscn"
const THRUSTER_SCENE := "res://Entities/Vehicles/Components/FlightControl/Thruster/thruster.tscn"

# name, bone, position, exhaust direction, thrust kN, gimbal deg, plume m, nozzle scale
# Main thrust follows the published late-UC ratio: 4 × 18,300 kgf + 2 × 12,300 kgf.
const THRUSTERS := [
	["MainUR", "backpack", Vector3(1.5, 17.15, 3.75), Vector3.INF, 179.5, 12.0, 11.0, 1.3],
	["MainUL", "backpack", Vector3(-1.5, 17.15, 3.75), Vector3.INF, 179.5, 12.0, 11.0, 1.3],
	["MainLR", "backpack", Vector3(1.5, 14.1, 2.9), Vector3.INF, 179.5, 15.0, 11.0, 1.3],
	["MainLL", "backpack", Vector3(-1.5, 14.1, 2.9), Vector3.INF, 179.5, 15.0, 11.0, 1.3],
	["LegR", "shin.R", Vector3(1.5, 3.2, 1.6), Vector3(0, -1, 0.4), 120.6, 20.0, 8.0, 1.0],
	["LegL", "shin.L", Vector3(-1.5, 3.2, 1.6), Vector3(0, -1, 0.4), 120.6, 20.0, 8.0, 1.0],
	["ShTopR", "shoulder.R", Vector3(4.1, 19.2, 0.3), Vector3(0, 1, 0), 25.0, 30.0, 3.5, 0.55],
	["ShTopL", "shoulder.L", Vector3(-4.1, 19.2, 0.3), Vector3(0, 1, 0), 25.0, 30.0, 3.5, 0.55],
	["ShFrontR", "shoulder.R", Vector3(4.1, 17.7, -1.62), Vector3(0, 0, -1), 30.0, 25.0, 3.5, 0.55],
	["ShFrontL", "shoulder.L", Vector3(-4.1, 17.7, -1.62), Vector3(0, 0, -1), 30.0, 25.0, 3.5, 0.55],
	["ShRearR", "shoulder.R", Vector3(4.1, 18.1, 1.65), Vector3(0, 0, 1), 25.0, 25.0, 3.5, 0.55],
	["ShRearL", "shoulder.L", Vector3(-4.1, 18.1, 1.65), Vector3(0, 0, 1), 25.0, 25.0, 3.5, 0.55],
	["ShSideR", "shoulder.R", Vector3(5.33, 17.8, 0.0), Vector3(1, 0, 0), 30.0, 25.0, 3.5, 0.55],
	["ShSideL", "shoulder.L", Vector3(-5.33, 17.8, 0.0), Vector3(-1, 0, 0), 30.0, 25.0, 3.5, 0.55],
	["ChestR", "chest", Vector3(2.1, 16.48, -2.66), Vector3(0, 0, -1), 35.0, 20.0, 4.0, 0.6],
	["ChestL", "chest", Vector3(-2.1, 16.48, -2.66), Vector3(0, 0, -1), 35.0, 20.0, 4.0, 0.6],
	["SkFrontR", "skirt_front.R", Vector3(1.25, 11.3, -1.75), Vector3(0, -0.4, -1), 30.0, 30.0,
			3.5, 0.55],
	["SkFrontL", "skirt_front.L", Vector3(-1.25, 11.3, -1.75), Vector3(0, -0.4, -1), 30.0, 30.0,
			3.5, 0.55],
	["SkSideR", "skirt_side.R", Vector3(2.8, 11.7, 0.0), Vector3(1, -0.3, 0), 30.0, 30.0, 3.5, 0.55],
	["SkSideL", "skirt_side.L", Vector3(-2.8, 11.7, 0.0), Vector3(-1, -0.3, 0), 30.0, 30.0, 3.5, 0.55],
	["SkRearR", "skirt_rear.R", Vector3(1.0, 11.6, 1.8), Vector3(0, -0.5, 1), 30.0, 30.0, 3.5, 0.55],
	["SkRearL", "skirt_rear.L", Vector3(-1.0, 11.6, 1.8), Vector3(0, -0.5, 1), 30.0, 30.0, 3.5, 0.55],
	["FootR", "foot.R", Vector3(1.5, 0.0, -0.4), Vector3(0, -1, 0), 30.0, 25.0, 3.5, 0.6],
	["FootL", "foot.L", Vector3(-1.5, 0.0, -0.4), Vector3(0, -1, 0), 30.0, 25.0, 3.5, 0.6],
	["BpTopR", "backpack", Vector3(1.5, 17.85, 2.9), Vector3(0, 1, 0), 20.0, 30.0, 3.0, 0.5],
	["BpTopL", "backpack", Vector3(-1.5, 17.85, 2.9), Vector3(0, 1, 0), 20.0, 30.0, 3.0, 0.5],
]

# name, center, size
const COLLIDERS := [
	["Torso", Vector3(0, 16.2, -0.4), Vector3(5.8, 4.3, 4.4)],
	["Backpack", Vector3(0, 16.0, 2.9), Vector3(4.0, 3.4, 1.8)],
	["Head", Vector3(0, 19.9, -0.45), Vector3(1.4, 1.8, 1.7)],
	["Pelvis", Vector3(0, 12.6, -0.1), Vector3(3.2, 3.0, 2.8)],
	["ShoulderR", Vector3(4.1, 18.0, 0), Vector3(2.4, 2.4, 3.0)],
	["ShoulderL", Vector3(-4.1, 18.0, 0), Vector3(2.4, 2.4, 3.0)],
	["ArmR", Vector3(3.9, 12.7, -0.05), Vector3(1.5, 8.8, 1.6)],
	["ArmL", Vector3(-3.9, 12.7, -0.05), Vector3(1.5, 8.8, 1.6)],
	["LegR", Vector3(1.5, 6.0, 0), Vector3(2.0, 12.0, 2.2)],
	["LegL", Vector3(-1.5, 6.0, 0), Vector3(2.0, 12.0, 2.2)],
	["FootR", Vector3(1.5, 0.55, -0.4), Vector3(1.8, 1.1, 3.6)],
	["FootL", Vector3(-1.5, 0.55, -0.4), Vector3(1.8, 1.1, 3.6)],
]

# bone, axis (skeleton space), group, inertia kg·m², max angle, priority
const AMBAC := [
	["upper_arm.R", Vector3.RIGHT, &"arm_r", 6.0e4, 35.0, 0.6],
	["upper_arm.R", Vector3.BACK, &"arm_r", 6.0e4, 25.0, 0.6],
	["upper_arm.L", Vector3.RIGHT, &"arm_l", 6.0e4, 35.0, 0.6],
	["upper_arm.L", Vector3.BACK, &"arm_l", 6.0e4, 25.0, 0.6],
	["thigh.R", Vector3.RIGHT, &"leg_r", 8.0e4, 30.0, 1.0],
	["thigh.R", Vector3.BACK, &"leg_r", 8.0e4, 15.0, 1.0],
	["thigh.L", Vector3.RIGHT, &"leg_l", 8.0e4, 30.0, 1.0],
	["thigh.L", Vector3.BACK, &"leg_l", 8.0e4, 15.0, 1.0],
	["spine", Vector3.UP, &"torso", 1.2e5, 12.0, 0.8],
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
	print("[build_msp02_scene] wrote %s and %s" % [SCENE_PATH, ANIM_PATH])
	model.free()
	root.free()
	quit()


# --- Scene ---

func _build_scene(library: AnimationLibrary) -> RigidBody3D:
	var root := RigidBody3D.new()
	root.name = "MobileSuitMSP02"
	root.set_script(load("res://Entities/Vehicles/MobileSuits/Common/mobile_suit_body.gd"))
	root.gravity_scale = 0.0
	root.can_sleep = false
	root.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	root.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	root.center_of_mass = COM
	root.mass = 46400.0

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

	var sensor_mount := _marker(root, "SensorHeadMount", Vector3(0, 19.9, -1.45))
	_add(root, sensor_mount, load(SENSOR_SCENE).instantiate())
	var cockpit_mount := _marker(root, "CockpitMount", Vector3(0, 16.1, -0.5))
	_add(root, cockpit_mount, load(COCKPIT_SCENE).instantiate())

	_build_thrusters(root)
	_build_flight_computer(root)
	_build_hatch(root)
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
		var exhaust: Vector3 = t[3]
		if exhaust == Vector3.INF:
			# Mains: thrust line through the centre of mass, so they push without pitching.
			exhaust = pos - COM
		exhaust = exhaust.normalized()
		var up := Vector3.UP if absf(exhaust.dot(Vector3.UP)) < 0.95 else Vector3.BACK
		# Thruster −Z = thrust direction = opposite of the exhaust.
		var body_xf := Transform3D(Basis.looking_at(-exhaust, up), pos)
		var node: Node3D = thruster_scene.instantiate()
		node.name = t[0]
		_add(root, attachments[bone], node)
		node.transform = _bone_rest_in_body(bone).affine_inverse() * body_xf
		node.set("max_thrust", float(t[4]) * 1000.0)
		node.set("gimbal_limit_deg", t[5])
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
	alloc.iterations = 30
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


func _build_hatch(root: Node3D) -> void:
	var hatch := Node.new()
	hatch.name = "CockpitHatch"
	hatch.set_script(load("res://Entities/Vehicles/Components/Hatch/cockpit_hatch.gd"))
	_add(root, root, hatch)
	var upper := HatchPanel.new()
	upper.bone_name = &"hatch_upper"
	upper.hinge_axis = Vector3.RIGHT
	upper.open_angle_deg = 110.0
	upper.window = Vector2(0.3, 0.85)
	var lower := HatchPanel.new()
	lower.bone_name = &"hatch_lower"
	lower.hinge_axis = Vector3.RIGHT
	lower.open_angle_deg = -95.0
	lower.window = Vector2(0.4, 1.0)
	var panels: Array[HatchPanel] = [upper, lower]
	hatch.set("panels", panels)
	hatch.set("skeleton", root.get_node(SKELETON))


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
		j.max_angle_deg = a[4]
		j.priority = a[5]
		joints.append(j)
	ambac.joints = joints


func _build_loadout(root: Node3D) -> void:
	var loadout := MsLoadout.new()
	loadout.name = "Loadout"
	_add(root, root, loadout)
	loadout.skeleton = root.get_node(SKELETON)
	var rifle: MsEquipment = load("res://Entities/Equipment/BeamRifle/beam_rifle.tscn").instantiate()
	_add(root, loadout, rifle)
	rifle.mount_bone = &"hand.R"
	rifle.mount_transform = Transform3D(
			Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(3.9, 9.55, -0.35))
	rifle.ambac_group = &"arm_r"
	var shield: MsEquipment = load("res://Entities/Equipment/Shield/shield.tscn").instantiate()
	_add(root, loadout, shield)
	shield.mount_bone = &"forearm.L"
	shield.mount_transform = Transform3D(
			Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(-4.85, 11.6, -0.05))
	shield.ambac_group = &"arm_l"


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


## Relaxed zero-g float: slightly bent knees and elbows, slow breathing sway, head scanning.
func _idle() -> Animation:
	var anim := Animation.new()
	anim.length = IDLE_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	var keys := 9
	for bone: String in IDLE_BONES:
		var track := _track(anim, bone)
		for k in keys:
			var t := IDLE_LENGTH * k / (keys - 1)
			var phase := TAU * t / IDLE_LENGTH
			anim.rotation_track_insert_key(track, t, _local(bone, _idle_rotations(bone, phase)))
	return anim


func _idle_rotations(bone: String, phase: float) -> Array:
	var side := 1.0 if bone.ends_with(".R") else -1.0
	var table := {
		"upper_arm": [[Vector3.RIGHT, 4.0 + 2.0 * sin(phase)], [Vector3.BACK, 6.0 * side]],
		"forearm": [[Vector3.RIGHT, 12.0 + 2.0 * sin(phase + 0.6)]],
		"thigh": [[Vector3.RIGHT, 8.0 + 1.5 * sin(phase + side)], [Vector3.BACK, 3.0 * side]],
		"shin": [[Vector3.RIGHT, -14.0 - 2.0 * sin(phase + side)]],
		"spine": [[Vector3.UP, 1.5 * sin(phase)]],
		"head": [[Vector3.UP, 10.0 * sin(phase)], [Vector3.RIGHT, -3.0]],
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
