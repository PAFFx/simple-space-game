class_name ProjectileManager
extends Node3D

## Flies every shot in the scene and draws it: beams, bullets and missiles (ProjectileSpec).
## Shots are plain data stepped each physics tick with a swept ray, so a fast bolt can't
## pass through a thin target between ticks; nothing is hit-scan. Whatever a shot hits gets
## `apply_hit(damage, position, direction, source)` called on the collider or the nearest
## ancestor that has it. Missiles burst near anything in the `damageable` group.
##
## One manager per scene, made on first use: ProjectileManager.of(node).
## Drawing: each shot is a camera-facing strip (beam.gdshader) placed every rendered frame
## from the shot's state, plus a glow at its head; flashes and sparks mark muzzles and
## impacts. sample_glow() tells a cockpit how much nearby beams light it up.

const GROUP := &"projectile_manager"
const DAMAGEABLE := &"damageable"
const MAX_LIGHTS := 6
const MAX_SPARKS := 6
const STRIP_SEGMENTS := 24
## Missiles can't burst this soon after launch, s.
const FUSE_ARM_TIME := 0.35

class Shot:
	var spec: ProjectileSpec
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var thrust_dir := Vector3.ZERO
	var flown := 0.0
	var age := 0.0
	var dead := false
	var dead_time := 0.0
	var exclude: Array[RID] = []
	var source: Node
	var strip: MeshInstance3D
	var head: MeshInstance3D
	var seed := 0.0

class Flash:
	var sprite: MeshInstance3D
	var light: OmniLight3D
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var color := Color.WHITE
	var age := 0.0
	var duration := 0.2
	var size_from := 1.0
	var size_to := 2.0
	var intensity := 1.0
	var glow := 0.0
	var light_energy := 0.0
	var light_range := 0.0

signal shot_hit(spec: ProjectileSpec, position: Vector3, collider: Node)

var _shots: Array[Shot] = []
var _flashes: Array[Flash] = []
var _strip_mesh: ArrayMesh
var _quad_mesh: QuadMesh
var _strip_pool: Array[MeshInstance3D] = []
var _sprite_pool: Array[MeshInstance3D] = []
var _light_pool: Array[OmniLight3D] = []
var _sparks: Array[GPUParticles3D] = []
var _next_sparks := 0


## The scene's manager, or null if nothing has been fired yet.
static func find(node: Node) -> ProjectileManager:
	return node.get_tree().get_first_node_in_group(GROUP) as ProjectileManager


## The scene's manager, made on first use.
static func of(node: Node) -> ProjectileManager:
	var manager := find(node)
	if manager == null:
		manager = ProjectileManager.new()
		manager.name = "ProjectileManager"
		var tree := node.get_tree()
		(tree.current_scene if tree.current_scene != null else tree.root).add_child(manager)
	return manager


func _init() -> void:
	add_to_group(GROUP)
	# Everything here is placed each frame from the shots' own state.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# After the vehicles and weapons have moved this tick.
	process_physics_priority = 20


func _ready() -> void:
	_build_meshes()
	for i in MAX_LIGHTS:
		var light := OmniLight3D.new()
		light.visible = false
		light.shadow_enabled = false
		# The cockpit is lit through its screen (sample_glow), not from outside.
		light.light_cull_mask = 0xFFFFF & ~(Layers.COCKPIT | Layers.PILOT)
		add_child(light)
		_light_pool.append(light)
	for i in MAX_SPARKS:
		_sparks.append(_make_sparks())


func get_shot_count() -> int:
	return _shots.size()


