shader_type spatial;

// The lamps on a rail, one mesh: lit red behind the carriage (mesh z above lit_from, which is
// the carriage's z in the same frame), black lenses ahead of it.

uniform vec3 lit_color : source_color = vec3(1.0, 0.0, 0.01);
uniform float lit_energy = 1.2;
uniform vec3 off_color : source_color = vec3(0.02, 0.02, 0.022);
instance uniform float lit_from = 0.0;

varying float along;

void vertex() {
	along = VERTEX.z;
}

void fragment() {
	float lit = step(lit_from, along);
	ALBEDO = mix(off_color, lit_color * 0.08, lit);
	ROUGHNESS = 0.25;
	EMISSION = lit_color * lit_energy * lit;
}
