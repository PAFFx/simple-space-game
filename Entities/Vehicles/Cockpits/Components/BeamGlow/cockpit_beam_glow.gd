class_name CockpitBeamGlow
extends Node3D

## Lights the cockpit in the colour of beams passing close by, muzzle flashes and nearby
## hits: what the panoramic screen would throw into the room. One light, moved toward
## where most of the glow comes from (ProjectileManager.sample_glow).

## Light energy per unit of glow, and its ceiling.
@export var gain: float = 3.5
@export var max_energy: float = 16.0
@export var light_range: float = 4.5
## How far from here the light sits toward the glow, m.
@export var offset: float = 0.9
## The glow comes up at once and dies away over this long, s.
@export var decay: float = 0.3

var _light: OmniLight3D
var _energy := 0.0
# A beam through the cabin (DamageModel): its blinding light, then fire burning at the holes.
var _flash := 0.0
var _flash_color := Color.WHITE
var _flash_at := Vector3.ZERO
var _burn_left := 0.0
var _burn_at := Vector3.ZERO
var _burn_t := 0.0


## A beam went through the cabin at `at` (world): light `energy`, dying in a fraction of a second.
func hit_flash(at: Vector3, color: Color, energy: float) -> void:
	_flash = energy
	_flash_color = color
	_flash_at = to_local(at)


## Fire at `at` (world) for `seconds`: a flickering orange light, fading out at the end.
func burn(at: Vector3, seconds: float) -> void:
	_burn_at = to_local(at)
	_burn_left = seconds


func put_out() -> void:
	_flash = 0.0
	_burn_left = 0.0


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
	var energy := _energy
	_flash *= exp(-delta / 0.12)
	_burn_left = maxf(_burn_left - delta, 0.0)
	_burn_t += delta
	var fire := 0.0
	if _burn_left > 0.0:
		var flicker := 0.55 + 0.25 * sin(_burn_t * 23.0) * sin(_burn_t * 7.3) + 0.2 * randf()
		fire = 2.2 * flicker * minf(_burn_left, 1.0)
	if _flash > maxf(energy, fire):
		energy = _flash
		_light.light_color = _flash_color
		_light.position = _flash_at
	elif fire > energy:
		energy = fire
		_light.light_color = Color(1.0, 0.45, 0.12)
		_light.position = _burn_at
	_light.light_energy = energy
	_light.visible = energy > 0.01
