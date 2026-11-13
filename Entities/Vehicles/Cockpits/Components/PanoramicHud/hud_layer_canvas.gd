class_name HudLayerCanvas
extends HudWidget

## Draws a widget's fixed parts into a PanoramicHud layer (see add_layer_drawer).
## Only redrawn on request, unlike other widgets.

var draw_fn: Callable


func _process(_delta: float) -> void:
	pass


func _draw() -> void:
	if hud != null and hud.projector != null:
		draw_fn.call(self)
		end_local()


func draw_widget() -> void:
	pass
