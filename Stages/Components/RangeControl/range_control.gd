class_name RangeControl
extends CanvasLayer

## Test range control (F4): spawn and clear practice targets, rearm the suit and count
## the shots it took (rearm resets the count). While its panel is open the number keys
## pick an entry instead of a weapon.
##
##   1 static · 2 drifting · 3 jinking · 4 hard jinking · 5 evasive (dodges your shots)
##   6 ace (hard jinking and dodging) · 7 turret · 8 hunter turret · 9 clear all · 0 rearm
##   - / + nearer / farther
## Rearm also repairs the suit (DamageModel); the panel lists each part. When the pilot is
## killed (a beam through the cockpit, a reactor breach) a GAME OVER screen asks for a rearm.

const TOGGLE := &"debug_toggle_range_control"
## Panels in this group close each other: they share the number keys.
const PANEL_GROUP := &"debug_key_panels"
const RANGES := [300.0, 600.0, 1000.0, 1500.0, 2500.0, 4000.0, 6000.0]
## [menu name, HUD label, behaviour, jink G, jink interval, dodge G (0 = none), dodge reaction s,
##  sensor-aimed (turrets)]
const PRESETS := [
	["STATIC", "TGT", TargetDrone.Behaviour.STATIC, 0.0, Vector2(0.8, 2.2), 0.0, 0.0, false],
	["DRIFTING", "DRIFT", TargetDrone.Behaviour.DRIFT, 0.0, Vector2(0.8, 2.2), 0.0, 0.0, false],
	["JINKING (3 G)", "JINK", TargetDrone.Behaviour.JINK, 3.0, Vector2(0.8, 2.2), 0.0, 0.0, false],
	["HARD JINKING (8 G, quick)", "HJINK", TargetDrone.Behaviour.JINK, 8.0, Vector2(0.3, 0.9), 0.0, 0.0, false],
	["EVASIVE (dodges on your spool)", "EVADE", TargetDrone.Behaviour.JINK, 3.0, Vector2(0.8, 2.2), 7.0, 0.25, false],
	["ACE (hard jinks + dodges)", "ACE", TargetDrone.Behaviour.JINK, 8.0, Vector2(0.3, 0.9), 9.0, 0.15, false],
	["TURRET (shoots back)", "TURRET", TargetDrone.Behaviour.TURRET, 3.0, Vector2(0.8, 2.2), 0.0, 0.0, false],
	["HUNTER (sensor-aimed, dodges)", "HUNTER", TargetDrone.Behaviour.TURRET, 8.0, Vector2(0.5, 1.4), 7.0, 0.25, true],
]

## Vehicle the targets are placed in front of. Default: the first one in the scene.
@export var vehicle: VehicleBase
## Spread of the spawn point about the suit's nose, deg.
@export var spread_deg: float = 12.0

var drones: Array[TargetDrone] = []
var _range_index := 2
var _count := 0
## Enemy shots that reached the suit since the last rearm: on the body, and on the shield.
var hits_taken := 0
var hits_blocked := 0
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 120
	if not InputMap.has_action(TOGGLE):
		InputMap.add_action(TOGGLE)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F4
		InputMap.action_add_event(TOGGLE, ev)
	add_to_group(PANEL_GROUP)
	_build_ui()
	_build_game_over()
	_panel.visible = false
	_hook_fire_control.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE):
		_panel.visible = not _panel.visible
		if _panel.visible:
			get_tree().call_group(PANEL_GROUP, &"close_panel", self)
		_refresh()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not _panel.visible:
		return
	var code := key.physical_keycode
	if code >= KEY_1 and code <= KEY_9:
		_run(code - KEY_1)
	elif code == KEY_0:
		_run(PRESETS.size() + 1)
	elif code == KEY_MINUS or code == KEY_KP_SUBTRACT:
		_range_index = maxi(_range_index - 1, 0)
	elif code == KEY_EQUAL or code == KEY_KP_ADD:
		_range_index = mini(_range_index + 1, RANGES.size() - 1)
	else:
		return
	_refresh()
	get_viewport().set_input_as_handled()


func get_range() -> float:
	return RANGES[_range_index]


func close_panel(opener: Node) -> void:
	if opener != self:
		_panel.visible = false


## Spawns a target `distance` ahead of the suit, keeping station with it.
func spawn(behaviour: TargetDrone.Behaviour, distance: float) -> TargetDrone:
	var suit := _vehicle()
	if suit == null:
		return null
	var basis := suit.global_basis.orthonormalized()
	var off := Vector2(randf_range(-spread_deg, spread_deg), randf_range(-spread_deg * 0.5, spread_deg * 0.5))
	var drone := TargetDrone.new()
	_count += 1
	drone.behaviour = behaviour
	drone.label = "%s %d" % [["TGT", "DRIFT", "JINK", "TURRET"][behaviour], _count]
	drone.quarry = suit
	var body := suit as Node as RigidBody3D
	drone.velocity = body.linear_velocity if body != null else Vector3.ZERO
	if behaviour == TargetDrone.Behaviour.DRIFT:
		drone.velocity += basis * Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3)).normalized() \
				* randf_range(40.0, 120.0)
	get_parent().add_child(drone)
	drone.global_position = suit.global_position + Vector3(0, 14, 0) \
			+ basis * SpatialMath.angles_to_direction(off) * distance
	drone.reset_physics_interpolation()
	drone.destroyed.connect(func(d: TargetDrone) -> void: drones.erase(d))
	drones.append(drone)
	return drone


func clear() -> void:
	for drone in drones:
		if is_instance_valid(drone):
			drone.queue_free()
	drones.clear()