## Fires one shot. `exclude`: bodies it can't hit (the shooter's own).
func spawn(spec: ProjectileSpec, position: Vector3, velocity: Vector3, aim_dir: Vector3,
		exclude: Array[RID] = [], source: Node = null) -> void:
	var shot := Shot.new()
	shot.spec = spec
	shot.position = position
	shot.velocity = velocity
	shot.thrust_dir = aim_dir
	shot.exclude = exclude
	shot.source = source
	shot.seed = randf()
	shot.strip = _take(_strip_pool, _strip_mesh, &"beam")
	shot.strip.set_instance_shader_parameter(&"beam_color", spec.color)
	shot.strip.set_instance_shader_parameter(&"beam_width", spec.width)
	shot.strip.set_instance_shader_parameter(&"beam_bolt", spec.bolt_length)
	shot.strip.set_instance_shader_parameter(&"beam_trail", spec.trail_time)
	shot.strip.set_instance_shader_parameter(&"beam_intensity", spec.intensity)
	shot.strip.set_instance_shader_parameter(&"beam_seed", shot.seed)
	shot.head = _take(_sprite_pool, _quad_mesh, &"flash")
	shot.head.set_instance_shader_parameter(&"flash_color", spec.color)
	shot.head.set_instance_shader_parameter(&"flash_size", spec.width * 6.0)
	shot.head.set_instance_shader_parameter(&"flash_intensity", spec.intensity * 0.8)
	shot.head.set_instance_shader_parameter(&"flash_core", 0.9)
	shot.head.set_instance_shader_parameter(&"flash_rays", 0.0)
	_shots.append(shot)


## A glow that swells from size_from to size_to (radius, m) and fades over `duration`.
## glow: how strongly it lights a cockpit nearby; light_range > 0 also lights the scene.
func flash(position: Vector3, color: Color, size_from: float, size_to: float, duration: float,
		intensity: float, glow := 0.0, light_range := 0.0, velocity := Vector3.ZERO, rays := 0.0) -> void:
	var f := Flash.new()
	f.position = position
	f.velocity = velocity
	f.color = color
	f.size_from = size_from
	f.size_to = size_to
	f.duration = duration
	f.intensity = intensity
	f.glow = glow
	f.sprite = _take(_sprite_pool, _quad_mesh, &"flash")
	f.sprite.set_instance_shader_parameter(&"flash_color", color)
	f.sprite.set_instance_shader_parameter(&"flash_core", 0.6)
	f.sprite.set_instance_shader_parameter(&"flash_rays", rays)
	f.sprite.set_instance_shader_parameter(&"flash_seed", randf())
	if light_range > 0.0 and not _light_pool.is_empty():
		f.light = _light_pool.pop_back()
		f.light.light_color = color
		f.light.omni_range = light_range
		f.light_energy = intensity * 1.6
		f.light_range = light_range
		f.light.visible = true
	_flashes.append(f)
	_place_flash(f)


## Muzzle flash for a shot leaving `position`, riding along at `velocity`.
func muzzle_flash(spec: ProjectileSpec, position: Vector3, velocity: Vector3) -> void:
	flash(position, spec.color, spec.flash_size * 0.4, spec.flash_size, 0.1, spec.intensity * 0.7,
			spec.glow * 1.4, spec.flash_size * 16.0 if spec.glow >= 0.5 else 0.0, velocity, 0.25)


## Flash, afterglow and sparks where a shot lands.
func impact(spec: ProjectileSpec, position: Vector3, velocity := Vector3.ZERO, scale := 1.0) -> void:
	var size := spec.impact_size * scale
	var hot := spec.color.lerp(Color.WHITE, 0.5)
	flash(position, hot, size * 0.35, size, 0.22, spec.intensity * 1.6, spec.glow * 2.5,
			size * 7.0, velocity, 1.0)
	flash(position, spec.color, size * 0.5, size * 1.5, 0.9, spec.intensity * 0.45, spec.glow * 0.8, 0.0, velocity)
	flash(position, spec.color.darkened(0.25), size * 0.3, size * 0.5, 2.2, spec.intensity * 0.25, 0.0, 0.0, velocity)
	_emit_sparks(position, velocity, hot, size)


