class_name ContactsWidget
extends HudWidget

## Marks every Node3D in the `hud_contacts` group with a triangle pointing down around
## it, plus name, range and closure rate. On a 360° screen nothing is ever "off screen",
## so no edge arrows.
##
##   any contact   three bars along the triangle's sides, short of its corners: a faint
##                 fill inside a fine border, so they don't hide what's behind. A contact
##                 too big for the triangle gets a bracket at each corner of a square
##   hostile       adds the corners of a smaller triangle inside and two strokes across
##                 each corner outside, in the hostile colour
##   selected      adds a fine winged V in the middle
##
## Nothing is drawn on the HUD canvas. The screen shader draws the triangles
## (hud_layers.gdshaderinc) from the directions and sizes given here. The text goes into
## its own small atlas, one slot per contact, several times finer than the canvas so it
## stays sharp, and is redrawn `label_hz` times a second so the numbers hold still long
## enough to read.
##
## Optional metadata on a contact: `hud_label` (String), `hud_radius` (metres),
## `hud_hostile` (bool). Nothing selects a contact yet: set `selected`, or (temporary, to
## see the mark) put metadata `hud_selected` on a contact.

const GROUP := &"hud_contacts"
## Contacts the shader draws (HUD_CONTACT_MAX); the nearest ones win.
const MAX_CONTACTS := 16
## Atlas layout and the screen size of a slot: HUD_CONTACT_SLOTS, HUD_CONTACT_LABEL_DEG.
const SLOT_GRID := Vector2i(2, 8)
const SLOT_SIZE := Vector2i(384, 192)
const SLOT_DEG := Vector2(10.0, 5.0)
const MAX_LABEL_LENGTH := 12

## Half the triangle's side: the contact's angular radius times `fit`, within these, deg.
@export var min_half_deg: float = 1.8
@export var max_half_deg: float = 11.0
@export var fit: float = 1.75
@export var default_radius: float = 20.0
## Largest square for a big contact, half its side, deg.
@export var max_box_deg: float = 35.0
## How solid the inside of the bars is, as a share of their border.
@export var bar_fill: float = 0.5
## Text redraws per second.
@export var label_hz: float = 10.0
## Text height, deg: the name, and the two lines under it.
@export var name_deg: float = 1.3
@export var detail_deg: float = 1.15

## The selected contact, or null.
var selected: Node3D

var _last_range := {}
var _closure := {}
# Contact instance id → its slot (index in the shader's arrays and the atlas).
var _slots := {}
# Slot → [name, range, closure, colour], as last drawn.
var _labels := {}
var _label_viewport: SubViewport
var _label_canvas: Node2D
var _label_due := 0.0


func setup_layers() -> void:
	hud.set_hud_parameter(&"hud_contact_color", hud.contact_color)
	hud.set_hud_parameter(&"hud_contact_hostile_color", hud.hostile_color)
	hud.set_hud_parameter(&"hud_contact_selected_color", hud.selected_color)
	hud.set_hud_parameter(&"hud_contact_fill", bar_fill)
	_label_viewport = SubViewport.new()
	_label_viewport.name = "ContactLabels"
	_label_viewport.size = SLOT_GRID * SLOT_SIZE
	_label_viewport.transparent_bg = true
	_label_viewport.disable_3d = true
	_label_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	hud.add_child(_label_viewport)
	_label_canvas = Node2D.new()
	_label_canvas.draw.connect(_draw_labels)
	_label_viewport.add_child(_label_canvas)
	hud.set_hud_parameter(&"hud_contact_labels", _label_viewport.get_texture())