func rearm() -> void:
	var suit := _vehicle()
	var fcs := suit.find_component(FireControl) as FireControl if suit != null else null
	if fcs != null:
		fcs.rearm()
	var damage := suit.find_component(DamageModel) as DamageModel if suit != null else null
	if damage != null:
		damage.repair()
	hits_taken = 0
	hits_blocked = 0


func _hook_fire_control() -> void:
	var suit := _vehicle()
	var fcs := suit.find_component(FireControl) as FireControl if suit != null else null
	if fcs != null:
		fcs.hit_taken.connect(_on_hit_taken)


func _on_hit_taken(blocked: bool) -> void:
	if blocked:
		hits_blocked += 1
	else:
		hits_taken += 1
	if _panel.visible:
		_refresh()


## Spawns one of PRESETS.
func spawn_preset(index: int, distance: float) -> TargetDrone:
	var p: Array = PRESETS[index]
	var drone := spawn(p[2], distance)
	if drone == null:
		return null
	drone.label = "%s %d" % [p[1], _count]
	drone.set_meta(&"hud_label", drone.label)
	if p[3] > 0.0:
		drone.jink_accel_g = p[3]
	drone.jink_interval = p[4]
	drone.leash = maxf(drone.leash, distance * 0.4)
	if p[5] > 0.0:
		var suit := _vehicle()
		drone.threat = suit.find_component(FireControl) as FireControl if suit != null else null
		drone.dodge_accel_g = p[5]
		drone.dodge_reaction = p[6]
	if p[7]:
		drone.use_track = true
		drone.fire_interval = Vector2(1.0, 2.0)
		# A quicker suit: turns and swings its arm faster, a bigger E-cap.
		drone.turn_rate_deg = 30.0
		drone.turn_accel_deg = 90.0
		drone.arm_slew_deg = 80.0
		drone.arm_cone_deg = 55.0
		drone.magazine = 8
	return drone


func _run(entry: int) -> void:
	if entry < PRESETS.size():
		spawn_preset(entry, get_range())
	elif entry == PRESETS.size():
		clear()
	else:
		rearm()


func _vehicle() -> VehicleBase:
	if vehicle == null:
		for node in get_tree().current_scene.find_children("*", "", true, false) if get_tree().current_scene else []:
			if node is VehicleBase:
				vehicle = node
				break
	return vehicle


var _game_over: Label


func _build_game_over() -> void:
	_game_over = Label.new()
	_game_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game_over.add_theme_font_size_override(&"font_size", 40)
	_game_over.add_theme_color_override(&"font_color", Color(1.0, 0.3, 0.25))
	_game_over.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_game_over.add_theme_constant_override(&"outline_size", 8)
	_game_over.visible = false
	add_child(_game_over)


var _damage: DamageModel
var _damage_of: Node


func _process(_delta: float) -> void:
	var suit := _vehicle()
	if suit != _damage_of:
		# Looked up once per suit: find_component walks its whole tree.
		_damage_of = suit
		_damage = suit.find_component(DamageModel) as DamageModel if suit != null else null
	var damage := _damage
	var over := damage != null and damage.pilot_dead
	if over != _game_over.visible:
		_game_over.visible = over
		_game_over.text = "GAME OVER\n%s\n\nF4 → 0 to rearm" % ("REACTOR BREACH" if damage.reactor_gone else "PILOT KILLED IN ACTION")


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(8, 120)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])
	_label.add_theme_font_override(&"font", font)
	_label.add_theme_font_size_override(&"font_size", 13)
	_panel.add_child(_label)


func _refresh() -> void:
	var lines := PackedStringArray(["RANGE CONTROL  (F4 closes)", ""])
	for i in PRESETS.size():
		lines.append("%d  %s" % [i + 1, PRESETS[i][0]])
	lines.append("%d  CLEAR ALL" % (PRESETS.size() + 1))
	lines.append("0  REARM")
	lines.append("")
	lines.append("- / +  spawn range  %s" % ("%.1f km" % (get_range() / 1000.0) if get_range() >= 1000.0 else "%d m" % get_range()))
	var alive := 0
	for drone in drones:
		if is_instance_valid(drone):
			alive += 1
	lines.append("targets  %d" % alive)
	lines.append("hits taken  %d   blocked  %d" % [hits_taken, hits_blocked])
	var suit := _vehicle()
	var damage := suit.find_component(DamageModel) as DamageModel if suit != null else null
	if damage != null:
		var parts := PackedStringArray()
		for state in damage.get_part_states():
			if state[1] < 0.999:
				parts.append("%s %s" % [String(state[0]).to_upper(), "GONE" if state[1] <= 0.0 else "%3d%%" % roundi(state[1] * 100.0)])
		var shield := suit.find_children("*", "MsShield", true, false)
		lines.append("")
		lines.append("DAMAGE%s" % ("  ** PILOT KIA: 0 rearms **" if damage.pilot_dead else ""))
		if parts.is_empty():
			lines.append("  intact")
		for i in range(0, parts.size(), 3):
			lines.append("  " + "   ".join(parts.slice(i, i + 3)))
		lines.append("  thrusters out %d   cameras out %d" % [damage.count_dead(DamageModel.Kind.THRUSTER),
				damage.count_dead(DamageModel.Kind.BODY_CAMERA) + damage.count_dead(DamageModel.Kind.EYES)])
		if not shield.is_empty():
			lines.append("  I-field charges %d" % (shield[0] as MsShield).charges)
		if damage.last_event != "":
			lines.append("  last: %s" % damage.last_event)
	_label.text = "\n".join(lines)
	_panel.reset_size()
