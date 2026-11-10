@tool
class_name DebrisField
extends MultiMeshInstance3D

## Scatters rocks in a spherical shell so there is something nearby to judge
## motion against — in empty space, velocity is otherwise invisible.

@export var count: int = 350:
	set(v): count = v; _rebuild()
@export var inner_radius: float = 40.0:
	set(v): inner_radius = v; _rebuild()
@export var outer_radius: float = 600.0:
	set(v): outer_radius = v; _rebuild()
@export var size_range := Vector2(0.4, 5.0):
	set(v): size_range = v; _rebuild()
@export var random_seed: int = 7:
	set(v): random_seed = v; _rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	rock.radius = 0.5
	rock.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.3, 0.29)
	mat.roughness = 0.95
	rock.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for i in count:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		# Uniform density by volume within the shell.
		var t := rng.randf()
		var r := pow(lerpf(pow(inner_radius, 3.0), pow(outer_radius, 3.0), t), 1.0 / 3.0)
		var s := rng.randf_range(size_range.x, size_range.y)
		var rock_scale := Vector3(s * rng.randf_range(0.6, 1.4), s * rng.randf_range(0.5, 1.0), s)
		var rock_basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(rock_scale)
		mm.set_instance_transform(i, Transform3D(rock_basis, dir * r))
	multimesh = mm
