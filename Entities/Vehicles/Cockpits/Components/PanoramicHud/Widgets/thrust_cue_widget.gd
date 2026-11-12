class_name ThrustCueWidget
extends HudWidget

## Chevron columns just inside both pitch ladder columns, below the suit line, lit only
## while boosting or braking: ^ chevrons lighting one after another upward for boost,
## v chevrons running downward for brake. Full boost / hard brake doubles each chevron,
## runs faster and turns them the accent colour.

@export var azimuth_deg: float = 26.5
## Column top and bottom, deg.
@export var elevation_deg := Vector2(-2.5, -10.0)
@export var chevrons: int = 5
@export var chevron_half_width_deg: float = 0.8
@export var chevron_depth_deg: float = 0.5
## Chevrons lit per second (normal, full).
@export var run_rate := Vector2(5.0, 9.0)
@export var fade_time: float = 0.2

var _amount := 0.0
var _full := 0.0
var _up := true
var _run := 0.0
var _last_ms := -1


func draw_widget() -> void:
	var fc := hud.flight_computer
	if fc == null:
		return
	var now := Time.get_ticks_msec()
	var dt := 0.0 if _last_ms < 0 else (now - _last_ms) / 1000.0
	_last_ms = now

	var boost := fc.get_boost_level()
	var brake := fc.get_brake_level()
	var level := maxi(boost, brake)
	if level > 0:
		_up = brake == 0  # brake wins when both are held
	var step := dt / maxf(fade_time, 0.01)
	_amount = move_toward(_amount, 1.0 if level > 0 else 0.0, step)
	_full = move_toward(_full, 1.0 if level == 2 else 0.0, step)
	if _amount <= 0.0:
		return
	_run = fposmod(_run + dt * lerpf(run_rate.x, run_rate.y, _full), float(chevrons + 2))

	var c := hud.primary_color.lerp(hud.suit_accent_color, _full)
	for side in [-1.0, 1.0]:
		_column(side, c)


func _column(side: float, c: Color) -> void:
	var p := patch(_dir(azimuth_deg * side, 0.0), Vector3.UP)
	var top := elevation_deg.x
	var bottom := elevation_deg.y
	var dir := 1.0 if _up else -1.0
	for i in chevrons:
		var t := float(i) / maxf(chevrons - 1, 1)
		var y := lerpf(bottom, top, t)
		# Lit chevron runs bottom to top for boost, top to bottom for brake.
		var order := i if _up else chevrons - 1 - i
		var d := absf(_run - 1.0 - order)
		var glow := clampf(1.0 - d * 0.6, 0.0, 1.0)
		var a := lerpf(0.18, 1.0, glow) * _amount
		var col := Color(c, c.a * a)
		_chevron(p, y, dir, col)
		if _full > 0.0:
			_chevron(p, y - dir * 0.4, dir, Color(col, col.a * _full * 0.7))


## ^ (dir +1) or v (dir -1) centred on the column at elevation offset y, deg.
func _chevron(p: Patch, y: float, dir: float, color: Color) -> void:
	var w := chevron_half_width_deg
	var tip := Vector2(0, y + chevron_depth_deg * 0.5 * dir)
	var back := y - chevron_depth_deg * 0.5 * dir
	# No dark edge: on a dim chevron it would outweigh the line.
	seam_safe_polyline(PackedVector2Array([patch_point(p, Vector2(-w, back)), patch_point(p, tip),
			patch_point(p, Vector2(w, back))]), color, 2.0, false)


## Display direction at azimuth / elevation, deg.
func _dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
