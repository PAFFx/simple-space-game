class_name ProjectileManager
extends Node3D

## Flies every shot in the scene and draws it: beams, bullets and missiles (ProjectileSpec).
## Shots are plain data stepped each physics tick with a swept ray, so a fast bolt can't
## pass through a thin target between ticks; nothing is hit-scan. Whatever a shot hits gets
## `apply_hit(damage, position, direction, source)` called on the collider or the nearest
## ancestor that has it. Missiles burst near anything in the `damageable` group.
##
## One manager per scene, made on first use: ProjectileManager.of(node).
## Drawing: each shot is a camera-facing strip placed every rendered frame from the
## shot's state, plus a glow at its head; flashes and sparks mark muzzles and
## impacts. sample_glow() tells a cockpit how much nearby beams light it up.
##
## A beam is one straight line of particles along the barrel (beam.gdshader). While the
## barrel pours it out (stream_from, emit_time) the whole line runs from the muzzle along
## the barrel and swings with it; its front travels at the beam's speed. Let go, the line
## flies on at that speed. Its front dissipates at the beam's range, and it leaves a short
## wake where it has passed. What it hits takes the front: the particles stop there.
## Bullets and missiles are bolts (bolt.gdshader).
## A spooling weapon shows a charge glow on its muzzle (set_charge): the dodge cue.
## Anything riding a muzzle is placed where the muzzle is drawn (physics-interpolated),
## not where it was last physics tick, so it doesn't stutter behind a moving gun.
## A beam with `energy` drills (Docs/Damage): a target with `beam_contact(BeamContact)` gets
## the energy arriving each tick and answers whether the beam is through; until then the front
## holds at the drill face, after it the line goes on from the exit with what is left.
## Explosions are balls of light.
## A shot's fire_sound plays on its muzzle (External bus): the cockpit's simulated outside sound.

const GROUP := &"projectile_manager"
const DAMAGEABLE := &"damageable"
const SOUND_BUS := &"External"
const MAX_VOICES := 8
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
	# Beams only: the line lies along `thrust_dir` from `position` (the barrel while it
	# emits), its front `reach` m along it and its tail `tail` m. prev_* are last tick's,
	# to interpolate between.
	var emitting := false
	var feed: Callable
	var muzzle: Node3D
	var mouth: MeshInstance3D
	var reach := 0.0
	var tail := 0.0
	var blocked := false
	var at_range := false
	var fizzle := 0.0
	var prev_position := Vector3.ZERO
	var prev_dir := Vector3.ZERO
	var prev_reach := 0.0
	var prev_tail := 0.0
	var hit_ids := {}
	var last_splash := -1.0
	var own_exclude := false

## One tick of a beam touching a target (beam_contact). The target fills in the result.
class BeamContact:
	var key := 0                   ## the shot (the same across its ticks)
	var point := Vector3.ZERO      ## where the beam's ray met the target's collider
	var normal := Vector3.ZERO     ## the collider's surface there
	var collider: Node
	var direction := Vector3.ZERO
	var energy := 0.0              ## J arriving at the target this tick
	var radius := 0.6              ## the hole's radius, m
	var spec: ProjectileSpec
	var source: Node
	# Result:
	var absorbed := 0.0            ## J the target took
	var through := false           ## burned through: the beam goes on from exit_point
	var exit_point := Vector3.ZERO
	var front := Vector3.ZERO      ## not through: where the front stands (the drill face)

class Charge:
	var muzzle: Node3D
	var spec: ProjectileSpec
	var level := 0.0
	var sprite: MeshInstance3D

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
	var delay := 0.0
	var ball := false
	## Rides this node (drawn position) instead of flying at `velocity`.
	var anchor: Node3D

class Voice:
	var player: AudioStreamPlayer3D
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var anchor: Node3D

signal shot_hit(spec: ProjectileSpec, position: Vector3, collider: Node)

## A charge never looks smaller than this (rad, full charge; 40% of it as it starts), and
## its camera glare at full charge (0..1): the dodge cue has to read from the receiving end.
@export var charge_min_angle: float = 0.022
@export var charge_glare: float = 1.0

