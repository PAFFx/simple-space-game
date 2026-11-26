// The face of a cut: a grid across the cut plane (part space), raised by the cut's torn offset
// so it sits exactly on the surface the part is cut away at, drawn only where the stencil writer
// marked the cross-section. Hot when made, cooling like a beam hole; re-melted, bumpy metal.
// Written to ALPHA so it is drawn after the opaque pass (after the writer).

#include "res://Entities/Vehicles/Components/Damage/Shader/beam_hole.gdshaderinc"

uniform sampler2D melt_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float melt_depth = 0.07;

varying vec3 v_cap_pos;

void vertex() {
	vec3 n = cut_plane.xyz;
	VERTEX += n * cut_offset(VERTEX);
	v_cap_pos = VERTEX;
	NORMAL = n * cut_side;
}

void fragment() {
	vec3 n = cut_plane.xyz;
	vec3 e1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec2 uv = vec2(dot(v_cap_pos, e1), dot(v_cap_pos, cross(n, e1)));
	float melt = texture(melt_height, uv * 1.1).r;
	float patches = texture(melt_height, uv * 0.4 + vec2(3.7)).r;
	// Bump from the melt's own gradient (screen derivatives taken before any branch).
	vec3 pos = VERTEX;
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float h = melt * melt_depth;
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dhx * r1 + dhy * r2));
	float age = hole_now - cut_heat.y;
	float t = cut_temperature(cut_heat.x, age, uv) * (0.82 + 0.12 * melt);
	float runs = smoothstep(0.25, 0.75, patches) * 0.75 + melt * 0.25;
	ALBEDO = mix(vec3(0.05, 0.045, 0.04), vec3(0.12, 0.105, 0.09), runs);
	ROUGHNESS = 0.72 + 0.18 * runs;
	METALLIC = 0.55;
	EMISSION = hole_blackbody(t) * hole_glow(t);
	ALPHA = 1.0;
}
