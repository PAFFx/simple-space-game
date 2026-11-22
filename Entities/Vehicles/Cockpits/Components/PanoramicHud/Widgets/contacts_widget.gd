class_name ContactsWidget
extends HudWidget

## Marks every Node3D in the `hud_contacts` group with a triangle pointing down around
## it, plus its name and range, and for the locked target its closure rate Vc (the rest is
## on the MFD target page). On a 360° screen nothing is ever "off screen", so no edge arrows.
##
##   any contact   three bars along the triangle's sides, short of its corners: a faint
##                 fill inside a fine border, so they don't hide what's behind. A contact
##                 too big for the triangle gets a bracket at each corner of a square
##   hostile       adds the corners of a smaller triangle inside, in the hostile colour
##   candidate     (under the designation cursor) its bars filled solid, in the border's
##                 colour
##   locked        strokes across each corner outside, by the track's quality: two = good,
##                 one = poor, one blinking = coasting. Drawn last, over the rest of the
##                 HUD (the gun circle too), so its mark and text are never covered; a
##                 contact whose text would run into its text shows none until clear
##   from sensors  every contact is drawn where its sensor track puts it
##                 (FireControl.get_contact_position), not where it really is, and at
##                 as big as it could look: its angular error, and how much nearer (so
##                 bigger) it could be for its range error. A new contact starts big and
##                 shrinks as the track settles: it picks a new size at most once every
##                 `size_period` s, only for a change over `size_step` (`settled_size_step`
##                 once the range has settled), and eases to it
##                 over `size_ease` s, so it
##                 never jitters. A contact the sensors don't track isn't drawn
##
## Nothing is drawn on the HUD canvas. The screen shader draws the triangles
## (hud_layers.gdshaderinc) from the directions and sizes given here. The text goes into
## its own small atlas, one slot per contact, several times finer than the canvas so it
## stays sharp, and is redrawn `label_hz` times a second so the numbers hold still long
## enough to read.
##
## Optional metadata on a contact: `hud_label` (String), `hud_radius` (metres),
## `hud_hostile` (bool).

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
## How often a triangle's size may change, per second, and by at least what share.
@export var size_period: float = 1.0
@export var size_step: float = 0.08
## Once the range is settled (doubt under ~10%) a size change must beat this instead: the
## settled range still wanders a few percent, and the mark shouldn't follow that.
@export var settled_size_step: float = 0.25
@export var size_ease: float = 0.5
## Coasting track: the lock's one dash blinks this many times a second.
@export var coast_blink_hz: float = 3.0
## Text redraws per second.
@export var label_hz: float = 10.0
## Text height, deg: the name, and the lines under it.
@export var name_deg: float = 1.3
@export var detail_deg: float = 1.15
## The locked target's Vc follows the track's velocity estimate this slowly, s.
@export var closure_ease: float = 0.4

## Half the locked target's triangle as drawn this frame, deg (0 = none drawn): the gun
## solution circle stays outside it.
var locked_half := 0.0

var _fcs: FireControl
# Contact instance id → its slot (index in the shader's arrays and the atlas).
var _slots := {}
# Slot → [colour, name, range, (Vc)], as last drawn.
var _labels := {}
var _label_viewport: SubViewport
var _label_canvas: Node2D
var _label_due := 0.0
var _half_shown := {}                 ## contact instance id → [drawn, aimed at, next pick (s)]
var _hidden := {}                     ## slots whose text gives way to the locked target's
var _closure := 0.0
var _closure_of: Node3D