var _shots: Array[Shot] = []
var _flashes: Array[Flash] = []
## Oldest first: a new sound takes a free voice, or the oldest one.
var _voices: Array[Voice] = []
var _charges := {}   # owner → Charge
var _beam_mesh: ArrayMesh
var _beam_pool: Array[MeshInstance3D] = []
var _strip_mesh: ArrayMesh
var _quad_mesh: QuadMesh
var _strip_pool: Array[MeshInstance3D] = []
var _sprite_pool: Array[MeshInstance3D] = []
var _light_pool: Array[OmniLight3D] = []
var _sparks: Array[GPUParticles3D] = []
var _next_sparks := 0
## Seconds of game time, for the charge flicker (frame-rate and time-scale true).
var _clock := 0.0


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
	var bus := SOUND_BUS if AudioServer.get_bus_index(SOUND_BUS) >= 0 else &"Master"
	for i in MAX_VOICES:
		var voice := Voice.new()
		voice.player = AudioStreamPlayer3D.new()
		voice.player.bus = bus
		add_child(voice.player)
		_voices.append(voice)


func get_shot_count() -> int:
	return _shots.size()


## Fires one shot. `exclude`: bodies it can't hit (the shooter's own).
func spawn(spec: ProjectileSpec, position: Vector3, velocity: Vector3, aim_dir: Vector3,
		exclude: Array[RID] = [], source: Node = null) -> Shot:
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
	shot.head.set_instance_shader_parameter(&"flash_size", spec.width * 7.0)
	shot.head.set_instance_shader_parameter(&"flash_intensity", spec.intensity * 0.8)
	shot.head.set_instance_shader_parameter(&"flash_core", 0.9)
	shot.head.set_instance_shader_parameter(&"flash_rays", 0.0)
	shot.head.set_instance_shader_parameter(&"flash_ball", 0.0)
	shot.head.set_instance_shader_parameter(&"flash_charge", 0.0)
	shot.head.set_instance_shader_parameter(&"flash_max_angle", 0.22)
	if spec.kind == ProjectileSpec.Kind.BEAM:
		# Swap the bolt strip for the beam's.
		_release(shot.strip, _strip_pool)
		shot.strip = _take(_beam_pool, _beam_mesh, &"beam")
		shot.strip.set_instance_shader_parameter(&"beam_color", spec.color)
		shot.strip.set_instance_shader_parameter(&"beam_width", spec.width)
		shot.strip.set_instance_shader_parameter(&"beam_intensity", spec.intensity)
		shot.strip.set_instance_shader_parameter(&"beam_seed", shot.seed)
		shot.strip.set_instance_shader_parameter(&"beam_speed", spec.speed)
		shot.strip.set_instance_shader_parameter(&"beam_trail", spec.trail_time)
		shot.prev_dir = aim_dir
		# Velocity is the frame it flies in (the shooter's); the line moves along itself.
		shot.velocity -= aim_dir * spec.speed
	_shots.append(shot)
	return shot


## Keeps a beam coming out of `muzzle` for its emit_time: `feed` returns this tick's
## [position, velocity, direction] at the barrel.
func stream_from(shot: Shot, muzzle: Node3D, feed: Callable) -> void:
	shot.emitting = true
	shot.muzzle = muzzle
	shot.feed = feed
	shot.mouth = _take(_sprite_pool, _quad_mesh, &"flash")
	shot.mouth.set_instance_shader_parameter(&"flash_color", shot.spec.color)
	shot.mouth.set_instance_shader_parameter(&"flash_core", 1.0)
	shot.mouth.set_instance_shader_parameter(&"flash_rays", 0.0)
	shot.mouth.set_instance_shader_parameter(&"flash_ball", 0.0)
	shot.mouth.set_instance_shader_parameter(&"flash_charge", 1.0)
	shot.mouth.set_instance_shader_parameter(&"flash_seed", randf())
	shot.mouth.set_instance_shader_parameter(&"flash_max_angle", 0.22)


