class_name DamageFx
extends Node3D

## What damage looks like besides the holes themselves (Docs/Damage/beam_effects.md): molten
## spray and a vapour jet where a beam drills in, a blow-out cone where it comes out, steam
## bursts with their glittering ice, stores going off, arcs from cut wiring, sparks where a
## limb tears off, the reactor's flash. Everything is in world space and keeps the velocity it
## was thrown with, so a boosting suit leaves its droplets behind on its own (no gravity in
## space). A few lights follow the hottest fresh holes. One per scene: DamageFx.of(node).

const GROUP := &"damage_fx"
const MAX_LIGHTS := 4
## Effects riding the suit (the cabin's, fires, leaks): DamageModel.repair clears them.
const ATTACHED_GROUP := &"damage_fx_attached"

class HoleLight:
	var light: OmniLight3D
	var anchor: Node3D
	var local := Vector3.ZERO
	var age := 0.0
	var life := 6.0
	var energy := 4.0
	var fire := false   ## flickers orange at an even level, fading out at the end

class Arc:
	var mesh: MeshInstance3D
	var centre := Vector3.ZERO
	var size := 1.0
	var age := 0.0
	var life := 0.4
	var velocity := Vector3.ZERO

class Stub:
	var root: Node3D
	var cables: MeshInstance3D
	var hot: StandardMaterial3D
	var radius := 1.0
	var age := 0.0
	var cable_base: Array[Vector3] = []
	var cable_dir: Array[Vector3] = []
	var next_spark := 0.3

var _lights: Array[HoleLight] = []
var _stubs: Array[Stub] = []
var _arcs: Array[Arc] = []
var _spark_material: StandardMaterial3D
var _vapour_material: StandardMaterial3D
var _glint_material: StandardMaterial3D
var _arc_material: StandardMaterial3D


static func of(node: Node) -> DamageFx:
	var tree := node.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found != null:
		return found as DamageFx
	var fx := DamageFx.new()
	fx.name = "DamageFx"
	tree.current_scene.add_child(fx) if tree.current_scene != null else tree.root.add_child(fx)
	return fx


func _init() -> void:
	add_to_group(GROUP)
	_spark_material = StandardMaterial3D.new()
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.vertex_color_use_as_albedo = true
	_spark_material.albedo_color = Color(1.6, 1.6, 1.6)
	# Streaks are turned by the emitter (Y along the velocity, facing the camera); a material
	# billboard would override that and stand every streak upright.
	_spark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.albedo_texture = _soft_texture(true)
	_vapour_material = StandardMaterial3D.new()
	_vapour_material.vertex_color_use_as_albedo = true
	_vapour_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_vapour_material.billboard_keep_scale = true
	_vapour_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_vapour_material.albedo_texture = _puff_texture()
	_vapour_material.roughness = 1.0
	_vapour_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_vapour_material.proximity_fade_enabled = true
	_vapour_material.proximity_fade_distance = 2.0
	_vapour_material.disable_receive_shadows = true
	_glint_material = _spark_material.duplicate()
	_glint_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_glint_material.billboard_keep_scale = true
	_glint_material.albedo_color = Color(1.8, 1.9, 2.2)
	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.albedo_color = Color(2.5, 3.5, 8.0)
	_arc_material.vertex_color_use_as_albedo = false


func _process(delta: float) -> void:
	_now += delta
	if not _warm.is_empty():
		_warm.pop_front().call()
	for i in range(_lights.size() - 1, -1, -1):
		var h := _lights[i]
		h.age += delta
		if h.age >= h.life or not is_instance_valid(h.anchor):
			_free_light(h.light)
			_lights.remove_at(i)
			continue
		var k := 1.0 - h.age / h.life
		h.light.global_position = h.anchor.global_transform * h.local
		if h.fire:
			var flicker := 0.6 + 0.25 * sin(_now * 21.0 + h.life) * sin(_now * 6.7) + 0.15 * randf()
			h.light.light_energy = h.energy * flicker * minf((h.life - h.age) / 2.0, 1.0)
			h.light.light_color = Color(1.0, 0.42, 0.1)
		else:
			h.light.light_energy = h.energy * k * k * (1.0 if h.age > 0.15 else 2.0)
			h.light.light_color = Color(1.0, lerpf(0.25, 0.55, k), lerpf(0.05, 0.25, k))
	for i in range(_stubs.size() - 1, -1, -1):
		var st := _stubs[i]
		if not is_instance_valid(st.root):
			_stubs.remove_at(i)
			continue
		st.age += delta
		# The broken ends cool like the holes (over tens of seconds).
		st.hot.emission_energy_multiplier = 3.0 * exp(-st.age / 12.0)
		st.hot.emission = Color(1.0, lerpf(0.12, 0.45, exp(-st.age / 6.0)), 0.04)
		_draw_cables(st)
		st.next_spark -= delta
		if st.age < 20.0 and st.next_spark <= 0.0:
			st.next_spark = randf_range(0.4, 2.5) * (1.0 + st.age * 0.2)
			var k := randi() % st.cable_base.size()
			var end := st.root.global_transform * (st.cable_base[k] + st.cable_dir[k])
			_arc(end, Vector3.ZERO, st.radius * 0.5, 0.15)
			_spray(end, Vector3.UP, Vector3.ZERO, 12, 180.0, 4.0, 0.1, 0.4, 0.02, 15.0)
	for i in range(_arcs.size() - 1, -1, -1):
		var a := _arcs[i]
		a.age += delta
		a.centre += a.velocity * delta
		if a.age >= a.life:
			a.mesh.queue_free()
			_arcs.remove_at(i)
			continue
		_draw_arc(a)


