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

class HoleLight:
	var light: OmniLight3D
	var anchor: Node3D
	var local := Vector3.ZERO
	var age := 0.0
	var life := 6.0
	var energy := 4.0

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
	for i in range(_lights.size() - 1, -1, -1):
		var h := _lights[i]
		h.age += delta
		if h.age >= h.life or not is_instance_valid(h.anchor):
			h.light.queue_free()
			_lights.remove_at(i)
			continue
		var k := 1.0 - h.age / h.life
		h.light.global_position = h.anchor.global_transform * h.local
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
		var length := radius * randf_range(0.5, 1.4)
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
		stub.cable_dir.append((Vector3(randfn(0, 0.5), 1.0, randfn(0, 0.5))).normalized() * radius * randf_range(0.8, 1.8))
	_stubs.append(stub)
	_spray(at, up, velocity, 40, 40.0, 10.0, 0.2, 0.6, 0.03, 40.0)
	return root


## The reactor gave way: a bright clean sphere ~200 m across, mostly light.
func reactor_flash(at: Vector3, velocity: Vector3) -> void:
	var pm := ProjectileManager.of(self)
	pm.flash(at, Color(1.0, 0.98, 0.95), 20.0, 260.0, 0.35, 30.0, 6.0, 4000.0, velocity, 1.0)
	pm.ball(at, velocity, 200.0, 3.2, Color(1.0, 0.85, 0.6), 0.0, 5.0, 3000.0)
	pm.ball(at, velocity, 120.0, 1.6, Color(1.0, 0.95, 0.9), 0.05, 3.0, 0.0)
	_spray(at, Vector3.ZERO, velocity, 400, 180.0, 160.0, 0.6, 3.0, 0.6, 260.0)


## A small reactor (a drone's core) going up: a ball of light `size` m in radius.
func reactor_flash_small(at: Vector3, velocity: Vector3, size: float) -> void:
	var pm := ProjectileManager.of(self)
	pm.flash(at, Color(1.0, 0.97, 0.92), size * 0.1, size * 1.2, 0.25, 20.0, 4.0, size * 15.0, velocity, 1.0)
	pm.ball(at, velocity, size, 2.0, Color(1.0, 0.82, 0.55), 0.0, 3.5, size * 10.0)
	_spray(at, Vector3.ZERO, velocity, 200, 180.0, 60.0, 0.5, 2.2, 0.3, 160.0)


# --- Pieces ---

func _emitter(at: Vector3, amount: int, lifetime: float, material: Material, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.draw_pass_1 = mesh
	p.material_override = material
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-300, -300, -300), Vector3(600, 600, 600))
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(p.queue_free)
	return p


## Molten droplets: streaks that cool white → orange → red and go dark.
func _spray(at: Vector3, dir: Vector3, velocity: Vector3, amount: int, spread: float, speed: float,
		life_min: float, life_max: float, size: float, speed_max: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(maxf(size, 0.02), maxf(size, 0.02) * 12.0)
	var p := _emitter(at, amount, life_max, _spark_material, quad)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var m := ParticleProcessMaterial.new()
	m.direction = dir if dir.length_squared() > 0.0 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed
	m.initial_velocity_max = speed_max
	m.gravity = Vector3.ZERO
	m.inherit_velocity_ratio = 0.0
	m.lifetime_randomness = 1.0 - life_min / life_max
	m.scale_min = 0.3
	m.scale_max = 1.0
	m.color_ramp = _cooling_ramp()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = maxf(size * 2.0, 0.1)
	p.process_material = m
	_carry(p, velocity)


## Vapour or steam: soft puffs that swell and thin out fast (vacuum).
func _vapour(at: Vector3, dir: Vector3, velocity: Vector3, amount: int, spread: float,
		size_from: float, size_to: float, life: float, color: Color, speed: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size_from
	var p := _emitter(at, amount, life, _vapour_material, quad)
	var m := ParticleProcessMaterial.new()
	m.direction = dir if dir.length_squared() > 0.0 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = speed * 0.3
	m.initial_velocity_max = speed
	m.gravity = Vector3.ZERO
	m.damping_min = speed * 0.4
	m.damping_max = speed * 0.9
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, size_to / maxf(size_from, 0.01)))
	curve.max_value = maxf(size_to / maxf(size_from, 0.01), 1.0)
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	g.add_point(0.25, Color(color.r, color.g, color.b, color.a * 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	m.angle_min = 0.0
	m.angle_max = 360.0
	p.process_material = m
	_carry(p, velocity)


## Hydrogen / water ice crystals glittering in the light.
func _glints(at: Vector3, velocity: Vector3, amount: int, reach: float, life: float, tint := Color(1, 1, 1)) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.05
	var p := _emitter(at, amount, life, _glint_material, quad)
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = reach * 0.15
	m.initial_velocity_max = reach * 0.6
	m.gravity = Vector3.ZERO
	m.damping_min = reach * 0.1
	m.damping_max = reach * 0.3
	m.scale_min = 0.5
	m.scale_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(tint.r, tint.g, tint.b, 1))
	g.set_color(1, Color(tint.r * 0.8, tint.g * 0.9, tint.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	_carry(p, velocity)


## Particles keep the velocity of whatever threw them: they ride an emitter that flies on at
## that velocity (local coordinates), so a suit that boosts away leaves them behind.
func _carry(p: GPUParticles3D, velocity: Vector3) -> void:
	if velocity.length_squared() < 0.01:
		return
	p.local_coords = true
	var tw := p.create_tween()
	tw.tween_property(p, "global_position", p.global_position + velocity * (p.lifetime + 0.5), p.lifetime + 0.5)


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
		_lights[0].light.queue_free()
		_lights.remove_at(0)
	var h := HoleLight.new()
	h.light = OmniLight3D.new()
	h.light.omni_range = light_range
	h.light.light_energy = energy
	h.light.shadow_enabled = false
	h.light.omni_attenuation = 1.5
	add_child(h.light)
	h.anchor = anchor
	h.local = anchor.global_transform.affine_inverse() * at
	h.energy = energy
	h.life = life
	h.light.global_position = at
	_lights.append(h)


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