## Something big going up: a few staggered bursts around `position`.
func explode(position: Vector3, velocity: Vector3, size: float, color := Color(1.0, 0.62, 0.3)) -> void:
	flash(position, color.lerp(Color.WHITE, 0.6), size * 0.3, size * 1.3, 0.35, 14.0, 2.5, size * 8.0, velocity, 1.0)
	flash(position, color, size * 0.6, size * 2.0, 1.4, 5.0, 1.0, 0.0, velocity)
	flash(position, color.darkened(0.4), size * 0.5, size * 0.9, 3.0, 2.0, 0.0, 0.0, velocity)
	for i in 3:
		var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * size * 0.5
		flash(position + offset, color, size * 0.2, size * 0.8, 0.5 + 0.2 * i, 8.0, 0.5, 0.0,
				velocity + offset * 1.5)
	_emit_sparks(position, velocity, color.lerp(Color.WHITE, 0.4), size * 1.6)


## How much the shots and flashes around `at` light it up: [colour × strength, the
## direction most of it comes from (zero if dark)]. For a cockpit's glow light.
func sample_glow(at: Vector3) -> Array:
	var sum := Vector3.ZERO
	var dir := Vector3.ZERO
	for shot in _shots:
		var spec := shot.spec
		if spec.glow <= 0.0:
			continue
		var speed := maxf(shot.velocity.length(), 1.0)
		var back := -shot.velocity / speed
		var length := minf(shot.flown, speed * spec.trail_time + spec.bolt_length)
		# Nearest point of the visible wake, as a distance behind the head.
		var along := clampf((at - shot.position).dot(back), 0.0, length)
		var nearest := shot.position + back * along
		var t := clampf(along / speed / maxf(spec.trail_time, 0.01) + shot.dead_time / maxf(spec.trail_time, 0.01), 0.0, 1.0)
		var strength := (1.0 - t) * (1.0 - t)
		if not shot.dead and along < spec.bolt_length:
			strength += 1.5
		var d := nearest.distance_to(at)
		var k := spec.glow * strength / (1.0 + (d / 45.0) * (d / 45.0))
		sum += Vector3(spec.color.r, spec.color.g, spec.color.b) * k
		dir += (nearest - at).normalized() * k
	for f in _flashes:
		if f.glow <= 0.0:
			continue
		var fade := 1.0 - f.age / f.duration
		var d := f.position.distance_to(at)
		var reach := f.size_to * 6.0
		var k := f.glow * fade * fade / (1.0 + (d / reach) * (d / reach))
		sum += Vector3(f.color.r, f.color.g, f.color.b) * k
		dir += (f.position - at).normalized() * k
	return [sum, dir.normalized() if dir.length_squared() > 1e-12 else Vector3.ZERO]


func _physics_process(delta: float) -> void:
	if _shots.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	for shot in _shots:
		if shot.dead:
			shot.dead_time += delta
			continue
		var spec := shot.spec
		shot.age += delta
		if spec.acceleration > 0.0 and shot.age <= spec.burn_time:
			shot.velocity += shot.thrust_dir * spec.acceleration * delta
		var from := shot.position
		var to := from + shot.velocity * delta
		query.from = from
		query.to = to
		query.exclude = shot.exclude
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			_land(shot, hit.position, hit.collider as Node)
			continue
		if spec.fuse_radius > 0.0 and shot.age >= FUSE_ARM_TIME and _fuse(shot, from, to):
			continue
		shot.position = to
		shot.flown += from.distance_to(to)
		if shot.age >= spec.lifetime:
			if spec.blast_radius > 0.0:
				_burst(shot, shot.position, Vector3.ZERO)
			shot.dead = true
	# Drop shots whose wake has gone.
	for i in range(_shots.size() - 1, -1, -1):
		var shot := _shots[i]
		if shot.dead and shot.dead_time > shot.spec.trail_time + 0.05:
			_release(shot.strip, _strip_pool)
			_release(shot.head, _sprite_pool)
			_shots.remove_at(i)


func _process(delta: float) -> void:
	var lead := Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
	for shot in _shots:
		_place_shot(shot, lead)
	for i in range(_flashes.size() - 1, -1, -1):
		var f := _flashes[i]
		f.age += delta
		f.position += f.velocity * delta
		if f.age >= f.duration:
			_release(f.sprite, _sprite_pool)
			if f.light != null:
				f.light.visible = false
				_light_pool.append(f.light)
			_flashes.remove_at(i)
			continue
		_place_flash(f)
	for sparks in _sparks:
		if sparks.emitting and sparks.has_meta(&"velocity"):
			sparks.position += (sparks.get_meta(&"velocity") as Vector3) * delta