func setup_layers() -> void:
	hud.set_hud_parameter(&"hud_contact_color", hud.contact_color)
	hud.set_hud_parameter(&"hud_contact_hostile_color", hud.hostile_color)
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
	if _fcs == null and hud.vehicle != null:
		_fcs = hud.vehicle.find_component(FireControl) as FireControl
	var origin := hud.get_view_origin()
	var at := PackedVector4Array()
	var state := PackedVector4Array()
	at.resize(MAX_CONTACTS)
	state.resize(MAX_CONTACTS)
	var locked: Node3D = _fcs.locked if _fcs != null else null
	var candidate: Node3D = _fcs.candidate if _fcs != null else null
	var now := Time.get_ticks_msec() / 1000.0
	var contacts := _nearest(origin)
	var changed := _assign_slots(contacts)
	var labels := {}
	var placed := {}                    ## slot → [direction, half, box]
	locked_half = 0.0
	var ease := 1.0 - exp(-delta / maxf(size_ease, 0.01))
	for contact in contacts:
		var is_locked := contact == locked
		var pos := _fcs.get_contact_position(contact) if _fcs != null else contact.get_global_transform_interpolated().origin
		var rel := pos - origin
		var dist := rel.length()
		if dist < 1.0:
			continue
		var id := contact.get_instance_id()

		var dir := hud.world_to_display(rel).normalized()
		var radius: float = contact.get_meta("hud_radius", default_radius)
		var apparent := rad_to_deg(atan(radius / dist))
		# Too big for the triangle: a square around it instead.
		var box := apparent * fit > max_half_deg
		var half := minf(apparent, max_box_deg) if box else maxf(apparent * fit, min_half_deg)
		var doubt := _fcs.get_contact_range_error_share(contact) if _fcs != null else 0.0
		if not box and _fcs != null:
			# Unsure of its range, it could be nearer, so bigger: drawn as big as that.
			half = maxf(half / (1.0 - minf(doubt, 0.75)), _fcs.get_contact_angular_error_deg(contact))
			half = minf(half, max_half_deg)
		half = _smoothed_half(id, half, now, ease, lerpf(settled_size_step, size_step, clampf((doubt - 0.1) / 0.2, 0.0, 1.0)))
		if is_locked:
			locked_half = half * (1.42 if box else 1.0)
		var hostile: bool = contact.get_meta("hud_hostile", false)
		# Lock dashes in the integer part; the fraction fills the bars solid (the candidate).
		var marks := 0.0
		if is_locked:
			match _fcs.get_track_mark():
				FireControl.TrackMark.GOOD:
					marks = 2.0
				FireControl.TrackMark.POOR:
					marks = 1.0
				FireControl.TrackMark.COAST:
					marks = 1.0 if fmod(now * coast_blink_hz, 1.0) < 0.5 else 0.0
		elif contact == candidate:
			marks = 0.9
		# The triangle lies within 1.7 half sides of the middle, the text further right.
		var reach := maxf(half * 1.7, half * 0.62 + 0.5 + SLOT_DEG.length())
		if box:
			reach = half * 1.42 + 1.5 + SLOT_DEG.x
		var slot: int = _slots[id]
		at[slot] = Vector4(dir.x, dir.y, dir.z, half)
		state[slot] = Vector4(float(hostile), marks, cos(deg_to_rad(minf(reach, 80.0))), float(box))
		var label: String = contact.get_meta("hud_label", String(contact.name))
		var lines := [hud.hostile_color if hostile else hud.contact_color,
				label.to_upper().left(MAX_LABEL_LENGTH), _format_range(dist)]
		if is_locked and _fcs != null:
			lines.append("Vc %+d" % roundi(_eased_closure(contact, rel / dist, delta)))
		labels[slot] = lines
		placed[slot] = [dir, half, box]
	var locked_slot := -1
	if locked != null and _slots.has(locked.get_instance_id()):
		locked_slot = _slots[locked.get_instance_id()]
	else:
		_closure_of = null
	hud.set_hud_parameter(&"hud_contact_locked", locked_slot)
	if _hide_under_locked(labels, placed, locked_slot):
		changed = true
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


## Drops the text of every contact whose text would overlap the locked target's; true if
## that set changed (the atlas must be redrawn).
func _hide_under_locked(labels: Dictionary, placed: Dictionary, locked_slot: int) -> bool:
	var hidden := {}
	if placed.has(locked_slot):
		var at: Array = placed[locked_slot]
		var c: Vector3 = at[0]
		var up := Vector3.UP - c * c.y
		up = (Vector3.BACK - c * c.z if up.length_squared() < 1e-6 else up).normalized()
		var right := c.cross(up)
		var mine := _label_rect(Vector2.ZERO, at[1], at[2], labels[locked_slot])
		for slot: int in placed:
			var other: Array = placed[slot]
			var d: Vector3 = other[0]
			if slot == locked_slot or d.dot(c) < 0.5:
				continue
			var off := Vector2(rad_to_deg(atan(d.dot(right) / d.dot(c))), rad_to_deg(atan(d.dot(up) / d.dot(c))))
			if mine.intersects(_label_rect(off, other[1], other[2], labels[slot])):
				hidden[slot] = true
				labels.erase(slot)
	var changed := hidden.hash() != _hidden.hash()
	_hidden = hidden
	return changed


