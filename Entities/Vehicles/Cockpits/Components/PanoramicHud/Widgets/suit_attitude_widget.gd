class_name SuitAttitudeWidget
extends HudWidget

## Suit orientation relative to the cockpit, as simple gauges: a fixed circle
## (the cockpit, with level ticks) and a line through it (the suit).
##
##   left / right of view — side view, PITCH: the line is the suit's fore-aft
##                          axis, nose dot toward the screen centre
##   below the reticle    — rear view, ROLL: the line is the shoulders, short tick = head
##
## Mostly at zero; they come alive when auto-rotation leans or rolls the suit.

@export var side_azimuth_deg: float = 30.0
@export var side_elevation_deg: float = 0.0
@export var roll_elevation_deg: float = -7.5
@export var radius_deg: float = 1.8
## Line half-length as a multiple of the radius.
@export var line_extent: float = 1.45
## Below this the gauge is drawn dim.
@export var active_deg: float = 1.0


func draw_widget() -> void:
	if hud.vehicle == null:
		return
	var display := hud.get_display_basis()
	var body := hud.vehicle.get_global_transform_interpolated().basis.orthonormalized()
	var rel := display.inverse() * body
	var fwd := rel * Vector3.FORWARD
	var right := rel * Vector3.RIGHT
	var pitch := atan2(fwd.y, -fwd.z)
	var roll := atan2(-right.y, right.x)  # + = rolled right (right shoulder down)

	var nose_in := Vector2(cos(pitch), -sin(pitch))
	_gauge(-side_azimuth_deg, side_elevation_deg, nose_in, "PITCH", pitch, true)
	_gauge(side_azimuth_deg, side_elevation_deg, Vector2(-nose_in.x, nose_in.y), "PITCH", pitch, true)
	_gauge(0.0, roll_elevation_deg, Vector2(cos(roll), sin(roll)), "ROLL", roll, false)


## dir: unit direction of the suit line on the canvas (toward the nose / right shoulder).
func _gauge(az: float, el: float, dir: Vector2, label: String, angle: float, nose: bool) -> void:
	begin_local(az, el)
	var r := px(radius_deg)
	var active := absf(rad_to_deg(angle)) >= active_deg
	var ref := hud.dim_color
	var c := hud.primary_color if active else hud.dim_color
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, ref, 1.5, true)
	for s in [-1.0, 1.0]:
		line(Vector2(r * s, 0), Vector2(r * 1.18 * s, 0), ref, 1.5)
	var half := dir * r * line_extent
	line(-half, half, c, hud.line_width + 0.5)
	if nose:
		draw_circle(half, 4.0, c, true, -1.0, true)
	else:
		var up := Vector2(dir.y, -dir.x)  # perpendicular, toward the suit's head
		line(Vector2.ZERO, up * r * 0.55, c, hud.line_width + 0.5)
	draw_circle(Vector2.ZERO, 2.5, c, true, -1.0, true)
	text(Vector2(0, r * 1.18 + 20.0), "%s %+d°" % [label, roundi(rad_to_deg(angle))], c,
			HORIZONTAL_ALIGNMENT_CENTER, 14)
	end_local()
