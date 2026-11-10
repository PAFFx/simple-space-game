class_name MsPoseAnimator
extends Node

## Plays the suit's base animation (idle) and blends equipment poses on top,
## each limited to its own bones, via an AnimationTree built at runtime:
##
##   base ─► Blend2(layer 0) ─► Blend2(layer 1) ─► … ─► output
##
## Layer weights follow MsLoadout.get_active_poses(). AMBAC offsets are added
## afterwards by AmbacModifier, so balancing works on top of any pose.

@export var animation_player: AnimationPlayer
@export var base_animation: StringName = &"idle"
@export var layers: Array[MsPoseLayer] = []
## Node path from the AnimationPlayer's root node to the Skeleton3D (for bone filters).
@export var skeleton_path: NodePath = ^"Armature/Skeleton3D"

var _tree: AnimationTree
var _weights := PackedFloat32Array()
var _loadout: MsLoadout


func _ready() -> void:
	if animation_player == null:
		push_error("MsPoseAnimator: animation_player not assigned")
		return
	var vehicle := VehicleBase.find_vehicle(self)
	if vehicle != null:
		_loadout = vehicle.find_component(MsLoadout) as MsLoadout
	_weights.resize(layers.size())
	_build_tree()


func get_layer_weight(pose: StringName) -> float:
	for i in layers.size():
		if layers[i].pose == pose:
			return _weights[i]
	return 0.0


func _process(delta: float) -> void:
	if _tree == null:
		return
	var active := _loadout.get_active_poses() if _loadout != null else {}
	for i in layers.size():
		var target := 1.0 if active.has(layers[i].pose) else 0.0
		_weights[i] = move_toward(_weights[i], target, delta / maxf(layers[i].blend_time, 0.01))
		_tree.set("parameters/layer_%d/blend_amount" % i, smoothstep(0.0, 1.0, _weights[i]))


func _build_tree() -> void:
	var blend := AnimationNodeBlendTree.new()
	var base := AnimationNodeAnimation.new()
	base.animation = base_animation
	blend.add_node(&"base", base)
	var previous := &"base"
	for i in layers.size():
		var layer := layers[i]
		var anim := AnimationNodeAnimation.new()
		anim.animation = layer.pose
		var pose_name := StringName("pose_%d" % i)
		blend.add_node(pose_name, anim)
		var mix := AnimationNodeBlend2.new()
		mix.filter_enabled = true
		for bone in layer.bones:
			mix.set_filter_path(NodePath("%s:%s" % [skeleton_path, bone]), true)
		var mix_name := StringName("layer_%d" % i)
		blend.add_node(mix_name, mix)
		blend.connect_node(mix_name, 0, previous)
		blend.connect_node(mix_name, 1, pose_name)
		previous = mix_name
	blend.connect_node(&"output", 0, previous)

	_tree = AnimationTree.new()
	_tree.name = "PoseTree"
	_tree.tree_root = blend
	add_child(_tree)
	_tree.root_node = _tree.get_path_to(animation_player.get_node(animation_player.root_node))
	for lib in animation_player.get_animation_library_list():
		_tree.add_animation_library(lib, animation_player.get_animation_library(lib))
	_tree.active = true
	animation_player.active = false