## A beam drilling in at `at`, going `direction`: white contact spray across the surface,
## a vapour jet blowing back along the beam, a light on the hole.
var _warm: Array[Callable] = []
var _warm_anchor: Node3D


## Plays every effect once, far off where nobody sees it, one per frame: the first of each kind
## builds its particle materials and shaders, 40–50 ms, which would otherwise land on the
## first hit that uses it.
func prewarm() -> void:
	if _warm_anchor != null:
		return
	_warm_anchor = Node3D.new()
	_warm_anchor.name = "Prewarm"
	add_child(_warm_anchor)
	var at := Vector3(0.0, -1.0e6, 0.0)
	_warm_anchor.global_position = at
	var v := Vector3.ZERO
	for i in MAX_LIGHTS:
		_free_light(_take_light())
	_warm = [
		func() -> void: drill_in(at, Vector3.FORWARD, v, 0.6, _warm_anchor),
		func() -> void: blow_out(at, Vector3.FORWARD, v, 0.6, _warm_anchor),
		func() -> void: burst(at, v, 1.0, &"steam"),
		func() -> void: burst(at, v, 1.0, &"minovsky"),
		func() -> void: burst(at, v, 1.0, &"stores"),
		func() -> void: burst(at, v, 1.0, &"electronics"),
		func() -> void: i_field(at, Vector3.UP, v, Color(1.0, 0.4, 0.7)),
		func() -> void: vent(_warm_anchor, Vector3.ZERO, Vector3.FORWARD, 0.2, 1.0),
		func() -> void: smoke_leak(_warm_anchor, Vector3.ZERO, Vector3.FORWARD, 0.2),
		func() -> void: creak(at, v, 1.0),
		func() -> void: sever(at, v),
		func() -> void: stump(_warm_anchor, at, Vector3.UP, 0.8, v),
		func() -> void: fragment_strike(at, Vector3.FORWARD, v, 0.0),
		func() -> void: reactor_flash_small(at, v, 5.0),
		func() -> void:
			var holes: Array[Vector3] = [at + Vector3.UP]
			cabin(_warm_anchor, at, holes, 0.3),
		func() -> void: burn(_warm_anchor, Vector3.ZERO, Vector3.FORWARD, 0.3),
		func() -> void:
			var tw := create_tween()
			tw.tween_interval(4.0)
			tw.tween_callback(_warm_anchor.queue_free),
	]


func drill_in(at: Vector3, direction: Vector3, velocity: Vector3, radius: float, anchor: Node3D) -> void:
	var back := -direction.normalized()
	_spray(at, back, velocity, 45, 70.0, 60.0, 0.15, 0.55, radius * 0.05, 180.0)
	_vapour(at + back * radius * 0.5, back, velocity, 8, 20.0, radius * 1.5, radius * 6.0, 0.3, Color(1.0, 0.7, 0.45, 0.22), 40.0)
	if anchor != null:
		_add_light(anchor, at, radius * 8.0, 3.0, 9.0)


## The beam came out of the far side at `at`: a cone of molten spray and vapour.
func blow_out(at: Vector3, direction: Vector3, velocity: Vector3, radius: float, anchor: Node3D) -> void:
	var dir := direction.normalized()
	_spray(at, dir, velocity, 90, 28.0, 70.0, 0.2, 0.8, radius * 0.06, 240.0)
	_vapour(at, dir, velocity, 12, 18.0, radius * 1.8, radius * 8.0, 0.35, Color(1.0, 0.6, 0.35, 0.28), 60.0)
	if anchor != null:
		_add_light(anchor, at, radius * 8.0, 2.5, 7.0)