## A weapon spooling up: a glow on `muzzle` that grows with `level` (0..1); 0 removes it.
func set_charge(owner: Object, muzzle: Node3D, spec: ProjectileSpec, level: float) -> void:
	var charge: Charge = _charges.get(owner)
	if level <= 0.0:
		if charge != null:
			_release(charge.sprite, _sprite_pool)
			_charges.erase(owner)
		return
	if charge == null:
		charge = Charge.new()
		charge.sprite = _take(_sprite_pool, _quad_mesh, &"flash")
		charge.sprite.set_instance_shader_parameter(&"flash_color", spec.color)
		charge.sprite.set_instance_shader_parameter(&"flash_core", 0.9)
		charge.sprite.set_instance_shader_parameter(&"flash_ball", 0.0)
		charge.sprite.set_instance_shader_parameter(&"flash_charge", 1.0)
		charge.sprite.set_instance_shader_parameter(&"flash_rays", 0.0)
		charge.sprite.set_instance_shader_parameter(&"flash_max_angle", 0.22)
		charge.sprite.set_instance_shader_parameter(&"flash_seed", randf())
		_charges[owner] = charge
	charge.muzzle = muzzle
	charge.spec = spec
	charge.level = level


## A glow that swells from size_from to size_to (radius, m) and fades over `duration`.
## glow: how strongly it lights a cockpit nearby; light_range > 0 also lights the scene.
func flash(position: Vector3, color: Color, size_from: float, size_to: float, duration: float,
		intensity: float, glow := 0.0, light_range := 0.0, velocity := Vector3.ZERO, rays := 0.0) -> Flash:
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
	f.sprite.set_instance_shader_parameter(&"flash_ball", 0.0)
	f.sprite.set_instance_shader_parameter(&"flash_charge", 0.0)
	f.sprite.set_instance_shader_parameter(&"flash_max_angle", 0.22)
	if light_range > 0.0 and not _light_pool.is_empty():
		f.light = _light_pool.pop_back()
		f.light.light_color = color
		f.light.omni_range = light_range
		f.light_energy = intensity * 1.6
		f.light_range = light_range
		f.light.visible = true
	_flashes.append(f)
	_place_flash(f)
	return f


## Muzzle flash for a shot leaving `position`, riding along at `velocity`, or on `anchor`
## (the muzzle) if given.
func muzzle_flash(spec: ProjectileSpec, position: Vector3, velocity: Vector3, anchor: Node3D = null) -> void:
	var f := flash(position, spec.color, spec.flash_size * 0.4, spec.flash_size, 0.1, spec.intensity * 0.7,
			spec.glow * 1.4, spec.flash_size * 16.0 if spec.glow >= 0.5 else 0.0, velocity, 0.25)
	f.anchor = anchor
	_place_flash(f)
	if spec.fire_sound != null:
		play_sound(spec.fire_sound, position, velocity, anchor, spec.fire_volume_db, spec.sound_unit_size,
				spec.sound_max_distance)


## Plays `stream` at `position`, riding along at `velocity`, or on `anchor` if given; not
## heard past `max_distance` m.
func play_sound(stream: AudioStream, position: Vector3, velocity := Vector3.ZERO, anchor: Node3D = null,
		volume_db := 0.0, unit_size := 150.0, max_distance := 2000.0) -> AudioStreamPlayer3D:
	var voice := _voices[0]
	for v in _voices:
		if not v.player.playing:
			voice = v
			break
	_voices.erase(voice)
	_voices.append(voice)
	voice.position = position
	voice.velocity = velocity
	voice.anchor = anchor
	voice.player.stream = stream
	voice.player.volume_db = volume_db
	voice.player.unit_size = unit_size
	voice.player.max_distance = max_distance
	voice.player.global_position = position
	voice.player.play()
	return voice.player


