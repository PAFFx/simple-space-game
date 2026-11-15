extends SceneTree

## Clean force authority of the RX-93 per direction (level, limbs at rest), in G at the
## current mass, plus the clean torque.
##   godot-double --headless --path . -s Tools/Flight/capability_probe.gd

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
	var g := st.mass * 9.80665
	var dirs := {up = Vector3.UP, down = Vector3.DOWN, forward = Vector3.FORWARD, back = Vector3.BACK,
			right = Vector3.RIGHT, left = Vector3.LEFT,
			"right+up45" = Vector3(1, 1, 0).normalized(), "right+fwd45" = Vector3(1, 0, -1).normalized()}
	var line := "capability (G, mass %.1f t):" % (st.mass / 1000.0)
	for k: String in dirs:
		line += "  %s %.2f" % [k, st.force_capability(dirs[k]) / g]
	print(line)
	print("clean torque MN·m (pitch yaw roll): ", st.max_torque / 1e6)
	var total := 0.0
	for t in fc.thrusters:
		total += t.max_thrust
	print("total thrust %.0f kN = %.2f G" % [total / 1000.0, total / g])
	quit()