## Something went off inside: steam (a tank cell), stores (an E-pac, shells), electronics.
func burst(at: Vector3, velocity: Vector3, radius: float, kind: StringName) -> void:
	var pm := ProjectileManager.of(self)
	match kind:
		&"steam":
			# Water into vacuum flashes to vapour and ice at once: a thin haze racing out,
			# gone in under a second.
			pm.flash(at, Color(1.0, 0.9, 0.8), radius * 0.3, radius * 1.2, 0.12, 6.0, 1.0, radius * 8.0, velocity, 1.0)
			_vapour(at, Vector3.ZERO, velocity, 6, 180.0, radius * 3.0, radius * 22.0, 0.7, Color(0.92, 0.95, 1.0, 0.1), radius * 40.0)
		&"minovsky":
			# Ruptured Minovsky lines: a pink-white flash, a small fireball, arcs and heavy
			# smoke rolling out (fiction: it lingers).
			pm.flash(at, Color(1.0, 0.85, 0.95), radius * 0.3, radius * 1.6, 0.14, 9.0, 1.2, radius * 12.0, velocity, 1.0)
			pm.explode(at, velocity, radius * 1.3, Color(1.0, 0.5, 0.35))
			_arc(at, velocity, radius * 2.2, 0.45)
			_arc(at, velocity, radius * 1.6, 0.6)
			_spray(at, Vector3.ZERO, velocity, 70, 180.0, 30.0, 0.2, 0.9, 0.05, 90.0)
			_smoke(at, velocity, radius, 3.5)
		&"stores":
			pm.explode(at, velocity, radius * 1.4, Color(1.0, 0.55, 0.25))
			_spray(at, Vector3.ZERO, velocity, 70, 180.0, 60.0, 0.3, 1.2, 0.05, 120.0)
			_vapour(at, Vector3.ZERO, velocity, 20, 180.0, radius * 0.8, radius * 4.0, 1.2, Color(0.7, 0.62, 0.55, 0.4), radius * 6.0)
		_:
			_arc(at, velocity, radius * 2.0, 0.35)
			_arc(at, velocity, radius * 1.5, 0.45)
			pm.flash(at, Color(0.7, 0.8, 1.0), radius * 0.3, radius * 1.4, 0.15, 5.0, 0.6, radius * 10.0, velocity, 1.0)
			_spray(at, Vector3.ZERO, velocity, 40, 180.0, 25.0, 0.15, 0.6, 0.05, 40.0)
			_vapour(at, Vector3.ZERO, velocity, 8, 180.0, radius, radius * 3.0, 0.8, Color(0.55, 0.55, 0.6, 0.3), radius * 3.0)


## An I-field took a beam at `at`: it disperses in a flash and a fan of sparks, and the
## shield's anti-beam coating boils off as smoke.
func i_field(at: Vector3, outward: Vector3, velocity: Vector3, color: Color) -> void:
	var pm := ProjectileManager.of(self)
	var hot := color.lerp(Color.WHITE, 0.6)
	pm.flash(at, hot, 1.5, 7.0, 0.18, 14.0, 2.0, 70.0, velocity, 1.0)
	pm.flash(at, color, 3.0, 9.0, 0.6, 3.0, 0.8, 0.0, velocity)
	_spray(at, outward, velocity, 220, 80.0, 60.0, 0.15, 0.7, 0.05, 220.0)
	_vapour(at, outward, velocity, 26, 60.0, 1.5, 9.0, 2.6, Color(0.42, 0.4, 0.38, 0.55), 8.0)
	# The coating burning off: a lot of thick smoke rolling off the face.
	_smoke(at, velocity, 2.2, 5.0)


