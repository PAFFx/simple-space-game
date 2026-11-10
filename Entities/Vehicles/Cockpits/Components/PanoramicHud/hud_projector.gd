class_name HudProjector
extends RefCounted

## Maps panoramic directions to HUD canvas pixels, matching panoramic_screen.gdshader:
##   x = (azimuth / TAU + 0.5) * width    forward at the centre, +azimuth = right
##   y = (0.5 - elevation / range) * height    +elevation = up
## Directions are in the sensor's local frame (forward = -Z), the same frame the
## screen uses, so anything placed here lines up with the sensor image.

var size := Vector2(4096, 2048)
var elevation_range: float = PI
## Canvas pixels per degree (vertical; horizontal matches when width = 2 × height).
var px_per_deg: float = 1.0


func _init(canvas_size: Vector2, p_elevation_range: float) -> void:
	size = canvas_size
	elevation_range = p_elevation_range
	px_per_deg = size.y / rad_to_deg(elevation_range)


func angles_to_canvas(azimuth: float, elevation: float) -> Vector2:
	var az := wrapf(azimuth, -PI, PI)
	return Vector2((az / TAU + 0.5) * size.x, (0.5 - elevation / elevation_range) * size.y)


func angles_deg_to_canvas(azimuth_deg: float, elevation_deg: float) -> Vector2:
	return angles_to_canvas(deg_to_rad(azimuth_deg), deg_to_rad(elevation_deg))


static func direction_to_angles(local_dir: Vector3) -> Vector2:
	var d := local_dir.normalized()
	return Vector2(atan2(d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


func direction_to_canvas(local_dir: Vector3) -> Vector2:
	var a := direction_to_angles(local_dir)
	return angles_to_canvas(a.x, a.y)


## Horizontal stretch of the equirectangular canvas at this elevation.
static func stretch_at(elevation: float) -> float:
	return 1.0 / maxf(cos(elevation), 0.15)
