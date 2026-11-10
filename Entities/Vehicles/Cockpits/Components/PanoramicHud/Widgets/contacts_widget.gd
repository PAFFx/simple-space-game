class_name ContactsWidget
extends HudWidget

## Brackets every Node3D in the `hud_contacts` group with name, range and
## closure rate. On a 360° screen nothing is ever "off screen", so no edge arrows.
## Optional metadata on a contact: `hud_label` (String), `hud_radius` (metres).

const GROUP := &"hud_contacts"

@export var min_box_deg: float = 1.6
@export var default_radius: float = 20.0

var _last_range := {}
var _closure := {}


func draw_widget() -> void:
	var origin := hud.get_display_origin()
	var dt := maxf(get_process_delta_time(), 1e-3)
	for node in get_tree().get_nodes_in_group(GROUP):
		var contact := node as Node3D
		if contact == null:
			continue
		var rel := contact.global_position - origin
		var dist := rel.length()
		if dist < 1.0:
			continue
		var id := contact.get_instance_id()
		if _last_range.has(id):
			var rate: float = (_last_range[id] - dist) / dt
			_closure[id] = lerpf(_closure.get(id, rate), rate, 0.1)
		_last_range[id] = dist

		var angles := HudProjector.direction_to_angles(hud.world_to_display(rel))
		begin_local_at(hud.projector.angles_to_canvas(angles.x, angles.y), angles.y)
		var radius: float = contact.get_meta("hud_radius", default_radius)
		var half := px(maxf(min_box_deg, rad_to_deg(atan(radius / dist))))
		brackets(Vector2(half, half), maxf(half * 0.35, 8.0), hud.primary_color)
		var label: String = contact.get_meta("hud_label", String(contact.name))
		var left := HORIZONTAL_ALIGNMENT_LEFT
		var x := half + 6.0
		text(Vector2(x, -half + 14.0), label.to_upper(), hud.primary_color, left, 15)
		text(Vector2(x, -half + 32.0), _format_range(dist), hud.dim_color, left, 14)
		text(Vector2(x, -half + 48.0), "Vc %+.1f" % _closure.get(id, 0.0), hud.dim_color, left, 14)
		end_local()


static func _format_range(metres: float) -> String:
	return "%.2f km" % (metres / 1000.0) if metres >= 1000.0 else "%d m" % roundi(metres)