func _place_shot(shot: Shot, lead: float) -> void:
	var spec := shot.spec
	var speed := shot.velocity.length()
	if speed < 0.01:
		shot.strip.visible = false
		shot.head.visible = false
		return
	var dir := shot.velocity / speed
	var head := shot.position
	var flown := shot.flown
	var dead_time := 0.0
	if shot.dead:
		dead_time = shot.dead_time + lead
	else:
		head += shot.velocity * lead
		flown += speed * lead
	var length := minf(flown, speed * spec.trail_time + spec.bolt_length)
	shot.strip.visible = length > 0.05
	shot.head.visible = not shot.dead
	if length <= 0.05:
		return
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	shot.strip.transform = Transform3D(basis.scaled_local(Vector3(1.0, 1.0, length)), head)
	shot.strip.set_instance_shader_parameter(&"beam_length", length)
	shot.strip.set_instance_shader_parameter(&"beam_speed", speed)
	shot.strip.set_instance_shader_parameter(&"beam_dead", dead_time)
	shot.head.position = head


func _place_flash(f: Flash) -> void:
	var u := clampf(f.age / f.duration, 0.0, 1.0)
	# Swell fast, then settle; fade out squared.
	var size := lerpf(f.size_from, f.size_to, 1.0 - (1.0 - u) * (1.0 - u))
	var fade := (1.0 - u) * (1.0 - u)
	f.sprite.position = f.position
	f.sprite.visible = true
	f.sprite.set_instance_shader_parameter(&"flash_size", size)
	f.sprite.set_instance_shader_parameter(&"flash_intensity", f.intensity * fade)
	if f.light != null:
		f.light.position = f.position
		f.light.light_energy = f.light_energy * fade


## The shot stops at `at`, on `collider`.
func _land(shot: Shot, at: Vector3, collider: Node) -> void:
	shot.flown += shot.position.distance_to(at)
	shot.position = at
	shot.dead = true
	var velocity := _velocity_of(collider)
	if shot.spec.blast_radius > 0.0:
		_burst(shot, at, velocity)
	else:
		_damage(collider, shot.spec.damage, at, shot.velocity.normalized(), shot.source)
		impact(shot.spec, at, velocity)
	shot_hit.emit(shot.spec, at, collider)


