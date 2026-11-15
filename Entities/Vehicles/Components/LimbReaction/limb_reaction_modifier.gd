class_name LimbReactionModifier
extends SkeletonModifier3D

## Hands the final pose to LimbReaction. Modifier results only exist inside the modifier
## pass, so this must run after every other modifier; it moves itself to the end of the
## skeleton's children whenever their order changes. Changes nothing itself.

var reaction: LimbReaction


func _enter_tree() -> void:
	var skel := get_parent()
	if skel != null and not skel.child_order_changed.is_connected(_keep_last):
		skel.child_order_changed.connect(_keep_last)


func _keep_last() -> void:
	var skel := get_parent()
	if skel != null and get_index() != skel.get_child_count() - 1:
		skel.move_child.call_deferred(self, -1)


func _process_modification_with_delta(delta: float) -> void:
	if reaction != null:
		reaction.sample(get_skeleton(), delta)
