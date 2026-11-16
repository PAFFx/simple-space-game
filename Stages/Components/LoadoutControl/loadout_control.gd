class_name LoadoutControl
extends CanvasLayer

## Test range loadout panel (F5): puts the suit's equipment on or takes it off. While its
## panel is open the number keys toggle an item instead of picking a weapon.

const TOGGLE := &"debug_toggle_loadout_control"

## Vehicle whose loadout it edits. Default: the first one in the scene.
@export var vehicle: VehicleBase

var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 120
	add_to_group(RangeControl.PANEL_GROUP)
	if not InputMap.has_action(TOGGLE):
		InputMap.add_action(TOGGLE)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F5
		InputMap.action_add_event(TOGGLE, ev)
	_build_ui()
	_panel.visible = false


func close_panel(opener: Node) -> void:
	if opener != self:
		_panel.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE):
		_panel.visible = not _panel.visible
		if _panel.visible:
			get_tree().call_group(RangeControl.PANEL_GROUP, &"close_panel", self)
		_refresh()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not _panel.visible:
		return
	var code := key.physical_keycode
	var items := _items()
	if code >= KEY_1 and code <= KEY_9 and code - KEY_1 < items.size():
		var eq := items[code - KEY_1]
		_loadout().set_equipped(eq, not eq.equipped)
	elif code == KEY_0:
		for eq in items:
			_loadout().set_equipped(eq, true)
	else:
		return
	_refresh()
	get_viewport().set_input_as_handled()


func _items() -> Array[MsEquipment]:
	var loadout := _loadout()
	return loadout.equipment if loadout != null else [] as Array[MsEquipment]


func _loadout() -> MsLoadout:
	var suit := _vehicle()
	return suit.find_component(MsLoadout) as MsLoadout if suit != null else null


func _vehicle() -> VehicleBase:
	if vehicle == null:
		for node in get_tree().current_scene.find_children("*", "", true, false) if get_tree().current_scene else []:
			if node is VehicleBase:
				vehicle = node
				break
	return vehicle


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
	var lines := PackedStringArray(["LOADOUT  (F5 closes)", ""])
	var items := _items()
	for i in mini(items.size(), 9):
		var eq := items[i]
		lines.append("%d  [%s] %-16s %5.1f t" % [i + 1, "x" if eq.equipped else " ",
				eq.get_display_name().to_upper(), eq.mass / 1000.0])
	lines.append("0  EQUIP ALL")
	var suit := _vehicle()
	var fc := suit.find_component(FlightComputer) as FlightComputer if suit != null else null
	if fc != null:
		lines.append("")
		lines.append("suit mass  %.1f t" % (fc.get_total_mass() / 1000.0))
	_label.text = "\n".join(lines)
	_panel.reset_size()