## Bursts the missile if it passes within its fuse radius of something this tick.
func _fuse(shot: Shot, from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var len2 := seg.length_squared()
	for node in get_tree().get_nodes_in_group(DAMAGEABLE):
		var target := node as Node3D
		if target == null or target == shot.source:
			continue
		var centre := target.global_position
		var u := clampf((centre - from).dot(seg) / maxf(len2, 1e-9), 0.0, 1.0)
		var nearest := from + seg * u
		var radius: float = target.get_meta(&"hud_radius", 0.0)
		if nearest.distance_to(centre) <= shot.spec.fuse_radius + radius:
			shot.flown += from.distance_to(nearest)
			shot.position = nearest
			shot.dead = true
			_burst(shot, nearest, _velocity_of(target))
			return true
	return false


func _burst(shot: Shot, at: Vector3, velocity: Vector3) -> void:
	var spec := shot.spec
	for node in get_tree().get_nodes_in_group(DAMAGEABLE):
		var target := node as Node3D
		if target == null or target == shot.source:
			continue
		var radius: float = target.get_meta(&"hud_radius", 0.0)
		var d := maxf(target.global_position.distance_to(at) - radius, 0.0)
		if d < spec.blast_radius:
			_damage(target, spec.damage * (1.0 - d / spec.blast_radius), at,
					(target.global_position - at).normalized(), shot.source)
	explode(at, velocity, spec.impact_size * 0.5, spec.color)


static func _damage(node: Node, amount: float, at: Vector3, direction: Vector3, source: Node) -> void:
	while node != null:
		if node.has_method(&"apply_hit"):
			node.call(&"apply_hit", amount, at, direction, source)
			return
		node = node.get_parent()


static func _velocity_of(node: Node) -> Vector3:
	while node != null:
		if node is RigidBody3D:
			return (node as RigidBody3D).linear_velocity
		if node.has_method(&"get_velocity"):
			return node.call(&"get_velocity")
		node = node.get_parent()
	return Vector3.ZERO


# --- Drawing resources ---

func _build_meshes() -> void:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in STRIP_SEGMENTS + 1:
		# Finer near the head, where the bolt is.
		var z := pow(float(i) / STRIP_SEGMENTS, 2.0)
		verts.append(Vector3(-1.0, 0.0, z))
		verts.append(Vector3(1.0, 0.0, z))
		if i < STRIP_SEGMENTS:
			var k := i * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	_strip_mesh = ArrayMesh.new()
	_strip_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader widens the strip in view space: leave room for it.
	_strip_mesh.custom_aabb = AABB(Vector3(-40.0, -40.0, 0.0), Vector3(80.0, 80.0, 1.0))
	var beam := ShaderMaterial.new()
	beam.shader = preload("res://Entities/Projectiles/Shader/beam.gdshader")
	_strip_mesh.surface_set_material(0, beam)

	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2(2.0, 2.0)
	_quad_mesh.custom_aabb = AABB(Vector3(-200.0, -200.0, -200.0), Vector3(400.0, 400.0, 400.0))
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://Entities/Projectiles/Shader/flash.gdshader")
	_quad_mesh.material = glow


func _take(pool: Array[MeshInstance3D], mesh: Mesh, _kind: StringName) -> MeshInstance3D:
	var node: MeshInstance3D
	if pool.is_empty():
		node = MeshInstance3D.new()
		node.mesh = mesh
		node.layers = Layers.FX
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	else:
		node = pool.pop_back()
	node.visible = false
	return node


func _release(node: MeshInstance3D, pool: Array[MeshInstance3D]) -> void:
	node.visible = false
	pool.append(node)


func _make_sparks() -> GPUParticles3D:
	var sparks := GPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	# The burst rides along with what was hit (the emitter is moved each frame).
	sparks.local_coords = true
	sparks.explosiveness = 1.0
	sparks.amount = 90
	sparks.lifetime = 1.3
	sparks.layers = Layers.FX
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.0
	process.direction = Vector3.ZERO
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 20.0
	process.initial_velocity_max = 140.0
	process.damping_min = 30.0
	process.damping_max = 60.0
	process.scale_min = 0.5
	process.scale_max = 1.6
	var shrink := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	shrink.curve = curve
	process.scale_curve = shrink
	sparks.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	# Sparks right at the camera (a hit on the viewer's own suit) fade out.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 20.0
	mat.distance_fade_max_distance = 70.0
	mat.albedo_color = Color(2.5, 2.5, 2.5)
	mat.albedo_texture = _spark_texture()
	quad.material = mat
	sparks.draw_pass_1 = quad
	add_child(sparks)
	return sparks


static func _spark_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 32
	tex.height = 32
	return tex


func _emit_sparks(at: Vector3, velocity: Vector3, color: Color, size: float) -> void:
	var sparks := _sparks[_next_sparks]
	_next_sparks = (_next_sparks + 1) % _sparks.size()
	var process := sparks.process_material as ParticleProcessMaterial
	process.color = color
	process.emission_sphere_radius = size * 0.08
	process.initial_velocity_min = size * 1.5
	process.initial_velocity_max = size * 9.0
	process.damping_min = size * 2.0
	process.damping_max = size * 5.0
	process.scale_min = size * 0.005
	process.scale_max = size * 0.018
	sparks.position = at
	sparks.set_meta(&"velocity", velocity)
	sparks.custom_aabb = AABB(Vector3.ONE * -size * 12.0, Vector3.ONE * size * 24.0)
	sparks.restart()
	sparks.emitting = true