## Water venting from a hole on `anchor` (it rides it): a jet of vapour and ice along
## `local_dir` for `seconds`; `strength` 1 = a cell emptying, ~0.2 = a leaking line.
func vent(anchor: Node3D, local_at: Vector3, local_dir: Vector3, seconds: float, strength: float,
		color := Color(0.97, 0.98, 1.0), opacity := 0.12) -> void:
	if strength > 0.5:
		# The cell empties in a fraction of a second: one burst of mist and ice.
		var at := anchor.global_transform * local_at
		var dir := (anchor.global_basis * local_dir).normalized()
		_vapour(at, dir, Vector3.ZERO, 8, 30.0, 2.0, 16.0, 0.8, Color(0.96, 0.98, 1.0, 0.14), 90.0)
		_glints(at, Vector3.ZERO, 60, 20.0, 1.2)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * lerpf(0.9, 1.8, strength)
	var p := GPUParticles3D.new()
	p.amount = roundi(lerpf(60.0, 120.0, strength))
	p.lifetime = lerpf(0.5, 0.9, strength)
	p.local_coords = false
	p.draw_pass_1 = quad
	p.material_override = _vapour_material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.FORWARD
	m.spread = lerpf(6.0, 14.0, strength)
	m.initial_velocity_min = lerpf(8.0, 22.0, strength)
	m.initial_velocity_max = lerpf(15.0, 40.0, strength)
	m.gravity = Vector3.ZERO
	m.angle_min = 0.0
	m.angle_max = 360.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(1.0, 4.0))
	curve.max_value = 4.0
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, opacity))
	g.set_color(1, Color(color.r * 0.93, color.g * 0.95, color.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.add_to_group(ATTACHED_GROUP)
	anchor.add_child(p)
	p.position = local_at
	p.basis = Basis.looking_at(local_dir, Vector3.UP if absf(local_dir.y) < 0.95 else Vector3.RIGHT)
	p.emitting = true
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false)
	get_tree().create_timer(seconds + p.lifetime + 0.5).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## A fragment striking armour at `at` (flying `dir`) after `delay` s: a hot spark splash.
func fragment_strike(at: Vector3, dir: Vector3, velocity: Vector3, delay: float) -> void:
	var go := func() -> void:
		ProjectileManager.of(self).flash(at, Color(1.0, 0.75, 0.45), 0.15, 0.6, 0.12, 6.0, 0.2, 0.0, velocity, 1.0)
		_spray(at, -dir, velocity, 10, 70.0, 20.0, 0.1, 0.35, 0.025, 60.0)
	if delay <= 0.0:
		go.call()
	else:
		get_tree().create_timer(delay).timeout.connect(go)


## A beam through the cockpit, seen from the seat. `anchor` is the capsule (everything rides it,
## in its frame); `at` where the beam passed closest to the pilot, `holes` where it holed the
## capsule (world). Sparks off every panel it touched, the air blasting out of the holes as fog,
## then insulation burning at the holes' edges and smoke drawn out through them, `seconds` s.
func cabin(anchor: Node3D, at: Vector3, holes: Array[Vector3], seconds: float) -> void:
	var to_local := anchor.global_transform.affine_inverse()
	var c := to_local * at
	var sparks := _cabin_emitter(&"spray", anchor, c, 160, 1.4, true)
	sparks.mat.direction = Vector3.UP
	sparks.mat.spread = 180.0
	sparks.mat.initial_velocity_min = 2.0
	sparks.mat.initial_velocity_max = 14.0
	sparks.mat.lifetime_randomness = 0.7
	sparks.mat.scale_min = 0.004
	sparks.mat.scale_max = 0.012
	sparks.mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sparks.mat.emission_sphere_radius = 0.45
	var cool := _cooling_ramp().gradient
	sparks.ramp.offsets = cool.offsets
	sparks.ramp.colors = cool.colors
	for h in holes:
		var hl := to_local * h
		var out := (hl - c).normalized()
		var air := _cabin_emitter(&"vapour", anchor, c, 18, 0.9, true)
		_puffs(air, out, 25.0, 4.0, 14.0, 0.15, 1.3, Color(0.9, 0.92, 0.95, 0.22))
		var fire := _cabin_emitter(&"fire", anchor, hl - out * 0.12, 40, 0.45, false)
		_puffs(fire, -out, 70.0, 0.15, 0.7, 0.05, 0.24, Color(1.0, 0.75, 0.35, 0.9))
		fire.mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		fire.mat.emission_sphere_radius = 0.3
		fire.ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		fire.ramp.colors = PackedColorArray([Color(1.0, 0.8, 0.45, 0.9), Color(1.0, 0.4, 0.08, 0.6), Color(0.4, 0.05, 0.0, 0.0)])
		var smoke := _cabin_emitter(&"vapour", anchor, hl - out * 0.35, 24, 3.0, false)
		_puffs(smoke, out, 40.0, 0.1, 0.5, 0.15, 0.9, Color(0.13, 0.12, 0.11, 0.4))
		smoke.mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		smoke.mat.emission_sphere_radius = 0.35
		for e in [fire, smoke]:
			_stop_later(e.node, seconds * randf_range(0.7, 1.0))


## Something shot through is burning inside (lines, electronics) at `local_at` on `anchor` (it
## rides it), the channel running along `local_axis`: flames in the hole, thick dark smoke
## pouring out of both ends and drifting off (it hides what is behind it, from the sensors too),
## a flickering light, for `seconds`, till it burns out.
func burn(anchor: Node3D, local_at: Vector3, local_axis: Vector3, seconds: float, size := 1.0) -> void:
	var axis := local_axis.normalized()
	var flames := _attached_emitter(&"fire", anchor, local_at, 36, 0.4, false)
	_puffs(flames, axis, 180.0, 0.5 * size, 2.0 * size, 0.25 * size, 0.9 * size, Color(1.0, 0.75, 0.35, 0.85))
	flames.mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	flames.mat.emission_sphere_radius = 0.35 * size
	flames.ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	flames.ramp.colors = PackedColorArray([Color(1.0, 0.8, 0.45, 0.85), Color(1.0, 0.38, 0.07, 0.55), Color(0.35, 0.04, 0.0, 0.0)])
	# The flames ride the part (a burning piece blown off takes them along); its smoke trails.
	_stop_later(flames.node, seconds)
	for side in [1.0, -1.0]:
		# Grey: lit by the sun it shows against space, in shadow it is dark.
		var smoke := _attached_emitter(&"vapour", anchor, local_at + axis * side * 0.6 * size, 44, 7.0, false)
		_puffs(smoke, axis * side, 35.0, 1.0 * size, 3.5 * size, 0.6 * size, 6.0 * size, Color(0.4, 0.38, 0.36, 0.6))
		smoke.mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		smoke.mat.emission_sphere_radius = 0.3 * size
		smoke.node.local_coords = false
		_stop_later(smoke.node, seconds * 1.2)
	_add_light(anchor, anchor.global_transform * local_at, 7.0 * size, 1.6, seconds)
	_lights[-1].fire = true


## A one-off emitter on `anchor` (local frame, `at`) for the cabin: freed after it is done.
func _cabin_emitter(kind: StringName, anchor: Node3D, at: Vector3, amount: int, lifetime: float,
		one_shot: bool) -> Pooled:
	var e := _attached_emitter(kind, anchor, at, amount, lifetime, one_shot)
	e.node.layers = Layers.COCKPIT | Layers.VEHICLE_EXT
	return e


## A one-off emitter riding `anchor` (local frame, `at`): freed after it is done, or on repair.
func _attached_emitter(kind: StringName, anchor: Node3D, at: Vector3, amount: int, lifetime: float,
		one_shot: bool) -> Pooled:
	var e := _new_emitter(kind, amount, anchor)
	var p := e.node
	p.add_to_group(ATTACHED_GROUP)
	p.local_coords = true
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.lifetime = lifetime
	p.position = at
	p.emitting = true
	if one_shot:
		_stop_later(p, 0.0)
	return e


## Puffs along `dir` (spread deg) at `speed_min`..`speed_max` m/s, swelling `from` → `to` m.
func _puffs(e: Pooled, dir: Vector3, spread: float, speed_min: float, speed_max: float,
		from: float, to: float, color: Color) -> void:
	var m := e.mat
	m.direction = dir
	m.spread = spread
	m.initial_velocity_min = speed_min
	m.initial_velocity_max = speed_max
	m.damping_min = speed_min * 0.5
	m.damping_max = speed_max * 0.5
	m.scale_min = from
	m.scale_max = from
	e.curve.clear_points()
	e.curve.max_value = maxf(to / from, 1.0)
	e.curve.add_point(Vector2(0.0, 1.0))
	e.curve.add_point(Vector2(1.0, to / from))
	e.ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	e.ramp.colors = PackedColorArray([color, Color(color.r, color.g, color.b, color.a * 0.7), Color(color.r, color.g, color.b, 0.0)])


## Stops `p` emitting after `after` s (a one-shot stops on its own) and frees it once its last
## particles are gone.
func _stop_later(p: GPUParticles3D, after: float) -> void:
	var tree := get_tree()
	if after > 0.0:
		tree.create_timer(after).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.emitting = false)
	tree.create_timer(after + p.lifetime + 0.5).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())