## A contact's text block around its middle `off`, deg, y down (shader:
## hud_contact_label_uv), as wide and tall as its text.
func _label_rect(off: Vector2, half: float, box: bool, label: Array) -> Rect2:
	var corner := Vector2(half + 0.6, half) if box else Vector2(half * 0.62 + 0.5, 1.0 - half * 0.3)
	var px_per_deg := SLOT_SIZE.y / SLOT_DEG.y
	var widest := 0.0
	for line in range(1, label.size()):
		var size := roundi((name_deg if line == 1 else detail_deg) * px_per_deg)
		widest = maxf(widest, hud.font.get_string_size(label[line], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var tall := name_deg * 1.05 + (label.size() - 2) * detail_deg * 1.25 + detail_deg * 0.3
	return Rect2(Vector2(off.x + corner.x, -(off.y + corner.y)), Vector2(minf(widest / px_per_deg + 0.2, SLOT_DEG.x), tall))


## The locked target's closure rate, m/s (+ = closing): its track velocity against ours
## along the line of sight, eased so the 10 Hz text doesn't flicker.
func _eased_closure(contact: Node3D, los: Vector3, delta: float) -> float:
	var vc := -(_fcs.get_contact_velocity(contact) - _fcs.get_own_velocity()).dot(los)
	if contact != _closure_of:
		_closure_of = contact
		_closure = vc
	_closure = lerpf(_closure, vc, 1.0 - exp(-delta / maxf(closure_ease, 0.01)))
	return _closure


## The size a contact's mark is drawn at: once a size_period it may pick `want` as its new
## size (if that differs by more than `step`), and it eases there.
func _smoothed_half(id: int, want: float, now: float, ease: float, step: float) -> float:
	var st: Array = _half_shown.get(id, [])
	if st.is_empty():
		# Spread the picks over the period, so contacts don't all change together.
		st = [want, want, now + randf() * size_period]
		_half_shown[id] = st
	if now >= st[2]:
		st[2] = now + size_period
		if absf(want - st[1]) > st[1] * step:
			st[1] = want
	st[0] = lerpf(st[0], st[1], ease)
	return st[0]


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
			_half_shown.erase(id)
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
		var color: Color = label[0]
		color.a = maxf(color.a, 0.95)
		var corner := Vector2(slot % SLOT_GRID.x, slot / SLOT_GRID.x) * Vector2(SLOT_SIZE) + Vector2(outline + 2.0, 0.0)
		var y := name_px * 1.05
		for line in range(1, label.size()):
			var size := name_px if line == 1 else detail_px
			var at := corner + Vector2(0.0, y)
			if hud.halo_color.a > 0.0:
				_label_canvas.draw_string_outline(hud.font, at, label[line], HORIZONTAL_ALIGNMENT_LEFT, -1, size,
						outline, hud.halo_color)
			_label_canvas.draw_string(hud.font, at, label[line], HORIZONTAL_ALIGNMENT_LEFT, -1, size,
					color if line == 1 else Color(color, color.a * 0.85))
			y += detail_px * 1.25


## The MAX_CONTACTS nearest contacts in sight (the locked one always: the sensors show it).
func _nearest(origin: Vector3) -> Array[Node3D]:
	var contacts: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var contact := node as Node3D
		if contact == null or contact == (hud.vehicle as Node):
			continue
		if _fcs != null and contact != _fcs.locked and not _fcs.can_see(contact):
			continue
		contacts.append(contact)
	if contacts.size() > MAX_CONTACTS:
		contacts.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return _known_position(a).distance_squared_to(origin) < _known_position(b).distance_squared_to(origin))
		contacts.resize(MAX_CONTACTS)
	return contacts


func _known_position(contact: Node3D) -> Vector3:
	return _fcs.get_contact_position_now(contact) if _fcs != null else contact.global_position


static func _format_range(metres: float) -> String:
	return "%.2f km" % (metres / 1000.0) if metres >= 1000.0 else "%d m" % roundi(metres)