func _process(delta: float) -> void:
	if hud == null or not hud.is_live() or _label_viewport == null:
		return
	var origin := hud.get_view_origin()
	var dt := maxf(delta, 1e-3)
	var at := PackedVector4Array()
	var state := PackedVector4Array()
	at.resize(MAX_CONTACTS)
	state.resize(MAX_CONTACTS)
	if selected != null and not is_instance_valid(selected):
		selected = null
	var contacts := _nearest(origin)
	var changed := _assign_slots(contacts)
	var labels := {}
	for contact in contacts:
		var rel := contact.get_global_transform_interpolated().origin - origin
		var dist := rel.length()
		if dist < 1.0:
			continue
		var id := contact.get_instance_id()
		if _last_range.has(id):
			var rate: float = (_last_range[id] - dist) / dt
			_closure[id] = lerpf(_closure.get(id, rate), rate, 0.1)
		_last_range[id] = dist

		var dir := hud.world_to_display(rel).normalized()
		var radius: float = contact.get_meta("hud_radius", default_radius)
		var apparent := rad_to_deg(atan(radius / dist))
		# Too big for the triangle: a square around it instead.
		var box := apparent * fit > max_half_deg
		var half := minf(apparent, max_box_deg) if box else maxf(apparent * fit, min_half_deg)
		var hostile: bool = contact.get_meta("hud_hostile", false)
		var is_selected: bool = contact == selected or contact.get_meta("hud_selected", false)
		# The triangle lies within 1.7 half sides of the middle, the text further right.
		var reach := maxf(half * 1.7, half * 0.62 + 0.5 + SLOT_DEG.length())
		if box:
			reach = half * 1.42 + 1.5 + SLOT_DEG.x
		var slot: int = _slots[id]
		at[slot] = Vector4(dir.x, dir.y, dir.z, half)
		state[slot] = Vector4(float(hostile), float(is_selected), cos(deg_to_rad(minf(reach, 80.0))), float(box))
		var label: String = contact.get_meta("hud_label", String(contact.name))
		labels[slot] = [label.to_upper().left(MAX_LABEL_LENGTH), _format_range(dist),
				"Vc %+.1f" % _closure.get(id, 0.0), hud.hostile_color if hostile else hud.contact_color]
	hud.set_hud_parameter(&"hud_contact_at", at)
	hud.set_hud_parameter(&"hud_contact_state", state)

	_label_due -= delta
	if changed or _label_due <= 0.0:
		_label_due = 1.0 / maxf(label_hz, 0.1)
		_labels = labels
		_label_canvas.queue_redraw()
		_label_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func draw_widget() -> void:
	pass


## Keeps each contact in the slot it already has, so its text stays with it between
## atlas redraws; true if any slot changed hands.
func _assign_slots(contacts: Array[Node3D]) -> bool:
	var ids := {}
	for contact in contacts:
		ids[contact.get_instance_id()] = true
	var changed := false
	for id: int in _slots.keys():
		if not ids.has(id):
			_slots.erase(id)
			_last_range.erase(id)
			_closure.erase(id)
			changed = true
	var used := {}
	for id: int in _slots:
		used[_slots[id]] = true
	var next := 0
	for id: int in ids:
		if _slots.has(id):
			continue
		while used.has(next):
			next += 1
		_slots[id] = next
		used[next] = true
		changed = true
	return changed


func _draw_labels() -> void:
	var px_per_deg := SLOT_SIZE.y / SLOT_DEG.y
	var name_px := roundi(name_deg * px_per_deg)
	var detail_px := roundi(detail_deg * px_per_deg)
	var outline := roundi(hud.halo_width * 1.5 / hud.projector.px_per_deg * px_per_deg)
	for slot: int in _labels:
		var label: Array = _labels[slot]
		var color: Color = label[3]
		color.a = maxf(color.a, 0.95)
		var corner := Vector2(slot % SLOT_GRID.x, slot / SLOT_GRID.x) * Vector2(SLOT_SIZE) + Vector2(outline + 2.0, 0.0)
		var y := name_px * 1.05
		for line in 3:
			var size := name_px if line == 0 else detail_px
			var at := corner + Vector2(0.0, y)
			if hud.halo_color.a > 0.0:
				_label_canvas.draw_string_outline(hud.font, at, label[line], HORIZONTAL_ALIGNMENT_LEFT, -1, size,
						outline, hud.halo_color)
			_label_canvas.draw_string(hud.font, at, label[line], HORIZONTAL_ALIGNMENT_LEFT, -1, size,
					color if line == 0 else Color(color, color.a * 0.85))
			y += detail_px * 1.25


## The MAX_CONTACTS nearest contacts.
func _nearest(origin: Vector3) -> Array[Node3D]:
	var contacts: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if node is Node3D:
			contacts.append(node)
	if contacts.size() > MAX_CONTACTS:
		contacts.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
		contacts.resize(MAX_CONTACTS)
	return contacts


static func _format_range(metres: float) -> String:
	return "%.2f km" % (metres / 1000.0) if metres >= 1000.0 else "%d m" % roundi(metres)
