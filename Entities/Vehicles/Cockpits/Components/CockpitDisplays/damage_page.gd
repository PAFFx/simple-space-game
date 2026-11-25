class_name DamagePage
extends MfdPage

## Damage control (DamageModel), as the suit's own diagnostics report it: the suit seen from
## the front, each part filled by how much of its cross-section is left (green, amber, red;
## a part gone is a dashed outline), its thrusters as dots (red dead, amber derated or nozzle
## stuck) and its cameras as squares (green live, red out).
## On the right: reactor, pilot, I-field charges, thrusters and cameras out, the last events.
## CockpitDisplays shows it on the left display for a while after each new damage, and on P.

var damage: DamageModel
var _events: PackedStringArray = []
var _clock := 0.0


func setup(p_vehicle: VehicleBase) -> void:
	super(p_vehicle)
	_bind.call_deferred()


## The suit makes its damage model in its own _ready, after its cockpit's: look it up then.
func _bind() -> void:
	damage = vehicle.find_component(DamageModel) as DamageModel if vehicle != null else null
	if damage != null:
		damage.component_destroyed.connect(func(kind: StringName, what: StringName) -> void:
			_note("%s %s" % [String(kind).to_upper(), String(what).to_upper()]))
		damage.part_severed.connect(func(part: StringName) -> void: _note("%s LOST" % String(part).to_upper()))
		damage.cockpit_holed.connect(func(_o: Vector3, _d: Vector3, _r: float) -> void: _note("COCKPIT HOLED"))
		damage.repaired.connect(func() -> void: _events.clear())


func _process(delta: float) -> void:
	_clock += delta


func _note(text: String) -> void:
	_events.append(text)
	if _events.size() > 7:
		_events.remove_at(0)


func draw_page() -> void:
	label(Vector2(20, 34), "DMG", INFO, 22)
	if damage == null or not damage.is_built():
		label(Vector2(20, 80), "NO DATA", DIM, 18)
		return
	var body := vehicle as Node as Node3D
	var inv := body.global_transform.affine_inverse()
	var skel := (vehicle.find_component(LimbReaction) as LimbReaction).skeleton
	# Front view: body x → page x, body y → page y (the suit 22 m tall in 400 px).
	var area := Rect2(20, 60, 400, 440)
	var scale := 18.0
	var origin := Vector2(area.position.x + area.size.x * 0.5, area.end.y - 8.0)
	var to_page := func(v: Vector3) -> Vector2:
		return origin + Vector2(-v.x, -v.y) * scale
	window(area, "SUIT")
	# Back to front, so the arms and legs draw over the torso.
	var order := damage.parts.duplicate()
	order.sort_custom(func(a: DamageModel.Part, b: DamageModel.Part) -> bool:
		return _depth(a, skel, inv) > _depth(b, skel, inv))
	for p: DamageModel.Part in order:
		if p.equipment != null or p.mesh == null:
			continue
		var frame := skel.global_transform * skel.get_bone_global_pose(p.bone)
		var c: Vector2 = to_page.call(inv * (frame * p.aabb.get_center()))
		var half := Vector2(p.aabb.size.x, p.aabb.size.y) * scale * 0.42
		var r := Rect2(c - half, half * 2.0)
		if p.severed:
			_dashed(r, Color(WARNING, 0.7))
			continue
		var left := clampf(p.left, 0.0, 1.0)
		var col := GOOD if left > 0.8 else (CAUTION if left > BREAK_SHOWN else WARNING)
		draw_rect(r, Color(col, 0.22 + 0.25 * (1.0 - left)), true)
		draw_rect(r, Color(col, 0.85), false, 1.5)
	for comp: DamageModel.Component in damage.components:
		if comp.kind == DamageModel.Kind.THRUSTER:
			var t := comp.ref as Thruster
			var at: Vector2 = to_page.call(inv * t.global_position)
			var col := GOOD
			if not comp.alive:
				if t.enabled:
					col = CAUTION
				else:
					col = WARNING
			draw_circle(at, 3.5, col)
		elif comp.kind == DamageModel.Kind.EYES or comp.kind == DamageModel.Kind.BODY_CAMERA:
			var at: Vector2 = to_page.call(inv * damage.component_position(comp))
			var r := Rect2(at - Vector2(4, 4), Vector2(8, 8))
			draw_rect(r, GOOD if comp.alive else WARNING, comp.alive)
	_status(Rect2(440, 60, 244, 440))


const BREAK_SHOWN := 0.45


static func _depth(p: DamageModel.Part, skel: Skeleton3D, inv: Transform3D) -> float:
	if p.equipment != null or p.mesh == null:
		return 0.0
	return (inv * (skel.global_transform * skel.get_bone_global_pose(p.bone) * p.aabb.get_center())).z


func _dashed(r: Rect2, col: Color) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := maxi(int(a.distance_to(b) / 8.0), 1)
		for i in range(0, n, 2):
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, 1.5)


func _status(r: Rect2) -> void:
	window(r, "STATUS")
	var y := r.position.y + 34.0
	var x := r.position.x + 14.0
	var line := func(name: String, value: String, col: Color) -> void:
		label(Vector2(x, y), name, DIM, 15)
		label(Vector2(r.end.x - 14.0, y), value, col, 15, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 24.0
	line.call("REACTOR", "BREACH" if damage.reactor_gone else "OK", WARNING if damage.reactor_gone else GOOD)
	line.call("PILOT", "KIA" if damage.pilot_dead else "OK", WARNING if damage.pilot_dead else GOOD)
	var shields := vehicle.find_children("*", "MsShield", true, false)
	if not shields.is_empty():
		var s := shields[0] as MsShield
		line.call("I-FIELD", "%d / %d" % [s.charges, s.field_charges] if s.equipped else "LOST",
				GOOD if s.charges > 1 and s.equipped else (CAUTION if s.charges == 1 and s.equipped else WARNING))
	var thr := damage.count_dead(DamageModel.Kind.THRUSTER)
	line.call("THRUSTERS OUT", str(thr), GOOD if thr == 0 else (CAUTION if thr < 6 else WARNING))
	var cams := damage.count_dead(DamageModel.Kind.BODY_CAMERA) + damage.count_dead(DamageModel.Kind.EYES)
	line.call("CAMERAS OUT", str(cams), GOOD if cams == 0 else CAUTION)
	line.call("MAIN CAMERA", "OUT" if damage.count_dead(DamageModel.Kind.EYES) > 0 else "OK",
			CAUTION if damage.count_dead(DamageModel.Kind.EYES) > 0 else GOOD)
	y += 10.0
	label(Vector2(x, y), "EVENTS", INFO, 14)
	y += 22.0
	for i in range(_events.size() - 1, -1, -1):
		var text := _events[i]
		if text.length() > 24:
			text = text.substr(0, 24)
		label(Vector2(x, y), text, TEXT if i == _events.size() - 1 else DIM, 13)
		y += 20.0