## Smoke rolling out of a burst: dark, swelling and lingering for `life` s.
func _smoke(at: Vector3, velocity: Vector3, radius: float, life: float) -> void:
	_vapour(at, Vector3.ZERO, velocity, 14, 180.0, radius * 3.5, radius * 12.0, life,
			Color(0.16, 0.14, 0.13, 0.6), radius * 3.0)
	_vapour(at, Vector3.ZERO, velocity, 6, 180.0, radius * 2.5, radius * 7.0, life * 0.5,
			Color(0.45, 0.32, 0.26, 0.45), radius * 2.0)


## Smoke leaking from a cut line on `anchor` (it rides it) along `local_dir` for `seconds`.
func smoke_leak(anchor: Node3D, local_at: Vector3, local_dir: Vector3, seconds: float) -> void:
	vent(anchor, local_at, local_dir, seconds, 0.35, Color(0.18, 0.16, 0.15), 0.45)


## A weakened limb straining at its wound (`size` its width): sparks and a crackle of arcs.
func creak(at: Vector3, velocity: Vector3, size: float) -> void:
	_arc(at, velocity, size * 0.5, 0.25)
	_spray(at, Vector3.ZERO, velocity, 30, 180.0, 8.0, 0.2, 0.7, 0.03, 30.0)


## A limb tore off at `at`.
func sever(at: Vector3, velocity: Vector3) -> void:
	_spray(at, Vector3.ZERO, velocity, 80, 180.0, 30.0, 0.3, 1.5, 0.06, 40.0)
	_arc(at, velocity, 2.5, 0.8)
	_arc(at, velocity, 2.0, 1.2)
	ProjectileManager.of(self).flash(at, Color(1.0, 0.7, 0.4), 1.0, 4.0, 0.25, 6.0, 1.0, 40.0, velocity, 1.0)


