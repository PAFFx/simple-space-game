extends SceneTree

## Pure-torque authority of the RX-93: what the allocator delivers and how much force it spills.
##   godot-double --headless --path . -s Tools/Flight/torque_probe.gd

var fc: FlightComputer
var frames := 0

func _initialize() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var suit: Node = load("res://Entities/Vehicles/MobileSuits/RX93/mobile_suit_rx93.tscn").instantiate()
	root.add_child(suit)
	fc = suit.get_node("FlightComputer")
	physics_frame.connect(_tick)

func _tick() -> void:
	frames += 1
	if frames < 5: return
	var st := fc.state
	var ideal := st.max_torque_ideal
	var names := ["pitch", "yaw", "roll"]
	print("clean/ideal torque ", st.max_torque / st.max_torque_ideal,  "  ambac ", st.ambac_torque / 1000.0, "  mass ", st.mass)
	print("inertia diag ", Vector3(st.inertia_local.x.x, st.inertia_local.y.y, st.inertia_local.z.z))
	for k in 3:
		for prio in [0.35, 2.0, 8.0]:
			var line := "%-5s prio %.2f:" % [names[k], prio]
			for frac in [0.1, 0.25, 0.5, 0.85]:
				var probe := fc.allocator.duplicate() as ConeProjectedAllocator
				probe.iterations = 200
				probe.warm_start_decay = 1.0
				var axis := Vector3.ZERO
				axis[k] = 1.0
				var w := Wrench.new(Vector3.ZERO, axis * ideal[k] * frac)
				w.torque_priority = prio
				var u := PackedVector3Array()
				for i in 4: u = probe.allocate(st, w)
				var r := ConeProjectedAllocator._wrench_of(st, u)
				var alpha: float = r[1][k] / st.inertia_local[k][k]
				line += "  ask %.2f → got %.2f (%.0f°/s²) spill %.2fg off-axis %.0f%%" % [
					frac, r[1][k] / ideal[k], rad_to_deg(alpha),
					r[0].length() / st.mass / 9.80665,
					100.0 * (r[1] - axis * r[1][k]).length() / maxf(absf(r[1][k]), 1.0)]
			print(line)
	quit()
