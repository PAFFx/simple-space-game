class_name CockpitBeamGlow
extends Node3D

## Lights the cockpit in the colour of beams passing close by, muzzle flashes and nearby
## hits: what the panoramic screen would throw into the room. One light, moved toward
## where most of the glow comes from (ProjectileManager.sample_glow).

## Light energy per unit of glow, and its ceiling.
@export var gain: float = 1.5
@export var max_energy: float = 7.0
@export var light_range: float = 3.2
## How far from here the light sits toward the glow, m.
@export var offset: float = 0.9
## The glow comes up at once and dies away over this long, s.
@export var decay: float = 0.12

var _light: OmniLight3D
var _energy := 0.0


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.name = "GlowLight"
	_light.light_cull_mask = Layers.COCKPIT | Layers.PILOT
	_light.omni_range = light_range
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)


func _process(delta: float) -> void:
	var manager := ProjectileManager.find(self)
	var target := 0.0
	if manager != null:
		var sample := manager.sample_glow(global_position)
		var sum: Vector3 = sample[0]
		var strength := maxf(sum.x, maxf(sum.y, sum.z))
		if strength > 0.002:
			target = minf(strength * gain, max_energy)
			_light.light_color = Color(sum.x, sum.y, sum.z) / strength
			_light.global_position = global_position + (sample[1] as Vector3) * offset
	_energy = target if target > _energy else lerpf(_energy, target, 1.0 - exp(-delta / maxf(decay, 0.01)))
	_light.light_energy = _energy
	_light.visible = _energy > 0.01