## Where a limb tore off, on `anchor` (it rides it): a stub of the inner frame (the joint's
## drum, broken struts glowing at their ends) and torn cables that spark for a while. `axis`
## points out of the stump; `radius` is the part's. Returns the stub's root node.
func stump(anchor: Node3D, at: Vector3, axis: Vector3, radius: float, velocity: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Stump"
	anchor.add_child(root)
	var up := axis.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	root.global_transform = Transform3D(Basis(side, up, side.cross(up)), at)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.11, 0.11, 0.12)
	metal.metallic = 0.85
	metal.roughness = 0.45
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(0.08, 0.06, 0.05)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.35, 0.06)
	hot.emission_energy_multiplier = 3.0
	# The joint's drum, across the joint.
	var drum := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.45
	cyl.bottom_radius = radius * 0.45
	cyl.height = radius * 1.3
	cyl.radial_segments = 14
	cyl.material = metal
	drum.mesh = cyl
	drum.rotation = Vector3(0.0, 0.0, PI * 0.5)
	root.add_child(drum)
	# Struts and actuator rods snapped off at different lengths, glowing where they broke.
	for i in 4:
		var strut := MeshInstance3D.new()
		var rod := CylinderMesh.new()
		# Short: broken off at the socket, not standing out where the limb was.
		var length := radius * randf_range(0.25, 0.6)
		rod.top_radius = radius * randf_range(0.08, 0.16)
		rod.bottom_radius = rod.top_radius
		rod.height = length
		rod.radial_segments = 8
		rod.material = metal
		strut.mesh = rod
		var ang := TAU * (i + randf() * 0.5) / 4.0
		var off := Vector3(cos(ang), 0.0, sin(ang)) * radius * 0.45
		strut.position = off + Vector3(0.0, length * 0.5, 0.0)
		strut.rotation = Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35))
		root.add_child(strut)
		var tip := MeshInstance3D.new()
		var cap := SphereMesh.new()
		cap.radius = rod.top_radius * 1.3
		cap.height = cap.radius * 1.4
		cap.radial_segments = 8
		cap.rings = 4
		cap.material = hot
		tip.mesh = cap
		tip.position = Vector3(0.0, length * 0.5, 0.0)
		strut.add_child(tip)
	# Cut cable bundles: limp, swaying a little, sparking at their ends.
	var cables := MeshInstance3D.new()
	cables.mesh = ImmediateMesh.new()
	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.05, 0.05, 0.05)
	cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cables.material_override = cable_mat
	root.add_child(cables)
	var stub := Stub.new()
	stub.root = root
	stub.cables = cables
	stub.hot = hot
	stub.radius = radius
	for i in 5:
		var ang := TAU * randf()
		stub.cable_base.append(Vector3(cos(ang), 0.0, sin(ang)) * radius * randf_range(0.1, 0.5))
		stub.cable_dir.append((Vector3(randfn(0, 0.5), 1.0, randfn(0, 0.5))).normalized() * radius * randf_range(0.35, 0.8))
	_stubs.append(stub)
	_spray(at, up, velocity, 40, 40.0, 10.0, 0.2, 0.6, 0.03, 40.0)
	return root


## The reactor gave way: a bright clean sphere ~200 m across, mostly light.
func reactor_flash(at: Vector3, velocity: Vector3) -> void:
	var pm := ProjectileManager.of(self)
	ProjectileManager.world_sized(pm.flash(at, Color(1.0, 0.98, 0.95), 20.0, 260.0, 0.35, 30.0, 6.0, 4000.0, velocity, 1.0))
	ProjectileManager.world_sized(pm.ball(at, velocity, 200.0, 3.2, Color(1.0, 0.85, 0.6), 0.0, 5.0, 3000.0))
	ProjectileManager.world_sized(pm.ball(at, velocity, 120.0, 1.6, Color(1.0, 0.95, 0.9), 0.05, 3.0, 0.0))
	_spray(at, Vector3.ZERO, velocity, 400, 180.0, 160.0, 0.6, 3.0, 0.6, 260.0)


## A small reactor (a drone's core) going up: a ball of light `size` m in radius.
func reactor_flash_small(at: Vector3, velocity: Vector3, size: float) -> void:
	var pm := ProjectileManager.of(self)
	pm.flash(at, Color(1.0, 0.97, 0.92), size * 0.1, size * 1.2, 0.25, 20.0, 4.0, size * 15.0, velocity, 1.0)
	pm.ball(at, velocity, size, 2.0, Color(1.0, 0.82, 0.55), 0.0, 3.5, size * 10.0)
	_spray(at, Vector3.ZERO, velocity, 200, 180.0, 60.0, 0.5, 2.2, 0.3, 160.0)


# --- Pieces ---

## Pooled one-shot emitters, by kind and particle-count bucket: a hit used to make new
## particle nodes, process materials, gradient textures and quads for every puff, a flood of
## render-thread work that stalled frames for tens of ms. Each pooled emitter owns its
## material, ramp and curve textures and is reconfigured in place.
class Pooled:
	var node: GPUParticles3D
	var mat: ParticleProcessMaterial
	var ramp: Gradient
	var curve: Curve
	var busy_until := 0.0
	var tween: Tween

