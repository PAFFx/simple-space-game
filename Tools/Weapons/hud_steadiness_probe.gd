extends SceneTree

## Headless, frame by frame: how steady the HUD's contact marks are. For each contact the
## sensors track: the drawn triangle size (how often and how much it changes) and the
## drawn direction's frame-to-frame wobble (second difference, so steady motion doesn't
## count), from 3 to 6 s, once the tracks (and a far contact added at the start) settle.
##
##   godot-double --headless --path . --fixed-fps 60 -s Tools/Weapons/hud_steadiness_probe.gd

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"

var _suit: RigidBody3D
var _fcs: FireControl
var _contacts: ContactsWidget


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	for node in stage.find_children("*", "", true, false):
		if "capture_on_ready" in node:
			node.set("capture_on_ready", false)
	root.add_child(stage)
	current_scene = stage
	for i in 10:
		await physics_frame
	for node in stage.find_children("*", "", true, false):
		if node is VehicleBase:
			_suit = node as Node as RigidBody3D
		if node is ContactsWidget:
			_contacts = node
	_fcs = (_suit as Node as VehicleBase).find_component(FireControl) as FireControl
	var drone := TargetDrone.new()
	drone.quarry = _suit
	current_scene.add_child(drone)
	drone.global_position = _fcs.get_view_origin() + _suit.global_basis * SpatialMath.angles_to_direction(Vector2(10, 5)) * 2200.0
	var stats := {}   # name → [frames, size changes, max size step %, sum wobble², max wobble, last dir, prev dir, first half, last half]
	for frame in 360:
		await process_frame
		if frame < 180:
			continue   # settling: the numbers are for a settled track
		for node in get_nodes_in_group(&"hud_contacts"):
			var c := node as Node3D
			if c == _suit or not _fcs.can_see(c):
				continue
			var st: Array = _contacts._half_shown.get(c.get_instance_id(), [])
			if st.is_empty():
				continue
			var half: float = st[0]
			var dir := (_fcs.get_contact_position(c) - _fcs.get_view_origin()).normalized()
			var key := String(c.name)
			if not stats.has(key):
				stats[key] = [0, 0, 0.0, 0.0, 0.0, dir, dir, half, half]
			var s: Array = stats[key]
			var step := absf(half - s[8]) / maxf(s[8], 1e-3)
			if step > 1e-4:
				s[1] += 1
			s[2] = maxf(s[2], step * 100.0)
			var wobble := rad_to_deg((dir - 2.0 * (s[5] as Vector3) + (s[6] as Vector3)).length())
			if s[0] >= 2:
				s[3] += wobble * wobble
				s[4] = maxf(s[4], wobble)
			s[6] = s[5]
			s[5] = dir
			s[8] = half
			s[0] += 1
	for node in get_nodes_in_group(&"hud_contacts"):
		var c := node as Node3D
		if c == _suit or not _fcs.can_see(c):
			continue
		var o := _fcs.get_view_origin()
		print("%-18s range %.0f m (true %.0f), 2σ doubt %.0f%%, angle 2σ %.3f°" % [String(c.name),
			(_fcs.get_contact_position_now(c) - o).length(), (c.global_position - o).length(),
			_fcs.get_contact_range_error_share(c) * 100.0, _fcs.get_contact_angular_error_deg(c)])
	for key: String in stats:
		var s: Array = stats[key]
		print("%-18s size %.2f° → %.2f°, changing %3d of %d frames (biggest step %.1f%%), wobble rms %.4f° max %.4f°" % [
			key, s[7], s[8], s[1], s[0], s[2], sqrt(s[3] / maxf(s[0] - 2, 1)), s[4]])
	quit()