## Flash, afterglow and sparks where a shot lands.
func impact(spec: ProjectileSpec, position: Vector3, velocity := Vector3.ZERO, scale := 1.0, sparks := true) -> void:
	var size := spec.impact_size * scale
	var hot := spec.color.lerp(Color.WHITE, 0.5)
	flash(position, hot, size * 0.35, size, 0.22, spec.intensity * 1.6, spec.glow * 2.5,
			size * 7.0, velocity, 1.0)
	flash(position, spec.color, size * 0.5, size * 1.5, 0.9, spec.intensity * 0.45, spec.glow * 0.8, 0.0, velocity)
	flash(position, spec.color.darkened(0.25), size * 0.3, size * 0.5, 2.2, spec.intensity * 0.25, 0.0, 0.0, velocity)
	if sparks:
		_emit_sparks(position, velocity, hot, size)


## Something going up: a sphere of light `size` m in radius swells out of a white flash,
## and smaller balls bubble out around it one after another.
func explode(position: Vector3, velocity: Vector3, size: float, color := Color(1.0, 0.62, 0.3)) -> void:
	flash(position, Color.WHITE.lerp(color, 0.2), size * 0.1, size * 0.5, 0.18, 18.0, 3.0, size * 10.0, velocity, 1.0)
	ball(position, velocity, size, 1.1, color, 0.0, 2.5, size * 6.0)
	for i in 5:
		var offset := Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized() * size * randf_range(0.55, 0.95)
		ball(position + offset, velocity + offset * 0.4, size * randf_range(0.3, 0.55),
				randf_range(0.5, 0.8), color, 0.06 + 0.09 * i, 0.6)
	_emit_sparks(position, velocity, color.lerp(Color.WHITE, 0.4), size * 0.8)


## One sphere of light: swells to `radius` (m) white-hot, holds, takes on `color` and fades.
func ball(position: Vector3, velocity: Vector3, radius: float, duration: float, color: Color,
		delay := 0.0, glow := 0.0, light_range := 0.0) -> void:
	# The ball's edge sits at 0.84 of the sprite's radius; the rest is its halo.
	var f := flash(position, color, radius * 0.25 / 0.84, radius / 0.84, duration, 6.0, glow,
			light_range, velocity)
	f.ball = true
	f.delay = delay
	f.sprite.set_instance_shader_parameter(&"flash_ball", 1.0)
	f.sprite.set_instance_shader_parameter(&"flash_max_angle", 0.9)
	_place_flash(f)


## How much the shots and flashes around `at` light it up: [colour × strength, the
## direction most of it comes from (zero if dark)]. For a cockpit's glow light.
func sample_glow(at: Vector3) -> Array:
	var sum := Vector3.ZERO
	var dir := Vector3.ZERO
	for shot in _shots:
		var spec := shot.spec
		if spec.glow <= 0.0:
			continue
		if spec.kind == ProjectileSpec.Kind.BEAM:
			if shot.tail >= shot.reach:
				continue
			var along := clampf((at - shot.position).dot(shot.thrust_dir), shot.tail, shot.reach)
			var nearest := shot.position + shot.thrust_dir * along
			var d := nearest.distance_to(at)
			var k := spec.glow / (1.0 + (d / 70.0) * (d / 70.0))
			sum += Vector3(spec.color.r, spec.color.g, spec.color.b) * k
			dir += (nearest - at).normalized() * k
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
		var k := spec.glow * strength / (1.0 + (d / 70.0) * (d / 70.0))
		sum += Vector3(spec.color.r, spec.color.g, spec.color.b) * k
		dir += (nearest - at).normalized() * k
	for charge: Charge in _charges.values():
		if not is_instance_valid(charge.muzzle):
			continue
		var p := drawn_position(charge.muzzle)
		var d := p.distance_to(at)
		var k := charge.spec.glow * charge.level * 0.6 / (1.0 + (d / 30.0) * (d / 30.0))
		sum += Vector3(charge.spec.color.r, charge.spec.color.g, charge.spec.color.b) * k
		dir += (p - at).normalized() * k
	for f in _flashes:
		if f.glow <= 0.0 or f.age < f.delay:
			continue
		var fade := 1.0 - (f.age - f.delay) / f.duration
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
		if spec.kind == ProjectileSpec.Kind.BEAM:
			_step_beam(shot, delta, space, query)
			continue
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
		var beam := shot.spec.kind == ProjectileSpec.Kind.BEAM
		if shot.dead and (beam or shot.dead_time > shot.spec.trail_time + 0.05):
			_release(shot.strip, _beam_pool if beam else _strip_pool)
			_release(shot.head, _sprite_pool)
			if shot.mouth != null:
				_release(shot.mouth, _sprite_pool)
			_shots.remove_at(i)