const BUCKETS := [16, 32, 64, 128, 256, 512]
var _pool := {}   ## [kind, bucket] → Array[Pooled]
var _now := 0.0


func _emitter(kind: StringName, at: Vector3, amount: int, lifetime: float) -> Pooled:
	var bucket: int = BUCKETS[-1]
	for b in BUCKETS:
		if amount <= b:
			bucket = b
			break
	var key := [kind, bucket]
	var list: Array = _pool.get(key, [])
	var e: Pooled = null
	for c: Pooled in list:
		if c.busy_until <= _now:
			e = c
			break
	if e == null:
		e = _new_emitter(kind, bucket)
		list.append(e)
		_pool[key] = list
	var p := e.node
	if e.tween != null and e.tween.is_valid():
		e.tween.kill()
	e.tween = null
	p.local_coords = false
	p.amount_ratio = clampf(float(amount) / bucket, 0.0, 1.0)
	p.lifetime = lifetime
	p.global_position = at
	p.visible = true
	p.restart()
	p.emitting = true
	e.busy_until = _now + lifetime + 0.5
	return e


func _new_emitter(kind: StringName, bucket: int, parent: Node = null) -> Pooled:
	var e := Pooled.new()
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = bucket
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-300, -300, -300), Vector3(600, 600, 600))
	p.emitting = false
	var quad := QuadMesh.new()
	var m := ParticleProcessMaterial.new()
	m.gravity = Vector3.ZERO
	e.ramp = Gradient.new()
	var gt := GradientTexture1D.new()
	gt.gradient = e.ramp
	m.color_ramp = gt
	match kind:
		&"spray":
			quad.size = Vector2(1.0, 12.0)
			p.material_override = _spark_material
			p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
			m.inherit_velocity_ratio = 0.0
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			var cool := _cooling_ramp().gradient
			e.ramp.offsets = cool.offsets
			e.ramp.colors = cool.colors
		&"vapour":
			quad.size = Vector2.ONE
			p.material_override = _vapour_material
			e.curve = Curve.new()
			var ct := CurveTexture.new()
			ct.curve = e.curve
			m.scale_curve = ct
			m.angle_min = 0.0
			m.angle_max = 360.0
		&"fire":
			# Flames: the glints' additive look on swelling puffs (the vapour's motion).
			quad.size = Vector2.ONE
			p.material_override = _glint_material
			e.curve = Curve.new()
			var ct := CurveTexture.new()
			ct.curve = e.curve
			m.scale_curve = ct
			m.angle_min = 0.0
			m.angle_max = 360.0
		_:
			quad.size = Vector2.ONE * 0.05
			p.material_override = _glint_material
			m.direction = Vector3.UP
			m.spread = 180.0
			m.scale_min = 0.5
			m.scale_max = 1.6
	p.draw_pass_1 = quad
	p.process_material = m
	e.node = p
	e.mat = m
	(parent if parent != null else self).add_child(p)
	return e


## Molten droplets: streaks that cool white → orange → red and go dark.
func _spray(at: Vector3, dir: Vector3, velocity: Vector3, amount: int, spread: float, speed: float,
		life_min: float, life_max: float, size: float, speed_max: float) -> void:
	var e := _emitter(&"spray", at, amount, life_max)
	var m := e.mat
	var w := maxf(size, 0.02)
	m.direction = dir if dir.length_squared() > 0.0 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed
	m.initial_velocity_max = speed_max
	m.lifetime_randomness = 1.0 - life_min / life_max
	m.scale_min = 0.3 * w
	m.scale_max = 1.0 * w
	m.emission_sphere_radius = maxf(size * 2.0, 0.1)
	_carry(e, velocity)


## Vapour or steam: soft puffs that swell and thin out fast (vacuum).
func _vapour(at: Vector3, dir: Vector3, velocity: Vector3, amount: int, spread: float,
		size_from: float, size_to: float, life: float, color: Color, speed: float) -> void:
	var e := _emitter(&"vapour", at, amount, life)
	var m := e.mat
	m.direction = dir if dir.length_squared() > 0.0 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed * 0.3
	m.initial_velocity_max = speed
	m.damping_min = speed * 0.4
	m.damping_max = speed * 0.9
	m.scale_min = size_from
	m.scale_max = size_from
	var grow := size_to / maxf(size_from, 0.01)
	e.curve.clear_points()
	e.curve.max_value = maxf(grow, 1.0)
	e.curve.add_point(Vector2(0.0, 1.0))
	e.curve.add_point(Vector2(1.0, grow))
	e.ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	e.ramp.colors = PackedColorArray([color, Color(color.r, color.g, color.b, color.a * 0.6), Color(color.r, color.g, color.b, 0.0)])
	_carry(e, velocity)


