class_name PanoramicMeshBuilder

## Generates the spherical ArrayMesh for a panoramic cockpit display screen.
##
## UV0: standard spherical wrap (t_arc, 1 - t_elev) for optional overlays.
## UV2: panoramic direction encoded as (azimuth / TAU, elevation_normalised).
##      The shader recovers world-space direction from UV2 each fragment.
## Normals point inward so the surface is visible from inside the cockpit.
##
## Extracted from PanoramicScreen to keep that class focused on lifecycle and
## segment masking. This function is stateless and has no node dependencies.


static func build(
	arc_angle: float,
	arc_offset: float,
	elevation_range: float,
	screen_radius: float,
	arc_segments: int,
	elevation_segments: int
) -> ArrayMesh:
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var uv2s    := PackedVector2Array()
	var indices := PackedInt32Array()

	for row in range(elevation_segments + 1):
		var t_elev    := float(row) / float(elevation_segments)
		var elevation := (t_elev - 0.5) * elevation_range

		for col in range(arc_segments + 1):
			var t_arc   := float(col) / float(arc_segments)
			var azimuth := arc_offset + t_arc * arc_angle
			var cos_el  := cos(elevation)

			verts.append(Vector3(
				screen_radius * sin(azimuth) * cos_el,
				screen_radius * sin(elevation),
				-screen_radius * cos(azimuth) * cos_el  # -Z is forward in Godot
			))

			# Inward-facing normals so the screen surface faces the pilot inside.
			normals.append(Vector3(
				-sin(azimuth) * cos_el,
				-sin(elevation),
				cos(azimuth) * cos_el
			))

			# UV0: standard spherical wrap.
			uvs.append(Vector2(t_arc, 1.0 - t_elev))

			# UV2: azimuth/TAU may exceed [0,1] when arc_offset != 0.
			# The shader uses fract() for the segment mask sample, and sin/cos
			# are periodic, so the direction maths stays correct regardless.
			uv2s.append(Vector2(azimuth / TAU, t_elev))

	for row in range(elevation_segments):
		for col in range(arc_segments):
			var i := row * (arc_segments + 1) + col
			indices.append(i)
			indices.append(i + arc_segments + 1)
			indices.append(i + 1)
			indices.append(i + 1)
			indices.append(i + arc_segments + 1)
			indices.append(i + arc_segments + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX]   = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
