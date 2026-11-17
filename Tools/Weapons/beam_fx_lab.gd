extends SceneTree

## Beam FX lab: one beam shot (spool, bolt, impact) fired from a bare muzzle at a plate,
## filmed from several cameras at once at exact sim times, for every variant of its look.
## Writes a filmstrip sheet per view (rows = variants, columns = times) and optionally
## every frame of one view as a slow-motion video. Run it through beam_fx_lab.sh, which
## sets the fixed frame rate that makes the times exact.
##
## Args after --: <out_dir> then any of
##   spec=res://...tres        the shot to film (default the RX-93 beam rifle)
##   dist=900                  muzzle to plate, m
##   views=spool,recv,side,track,fp,impact   (track rides 60 m beside the bolt head)
##   size=960x540              per view
##   video=side                save every frame of that view and encode <out>/<variant>_side.mp4
##   times.<view>=s0.5,+0.05,i+0.02   capture times: s = fraction of the spool,
##                             + = s after the shot leaves, i = s after it reaches the plate
##   <variant>:<key>=<value>   one override; variants run in order of first mention, after
##                             "base" (unchanged) unless `nobase` is given. Keys: a
##                             ProjectileSpec property (width, bolt_length, color, ...), or
##                             mgr.<export>, beam.<uniform>, flash.<uniform>, linear.<uniform>.
##                             Values go through str_to_var: 0.8, Color(1,0.2,0.1,1), true.

const STAGE := "res://Stages/RX93TestRange/rx93_test_range.tscn"
const DEFAULT_SPEC := "res://Entities/Projectiles/Specs/nu_beam_rifle.tres"
const ALL_VIEWS := ["spool", "recv", "side", "track", "fp", "impact"]
const DEFAULT_TIMES := {
	"spool": "s0.1,s0.3,s0.5,s0.7,s0.9,+0.008,+0.03,+0.08",
	"recv": "s0.2,s0.5,s0.8,s1.0,i-0.15,i-0.08,i-0.03,i+0.0",
	"side": "+0.02,+0.05,+0.1,+0.15,+0.2,+0.25,i+0.01,i+0.05",
	"track": "+0.01,+0.03,+0.06,+0.1,+0.15,+0.2,i-0.01,i+0.01",
	"fp": "+0.0,+0.02,+0.05,+0.1,+0.2,i+0.0",
	"impact": "i-0.02,i+0.01,i+0.03,i+0.08,i+0.15,i+0.3,i+0.6,i+1.0",
}

var _out := "user://beam_fx_lab"
var _spec_path := DEFAULT_SPEC
var _dist := 900.0
var _views: Array = ALL_VIEWS.duplicate()
var _size := Vector2i(960, 540)
var _video := ""
var _times := {}
## [[name, {key: value}]] in run order.
var _variants: Array = []

var _lab: Node3D
var _muzzle: Node3D
var _cams := {}   # view -> SubViewport
var _track: Camera3D
## view -> [[variant, tag, file]] for the sheets.
var _tiles := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var by_name := {}
	var keep_base := true
	for i in args.size():
		var a := args[i]
		if i == 0 and not "=" in a:
			_out = a
		elif a == "nobase":
			keep_base = false
		elif ":" in a.get_slice("=", 0):
			var name := a.get_slice(":", 0)
			var kv := a.substr(name.length() + 1)
			var key := kv.get_slice("=", 0)
			if not by_name.has(name):
				by_name[name] = {}
				_variants.append([name, by_name[name]])
			by_name[name][key] = _parse(kv.substr(key.length() + 1))
		elif a.begins_with("times."):
			_times[a.get_slice("=", 0).trim_prefix("times.")] = a.get_slice("=", 1)
		elif a.begins_with("spec="):
			_spec_path = a.trim_prefix("spec=")
		elif a.begins_with("dist="):
			_dist = a.trim_prefix("dist=").to_float()
		elif a.begins_with("views="):
			_views = Array(a.trim_prefix("views=").split(","))
		elif a.begins_with("size="):
			var wh := a.trim_prefix("size=").split("x")
			_size = Vector2i(wh[0].to_int(), wh[1].to_int())
		elif a.begins_with("video="):
			_video = a.trim_prefix("video=")
		else:
			push_error("beam_fx_lab: unknown arg %s" % a)
	if keep_base:
		_variants.push_front(["base", {}])
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _parse(text: String) -> Variant:
	var v: Variant = str_to_var(text)
	return text if v == null else v


