class_name CockpitClickMode
extends Node

## DCS-style cockpit interaction. Middle mouse (PilotInputActions.CLICK_MODE) frees the
## cursor (the view stops following the mouse); the nearest CockpitClickable under the
## cursor ray lights up, left click throws it one way and right click the other. Middle
## mouse again captures the mouse for looking around.

var active := false

var _hovered: CockpitClickable
var _tip: Label


func _ready() -> void:
	PilotInputActions.ensure_defaults()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_tip = Label.new()
	_tip.add_theme_font_size_override("font_size", 15)
	_tip.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tip.add_theme_constant_override("outline_size", 4)
	_tip.visible = false
	layer.add_child(_tip)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(PilotInputActions.CLICK_MODE):
		_set_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active or not event is InputEventMouseButton or not event.pressed:
		return
	var button := (event as InputEventMouseButton).button_index
	if _hovered != null and (button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT):
		_hovered.click(-1 if button == MOUSE_BUTTON_LEFT else 1)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not active:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_set_active(false)  # something else captured the mouse
		return
	var pick := _pick(get_viewport().get_mouse_position())
	if pick != _hovered:
		if _hovered != null:
			_hovered.set_hover(false)
		_hovered = pick
		if _hovered != null:
			_hovered.set_hover(true)
	_tip.visible = _hovered != null and _hovered.tooltip != ""
	if _tip.visible:
		_tip.text = _hovered.tooltip
		_tip.position = get_viewport().get_mouse_position() + Vector2(18, 14)


func _set_active(value: bool) -> void:
	active = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if active else Input.MOUSE_MODE_CAPTURED
	if not active:
		if _hovered != null:
			_hovered.set_hover(false)
		_hovered = null
		_tip.visible = false


## Nearest clickable along the cursor ray whose pick sphere the ray passes through.
func _pick(mouse: Vector2) -> CockpitClickable:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best: CockpitClickable = null
	var best_t := INF
	for node in get_tree().get_nodes_in_group(CockpitClickable.GROUP):
		var c := node as CockpitClickable
		if c == null or not c.is_visible_in_tree():
			continue
		var rel := c.get_pick_position() - origin
		var t := rel.dot(dir)
		if t <= 0.0 or t >= best_t:
			continue
		if (rel - dir * t).length() <= c.pick_radius:
			best = c
			best_t = t
	return best