## Hydrogen / water ice crystals glittering in the light.
func _glints(at: Vector3, velocity: Vector3, amount: int, reach: float, life: float, tint := Color(1, 1, 1)) -> void:
	var e := _emitter(&"glints", at, amount, life)
	var m := e.mat
	m.initial_velocity_min = reach * 0.15
	m.initial_velocity_max = reach * 0.6
	m.damping_min = reach * 0.1
	m.damping_max = reach * 0.3
	e.ramp.offsets = PackedFloat32Array([0.0, 1.0])
	e.ramp.colors = PackedColorArray([Color(tint.r, tint.g, tint.b, 1), Color(tint.r * 0.8, tint.g * 0.9, tint.b, 0.0)])
	_carry(e, velocity)


## Particles keep the velocity of whatever threw them: they ride an emitter that flies on at
## that velocity (local coordinates), so a suit that boosts away leaves them behind.
func _carry(e: Pooled, velocity: Vector3) -> void:
	if velocity.length_squared() < 0.01:
		return
	var p := e.node
	p.local_coords = true
	e.tween = p.create_tween()
	e.tween.tween_property(p, "global_position", p.global_position + velocity * (p.lifetime + 0.5), p.lifetime + 0.5)


static func _cooling_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	g.set_color(1, Color(0.25, 0.02, 0.0, 0.0))
	g.add_point(0.15, Color(1.0, 0.7, 0.3, 1.0))
	g.add_point(0.45, Color(1.0, 0.3, 0.05, 0.9))
	g.add_point(0.75, Color(0.6, 0.08, 0.01, 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _soft_texture(hard: bool) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35 if hard else 0.1, Color(1, 1, 1, 0.8 if hard else 0.7))
	t.gradient = g
	return t


## A wisp of gas: soft round falloff broken up by noise, so overlapping puffs read as one
## cloud, not a heap of balls. Baked to a file.
const SMOKE_PUFF := preload("res://Entities/Vehicles/Components/Damage/Shader/smoke_puff.png")


static func _puff_texture() -> Texture2D:
	return SMOKE_PUFF


func _add_light(anchor: Node3D, at: Vector3, light_range: float, energy: float, life: float) -> void:
	if _lights.size() >= MAX_LIGHTS:
		_free_light(_lights[0].light)
		_lights.remove_at(0)
	var h := HoleLight.new()
	h.light = _take_light()
	h.light.omni_range = light_range
	h.light.light_energy = energy
	h.anchor = anchor
	h.local = anchor.global_transform.affine_inverse() * at
	h.energy = energy
	h.life = life
	h.light.global_position = at
	_lights.append(h)


var _spare_lights: Array[OmniLight3D] = []


## Hole lights are kept and reused: making and freeing lights on every hit stalled the
## render thread for ~35 ms at a time.
func _take_light() -> OmniLight3D:
	var l: OmniLight3D
	if not _spare_lights.is_empty():
		l = _spare_lights.pop_back()
	else:
		l = OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.5
		add_child(l)
	l.visible = true
	return l


func _free_light(l: OmniLight3D) -> void:
	l.visible = false
	l.light_energy = 0.0
	_spare_lights.append(l)


func _arc(at: Vector3, velocity: Vector3, size: float, life: float) -> void:
	var a := Arc.new()
	a.mesh = MeshInstance3D.new()
	a.mesh.mesh = ImmediateMesh.new()
	a.mesh.material_override = _arc_material
	a.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(a.mesh)
	a.centre = at
	a.size = size
	a.life = life
	a.velocity = velocity
	_arcs.append(a)
	_draw_arc(a)


func _draw_cables(st: Stub) -> void:
	var im := st.cables.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in st.cable_base.size():
		var sway := Vector3(sin(st.age * 1.3 + k), 0.0, cos(st.age * 1.1 + k * 2.0)) * st.radius * 0.12
		var prev := st.cable_base[k]
		for j in range(1, 7):
			var f := j / 6.0
			var p := st.cable_base[k] + st.cable_dir[k] * f + sway * f * f
			for o in [Vector3.ZERO, Vector3(0.03, 0.0, 0.0), Vector3(0.0, 0.0, 0.03)]:
				im.surface_add_vertex(prev + o)
				im.surface_add_vertex(p + o)
			prev = p
	im.surface_end()


## A few jagged bolts crackling between points around the arc's centre, redrawn each frame.
func _draw_arc(a: Arc) -> void:
	var im := a.mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if randf() < 0.25:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for bolt in 3:
		var p := Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * a.size * 0.3
		var q := Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * a.size * 0.6
		var prev := p
		for k in range(1, 8):
			var next := p.lerp(q, k / 7.0) + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * a.size * 0.08
			im.surface_add_vertex(prev)
			im.surface_add_vertex(next)
			prev = next
	im.surface_end()
	a.mesh.global_position = a.centre