func _run() -> void:
	_build_lab()
	await _wait(10)
	for variant in _variants:
		await _film(variant[0], variant[1])
	_sheets()
	print("BEAMLAB done: %s" % ProjectSettings.globalize_path(_out))
	quit()


## The range's light and environment (same bloom and tonemap as the game), a muzzle
## stub at the origin firing down -Z, a plate at _dist, and one SubViewport per view.
func _build_lab() -> void:
	var stage: Node = (load(STAGE) as PackedScene).instantiate()
	_lab = Node3D.new()
	_lab.name = "BeamLab"
	for node_name in ["WorldEnvironment", "DirectionalLight3D"]:
		var node := stage.get_node(node_name).duplicate()
		_lab.add_child(node)
	stage.free()
	root.add_child(_lab)
	current_scene = _lab

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.25, 0.26, 0.28)
	dark.metallic = 0.6
	dark.roughness = 0.4
	_muzzle = Node3D.new()
	_lab.add_child(_muzzle)
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 4.0
	cyl.material = dark
	barrel.mesh = cyl
	barrel.rotation_degrees.x = 90.0
	barrel.position.z = 2.0
	_lab.add_child(barrel)

	var plate := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 30, 2)
	shape.shape = box
	plate.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	bm.material = dark
	mesh.mesh = bm
	plate.add_child(mesh)
	plate.position = Vector3(0, 0, -_dist)
	_lab.add_child(plate)

	var eyes := {
		"spool": [Vector3(5, 1.5, -12), Vector3(0, 0, -1), 40.0],
		"recv": [Vector3(3, 2, -_dist + 30), Vector3.ZERO, 75.0],
		"side": [Vector3(_dist * 0.42, 30, -_dist * 0.5), Vector3(0, 0, -_dist * 0.5), 70.0],
		"track": [Vector3(60, 10, 0), Vector3.ZERO, 50.0],
		"fp": [Vector3(0.8, 0.6, 3), Vector3(0, 0, -_dist), 75.0],
		"impact": [Vector3(40, 15, -_dist + 50), Vector3(0, 0, -_dist), 50.0],
	}
	for view in _views:
		var vp := SubViewport.new()
		vp.size = _size
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.fov = eyes[view][2]
		cam.far = 20000.0
		vp.add_child(cam)
		_lab.add_child(vp)
		cam.global_transform = Transform3D(Basis.IDENTITY, eyes[view][0]).looking_at(eyes[view][1], Vector3.UP)
		cam.current = true
		_cams[view] = vp
		if view == "track":
			_track = cam
		_tiles[view] = []


