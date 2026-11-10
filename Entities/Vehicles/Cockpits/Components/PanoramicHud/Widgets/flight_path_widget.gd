class_name FlightPathWidget
extends HudWidget

## Prograde (velocity vector) and retrograde markers relative to the reference
## frame. In space this is the most important cue: where you are actually going
## versus where the suit is pointing.

@export var min_speed: float = 0.3   ## m/s, below this the markers are hidden
@export var marker_deg: float = 0.9


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var v := fc.state.linear_velocity
	var speed := v.length()
	if speed < min_speed:
		return
	var r := px(marker_deg)

	_begin_at_dir(v)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, hud.primary_color, hud.line_width, true)
	line(Vector2(r, 0), Vector2(r * 2.4, 0))
	line(Vector2(-r, 0), Vector2(-r * 2.4, 0))
	line(Vector2(0, -r), Vector2(0, -r * 1.9))
	text(Vector2(r * 2.8, r * 0.4), "%.1f" % speed)
	end_local()

	_begin_at_dir(-v)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, hud.dim_color, hud.line_width, true)
	var k := r * 0.7
	line(Vector2(-k, -k), Vector2(k, k), hud.dim_color)
	line(Vector2(-k, k), Vector2(k, -k), hud.dim_color)
	end_local()


func _begin_at_dir(world_dir: Vector3) -> void:
	var angles := HudProjector.direction_to_angles(hud.world_to_sensor(world_dir))
	begin_local_at(hud.projector.angles_to_canvas(angles.x, angles.y), angles.y)