func _step_beam(shot: Shot, delta: float, space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> void:
	var spec := shot.spec
	shot.age += delta
	shot.prev_position = shot.position
	shot.prev_dir = shot.thrust_dir
	shot.prev_reach = shot.reach
	shot.prev_tail = shot.tail
	if shot.emitting and not (shot.age < spec.emit_time and shot.feed.is_valid() and is_instance_valid(shot.muzzle)):
		shot.emitting = false
		if shot.mouth != null:
			_release(shot.mouth, _sprite_pool)
			shot.mouth = null
	# A free beam that ran into something, or is all used up, has no front moving on.
	var stopped := not shot.emitting and (shot.blocked or shot.tail >= shot.reach)
	if shot.emitting:
		var at: Array = shot.feed.call()
		shot.position = at[0]
		shot.thrust_dir = at[2]
		shot.velocity = (at[1] as Vector3) - shot.thrust_dir * spec.speed
	else:
		# Let go: the line flies on along itself (in the shooter's frame at release).
		shot.position += shot.velocity * delta
		shot.tail += spec.speed * delta
	var range := spec.get_range()
	if not stopped:
		shot.reach = minf(shot.reach + spec.speed * delta, range)
	shot.at_range = shot.reach >= range
	shot.fizzle = move_toward(shot.fizzle, 1.0 if shot.at_range else 0.0, delta / 0.12)
	if shot.tail >= shot.reach:
		# Gone: only its wake is left, fading.
		shot.blocked = false
		if shot.tail - spec.speed * spec.trail_time >= shot.reach:
			shot.dead = true
		return
	query.exclude = shot.exclude
	var dir := shot.thrust_dir
	var swing := shot.prev_dir.angle_to(dir) if shot.emitting else 0.0
	# A swinging barrel sweeps the line sideways: rays in between catch what it swept
	# across (they hurt it, but don't end the beam).
	var between := clampi(ceili(swing * shot.reach / 4.0), 0, 8)
	for i in between:
		var d := shot.prev_dir.slerp(dir, (i + 1.0) / (between + 1.0)).normalized()
		query.from = shot.position + d * shot.tail
		query.to = shot.position + d * shot.reach
		var swept := space.intersect_ray(query)
		if not swept.is_empty():
			_beam_hit(shot, swept.collider as Node, swept.position, d)
	# From last tick's tail: what the tail has just passed was still in the beam, so a
	# thin plate it slipped through this tick still takes the rest of it.
	query.from = shot.position + dir * minf(shot.prev_tail, shot.tail)
	query.to = shot.position + dir * shot.reach
	var hit := space.intersect_ray(query)
	shot.blocked = not hit.is_empty()
	if not shot.blocked:
		return
	var point: Vector3 = hit.position
	var collider := hit.collider as Node
	if spec.energy > 0.0 and _beam_target(collider) != null:
		_drill(shot, hit, dir, delta, space, query)
		return
	# It ends where it hit: the particles stop there.
	shot.reach = maxf(shot.position.distance_to(point), shot.tail)
	shot.at_range = false
	if not _beam_hit(shot, collider, point, dir) and shot.age - shot.last_splash > 0.06:
		shot.last_splash = shot.age
		impact(spec, point, _velocity_of(collider), 0.45)


## A beam with energy on something that drills (beam_contact): this tick's energy goes in;
## through, the line goes on from the exit with what is left and may meet the next target
## in the same tick. Not through, the front stands at the drill face.
func _drill(shot: Shot, hit: Dictionary, dir: Vector3, delta: float,
		space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D) -> void:
	var spec := shot.spec
	var left := -1.0
	for _i in 4:
		var collider := hit.collider as Node
		var point: Vector3 = hit.position
		var target := _beam_target(collider)
		if target == null:
			# Something that doesn't drill: the rest of the line stops on it.
			shot.reach = maxf(shot.position.distance_to(point), shot.tail)
			shot.at_range = false
			if not _beam_hit(shot, collider, point, dir) and shot.age - shot.last_splash > 0.06:
				shot.last_splash = shot.age
				impact(spec, point, _velocity_of(collider), 0.45)
			return
		var distance := shot.position.distance_to(point)
		if left < 0.0:
			# What reaches `distance` this tick left the barrel distance / speed earlier.
			var lag := distance / maxf(spec.speed, 1.0)
			left = spec.energy * spec.energy_share(shot.age - delta - lag, shot.age - lag)
		var c := BeamContact.new()
		c.key = shot.get_instance_id()
		c.point = point
		c.normal = hit.normal
		c.collider = collider
		c.direction = dir
		c.energy = left
		c.radius = spec.hole_radius
		c.spec = spec
		c.source = shot.source if is_instance_valid(shot.source) else null
		c.front = point
		var id := target.get_instance_id()
		var first := not shot.hit_ids.has(id)
		target.call(&"beam_contact", c)
		if first:
			shot.hit_ids[id] = true
			# A small contact flash: the target draws the drilling itself (DamageFx).
			impact(spec, point, _velocity_of(collider), 0.18, false)
			shot_hit.emit(spec, point, collider)
		if not c.through:
			shot.reach = maxf(shot.position.distance_to(c.front), shot.tail)
			shot.at_range = false
			shot.blocked = true
			return
		# Through: this body no longer stops the beam (its channel is open).
		left = maxf(left - c.absorbed, 0.0)
		if not shot.own_exclude:
			shot.exclude = shot.exclude.duplicate()
			shot.own_exclude = true
		shot.exclude.append(hit.rid)
		query.exclude = shot.exclude
		query.from = c.exit_point
		query.to = shot.position + dir * shot.reach
		hit = space.intersect_ray(query)
		if hit.is_empty():
			shot.blocked = false
			return
	shot.blocked = true


## The node that takes beam contacts for `collider` (itself or an ancestor), or null.
static func _beam_target(collider: Node) -> Node:
	var node := collider
	while node != null:
		if node.has_method(&"beam_contact"):
			return node
		if node.has_method(&"apply_hit"):
			return null
		node = node.get_parent()
	return null


## A beam touching `collider` at `point`: hurts it the first time (true), else nothing.
func _beam_hit(shot: Shot, collider: Node, point: Vector3, dir: Vector3) -> bool:
	var id := collider.get_instance_id() if collider != null else 0
	if shot.hit_ids.has(id):
		return false
	shot.hit_ids[id] = true
	_damage(collider, shot.spec.damage, point, dir, shot.source if is_instance_valid(shot.source) else null)
	impact(shot.spec, point, _velocity_of(collider))
	shot_hit.emit(shot.spec, point, collider)
	return true


## Where `node` is drawn this frame: between the last two physics ticks, like the suit
## carrying it, rather than where it was at the last one.
static func drawn_position(node: Node3D) -> Vector3:
	var body := node.get_parent()
	while body != null and not body is PhysicsBody3D:
		body = body.get_parent()
	if body == null:
		return node.get_global_transform_interpolated().origin
	var b := body as Node3D
	return b.get_global_transform_interpolated() * (b.global_transform.affine_inverse() * node.global_position)


func _process(delta: float) -> void:
	var lead := Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
	for shot in _shots:
		if shot.spec.kind == ProjectileSpec.Kind.BEAM:
			_place_beam(shot, lead)
		else:
			_place_shot(shot, lead)
	_clock += delta
	_place_charges()
	for i in range(_flashes.size() - 1, -1, -1):
		var f := _flashes[i]
		f.age += delta
		if f.anchor != null and is_instance_valid(f.anchor):
			f.position = drawn_position(f.anchor)
		else:
			f.position += f.velocity * delta
		if f.age >= f.delay + f.duration:
			_release(f.sprite, _sprite_pool)
			if f.light != null:
				f.light.visible = false
				_light_pool.append(f.light)
			_flashes.remove_at(i)
			continue
		_place_flash(f)
	for v in _voices:
		if not v.player.playing:
			continue
		if v.anchor != null and is_instance_valid(v.anchor):
			v.position = drawn_position(v.anchor)
		else:
			v.position += v.velocity * delta
		v.player.global_position = v.position
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
	shot.head.position = head - dir * spec.bolt_length * 0.25


func _place_flash(f: Flash) -> void:
	if f.age < f.delay:
		f.sprite.visible = false
		if f.light != null:
			f.light.light_energy = 0.0
		return
	var u := clampf((f.age - f.delay) / f.duration, 0.0, 1.0)
	# Swell fast, then settle; fade out squared.
	var size := lerpf(f.size_from, f.size_to, 1.0 - (1.0 - u) * (1.0 - u))
	var fade := (1.0 - u) * (1.0 - u)
	if f.ball:
		# Pops out, holds white-hot, then cools to its colour and goes.
		size = lerpf(f.size_from, f.size_to, 1.0 - pow(1.0 - minf(u * 2.5, 1.0), 3.0))
		fade = 1.0 - smoothstep(0.45, 1.0, u)
		f.sprite.set_instance_shader_parameter(&"flash_heat", u)
	f.sprite.position = f.position
	f.sprite.visible = true
	f.sprite.set_instance_shader_parameter(&"flash_size", size)
	f.sprite.set_instance_shader_parameter(&"flash_intensity", f.intensity * fade)
	if f.light != null:
		f.light.position = f.position
		f.light.light_energy = f.light_energy * fade


func _place_charges() -> void:
	var t := _clock
	for owner in _charges.keys():
		var charge: Charge = _charges[owner]
		if not is_instance_valid(owner) or not is_instance_valid(charge.muzzle):
			_release(charge.sprite, _sprite_pool)
			_charges.erase(owner)
			continue
		var spec := charge.spec
		# Gathers in: swells and flickers faster as it nears the shot.
		var k := pow(charge.level, 0.7)
		var flicker := 1.0 + 0.18 * sin(t * (25.0 + 35.0 * charge.level))
		charge.sprite.position = drawn_position(charge.muzzle)
		charge.sprite.visible = true
		charge.sprite.set_instance_shader_parameter(&"flash_size", lerpf(spec.width * 2.0, spec.flash_size * 0.55, k) * flicker)
		charge.sprite.set_instance_shader_parameter(&"flash_intensity", spec.intensity * (0.3 + 0.7 * k))
		charge.sprite.set_instance_shader_parameter(&"flash_core", charge.level)
		# Readable from the receiving end at any range: a floor on its apparent size and a
		# camera glare that build with the charge.
		charge.sprite.set_instance_shader_parameter(&"flash_min_angle", charge_min_angle * (0.4 + 0.6 * k))
		charge.sprite.set_instance_shader_parameter(&"flash_glare", charge_glare * k)


## Draws a beam: its line and wake along the barrel (turned smoothly between ticks while
## it emits), the near end on the muzzle where it is drawn.
func _place_beam(shot: Shot, _lead: float) -> void:
	var spec := shot.spec
	var f := Engine.get_physics_interpolation_fraction()
	var dir := shot.prev_dir.slerp(shot.thrust_dir, f).normalized() if shot.emitting else shot.thrust_dir
	var reach := lerpf(shot.prev_reach, shot.reach, f)
	var tail := lerpf(shot.prev_tail, shot.tail, f)
	# Interpolated like the barrel it left, so it doesn't jump a tick ahead on release.
	var origin := shot.prev_position.lerp(shot.position, f)
	if shot.emitting and is_instance_valid(shot.muzzle):
		origin = drawn_position(shot.muzzle)
	var back := maxf(tail - spec.speed * spec.trail_time, 0.0)
	var length := reach - back
	shot.strip.visible = length > 0.5
	shot.head.visible = false
	if not shot.strip.visible:
		return
	var head := origin + dir * reach
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	shot.strip.transform = Transform3D(Basis.looking_at(dir, up).scaled_local(Vector3(1.0, 1.0, length)), head)
	shot.strip.set_instance_shader_parameter(&"beam_length", length)
	shot.strip.set_instance_shader_parameter(&"beam_body", reach - tail)
	shot.strip.set_instance_shader_parameter(&"beam_tip", 0.0 if shot.blocked else 1.0)
	shot.strip.set_instance_shader_parameter(&"beam_fizzle", shot.fizzle)
	shot.strip.set_instance_shader_parameter(&"beam_free", 0.0 if shot.emitting else 1.0)
	shot.head.visible = tail < reach and not shot.blocked and shot.fizzle < 0.5
	shot.head.position = head - dir * spec.width * 6.0
	shot.head.set_instance_shader_parameter(&"flash_size", spec.width * 7.0)
	if shot.mouth != null:
		shot.mouth.visible = true
		shot.mouth.position = origin
		shot.mouth.set_instance_shader_parameter(&"flash_size", spec.flash_size * 0.22)
		shot.mouth.set_instance_shader_parameter(&"flash_intensity", spec.intensity * 0.45)


## The shot stops at `at`, on `collider`.
func _land(shot: Shot, at: Vector3, collider: Node) -> void:
	shot.flown += shot.position.distance_to(at)
	shot.position = at
	shot.dead = true
	var velocity := _velocity_of(collider)
	if shot.spec.blast_radius > 0.0:
		_burst(shot, at, velocity)
	else:
		if not _impact(collider, shot.spec, at, shot.velocity - velocity, 0.0, shot.source):
			_damage(collider, shot.spec.damage, at, shot.velocity.normalized(), shot.source if is_instance_valid(shot.source) else null)
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
		if _impact(target, spec, at, Vector3.ZERO, maxf(target.global_position.distance_to(at) - radius, 0.5), shot.source):
			continue
		if d < spec.blast_radius:
			_damage(target, spec.damage * (1.0 - d / spec.blast_radius), at,
					(target.global_position - at).normalized(), shot.source if is_instance_valid(shot.source) else null)
	explode(at, velocity, spec.blast_radius, spec.color)


## A bullet or a burst reaching something with a physical damage model
## (`apply_impact(spec, at, relative_velocity, burst_distance, source)`): true if it took it.
static func _impact(node: Node, spec: ProjectileSpec, at: Vector3, relative_velocity: Vector3,
		burst_distance: float, source: Node) -> bool:
	while node != null:
		if node.has_method(&"apply_impact"):
			node.call(&"apply_impact", spec, at, relative_velocity, burst_distance,
					source if is_instance_valid(source) else null)
			return true
		if node.has_method(&"apply_hit"):
			return false
		node = node.get_parent()
	return false


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
	beam.shader = preload("res://Entities/Projectiles/Shader/bolt.gdshader")
	_strip_mesh.surface_set_material(0, beam)

	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2(2.0, 2.0)
	_quad_mesh.custom_aabb = AABB(Vector3(-200.0, -200.0, -200.0), Vector3(400.0, 400.0, 400.0))
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://Entities/Projectiles/Shader/flash.gdshader")
	_quad_mesh.material = glow

	# The beam: denser at both ends (its front far away, the barrel near the eye).
	verts = PackedVector3Array()
	indices = PackedInt32Array()
	var n := 96
	for i in n + 1:
		var z := 0.5 - 0.5 * cos(PI * float(i) / n)
		verts.append(Vector3(-1.0, 0.0, z))
		verts.append(Vector3(1.0, 0.0, z))
		if i < n:
			var k := i * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	_beam_mesh = ArrayMesh.new()
	_beam_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_beam_mesh.custom_aabb = AABB(Vector3(-60.0, -60.0, 0.0), Vector3(120.0, 120.0, 1.0))
	var line := ShaderMaterial.new()
	line.shader = preload("res://Entities/Projectiles/Shader/beam.gdshader")
	_beam_mesh.surface_set_material(0, line)


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
	if pool == _sprite_pool:
		# Only charges set these; a pooled sprite reused as a flash must not keep them.
		node.set_instance_shader_parameter(&"flash_min_angle", 0.0)
		node.set_instance_shader_parameter(&"flash_glare", 0.0)
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