## One full shot for a variant: spool, fire, fly, hit, fade, saving the due frames.
func _film(variant: String, overrides: Dictionary) -> void:
	var old := ProjectileManager.find(_lab)
	if old != null:
		old.free()
	seed(1)
	var manager := ProjectileManager.of(_lab)
	await _wait(2)
	var spec := (load(_spec_path) as ProjectileSpec).duplicate() as ProjectileSpec
	_apply(manager, spec, overrides)
	var spool := spec.spool_time
	var arrive := spool + (_dist - 0.0) / spec.speed
	# view -> [[t, tag]] sorted
	var due := {}
	var end := 0.0
	for view in _views:
		var list := []
		for token in String(_times.get(view, DEFAULT_TIMES[view])).split(","):
			var t := _resolve(token.strip_edges(), spool, arrive)
			list.append([t, token.strip_edges()])
			end = maxf(end, t)
		list.sort_custom(func(a, b): return a[0] < b[0])
		due[view] = list
	end += 0.05
	if _video != "":
		DirAccess.make_dir_recursive_absolute("%s/video_%s" % [_out, variant])

	var owner := RefCounted.new()
	var t := 0.0
	var fired := false
	var frame := 0
	var dt := 0.0
	while t <= end:
		await process_frame
		dt = _lab.get_process_delta_time()
		if not fired:
			if t >= spool:
				manager.set_charge(owner, _muzzle, spec, 0.0)
				var dir := Vector3.FORWARD
				manager.spawn(spec, _muzzle.global_position, dir * spec.speed, dir)
				manager.muzzle_flash(spec, _muzzle.global_position, Vector3.ZERO, _muzzle)
				fired = true
			elif spool > 0.0:
				manager.set_charge(owner, _muzzle, spec, maxf(t / spool, 0.001))
		if _track != null:
			# Abreast of the head as it is drawn (same lead as the manager), held at the plate.
			var z := 0.0
			if not manager._shots.is_empty():
				var shot: ProjectileManager.Shot = manager._shots[0]
				var lead := 0.0 if shot.dead else Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second
				z = (shot.position + shot.velocity * lead).z
			elif fired:
				z = -_dist
			_track.global_transform = Transform3D(Basis.IDENTITY, Vector3(60, 10, z + 30)) \
					.looking_at(Vector3(0, 0, z + 20), Vector3.UP)
		await RenderingServer.frame_post_draw
		for view in _views:
			var list: Array = due[view]
			while not list.is_empty() and t + dt * 0.5 >= list[0][0]:
				var item: Array = list.pop_front()
				var file := "%s/%s_%s_%s.png" % [_out, variant, view, _safe(item[1])]
				_cams[view].get_texture().get_image().save_png(file)
				_tiles[view].append([variant, item[1], file])
		if _video != "" and _cams.has(_video):
			_cams[_video].get_texture().get_image().save_png("%s/video_%s/%05d.png" % [_out, variant, frame])
		frame += 1
		t += dt
	manager.set_charge(owner, _muzzle, spec, 0.0)
	if _video != "" and _cams.has(_video):
		var fps := roundi(1.0 / maxf(dt, 1e-4))
		var mp4 := ProjectSettings.globalize_path("%s/%s_%s.mp4" % [_out, variant, _video])
		OS.execute("ffmpeg", ["-y", "-loglevel", "error", "-framerate", "60", "-i",
				ProjectSettings.globalize_path("%s/video_%s/%%05d.png" % [_out, variant]),
				"-pix_fmt", "yuv420p", mp4])
		print("BEAMLAB video %s (%d fps sim at 60: %.0fx slow motion)" % [mp4, fps, fps / 60.0])
	print("BEAMLAB filmed %s (%d frames, dt %.4f s)" % [variant, frame, dt])


func _resolve(token: String, spool: float, arrive: float) -> float:
	if token.begins_with("s"):
		return token.substr(1).to_float() * spool
	if token.begins_with("i"):
		return arrive + token.substr(1).to_float()
	return spool + token.to_float()


func _apply(manager: ProjectileManager, spec: ProjectileSpec, overrides: Dictionary) -> void:
	var materials := {
		"beam": manager._strip_mesh.surface_get_material(0),
		"flash": manager._quad_mesh.material,
		"linear": manager._linear_mesh.surface_get_material(0),
	}
	for key: String in overrides:
		var value: Variant = overrides[key]
		var scope := key.get_slice(".", 0) if "." in key else "spec"
		var prop := key.get_slice(".", 1) if "." in key else key
		match scope:
			"spec":
				if not prop in spec:
					push_error("beam_fx_lab: no spec property %s" % prop)
				spec.set(prop, value)
			"mgr":
				manager.set(prop, value)
			_:
				(materials[scope] as ShaderMaterial).set_shader_parameter(prop, value)


func _safe(tag: String) -> String:
	return tag.replace("+", "p").replace("-", "m")


## One sheet per view: a row per variant, a column per time, labelled.
func _sheets() -> void:
	for view in _views:
		var files := []
		var cols := 0
		var per_row := {}
		for tile in _tiles[view]:
			per_row[tile[0]] = per_row.get(tile[0], 0) + 1
			cols = maxi(cols, per_row[tile[0]])
			files.append_array(["-label", "%s %s" % [tile[0], tile[1]], ProjectSettings.globalize_path(tile[2])])
		var sheet := ProjectSettings.globalize_path("%s/sheet_%s.png" % [_out, view])
		var thumb := "%dx%d+3+3" % [_size.x / 2, _size.y / 2]
		var args := ["-background", "#202020", "-fill", "white", "-pointsize", "16"]
		args.append_array(files)
		args.append_array(["-tile", "%dx" % cols, "-geometry", thumb, sheet])
		var code := OS.execute("montage", args)
		print("BEAMLAB sheet %s%s" % [sheet, "" if code == 0 else " (montage failed %d)" % code])


func _wait(count: int) -> void:
	for i in count:
		await process_frame
