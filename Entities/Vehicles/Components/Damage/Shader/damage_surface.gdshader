shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// The look of a plain StandardMaterial3D (albedo texture × colour, roughness, metallic,
// specular, optional emission) plus beam holes (beam_hole.gdshaderinc). A mesh switches to
// this on its first hole (HoleSet), with the original's values copied in.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// Height of re-melted metal (HoleSet: a noise texture), for bump-mapped melt: runs and dross on
// the bore walls, crater floors and cut faces, beads on the molten lip.
uniform sampler2D melt_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float melt_depth = 0.07;   // m of relief inside, at full height
uniform float lip_depth = 0.035;   // m of relief on the lip and the hot zone around it

#include "res://Entities/Vehicles/Components/Damage/Shader/beam_hole.gdshaderinc"

// Bump from a height field over the surface, from its screen derivatives (position, view
// space, and height). The derivatives are taken once at the top of fragment(): inside a branch
// that neighbouring pixels don't all take they are undefined (a broken line along every edge).
vec3 melt_bump(vec3 n, vec3 dpdx, vec3 dpdy, float dhx, float dhy) {
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

// Melt height on a bore, floor or cut face: triplanar in the hole's own frame (no seam, no
// polar streaks, fixed to the hole whatever the view).
float tri_melt(vec3 p, vec3 n, float k) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z + 1e-5;
	return texture(melt_height, p.yz * k).r * w.x + texture(melt_height, p.xz * k).r * w.y
			+ texture(melt_height, p.xy * k).r * w.z;
}

void vertex() {
	v_part_pos = hole_part_pos(VERTEX);
	v_part_cam = hole_part_cam(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	HoleHit h = hole_fragment(v_part_pos, v_part_cam, FRONT_FACING);
	// Every sample and derivative first, for every pixel (before the discard and the
	// branches): inside, in the hole's frame; outside, over the part (its own space, metres).
	float melt_in = tri_melt(h.tex_p, h.tex_n, 1.1);
	vec2 zone_uv = vec2(v_part_pos.x + v_part_pos.z * 0.62, v_part_pos.y + v_part_pos.z * 0.41) * 0.9;
	float melt_out = texture(melt_height, zone_uv).r;
	// Coarser patches of the same melt: slag crusts inside, beads on the lip.
	float patches_in = tri_melt(h.tex_p * 0.4 + 3.7, h.tex_n, 1.0);
	float patches_out = texture(melt_height, zone_uv * 2.6 + vec2(0.37, 0.71)).r;
	// The inside (a back face, only seen through an opening): torn, re-melted metal all over,
	// triplanar over the part by its own facing.
	vec3 geo_n = normalize(cross(dFdx(v_part_pos), dFdy(v_part_pos)));
	float melt_inner = tri_melt(v_part_pos * 0.9, geo_n, 1.1);
	float patches_inner = tri_melt(v_part_pos * 0.35 + 5.3, geo_n, 1.0);
	bool inner = !FRONT_FACING && !h.inside;
	float melt = h.inside ? melt_in : (inner ? melt_inner : melt_out);
	float relief = (h.inside || inner) ? melt_depth : lip_depth * max(h.lip, clamp((h.temperature - 650.0) / 900.0, 0.0, 1.0) * 0.8);
	vec3 bump_pos = VERTEX + normalize(VERTEX) * h.depth;
	float bump_h = melt * relief;
	vec3 dpdx = dFdx(bump_pos);
	vec3 dpdy = dFdy(bump_pos);
	float dhx = dFdx(bump_h);
	float dhy = dFdy(bump_h);
	if (h.discard_it) {
		discard;
	}
	float depth = FRAGCOORD.z;
	vec3 albedo = base.rgb;
	float rough = roughness;
	float metal = metallic;
	vec3 emit = emission_color * emission_energy;
	if (h.inside) {
		// Bore wall or crater floor: re-melted metal, drawn where it really is. Melt runs
		// streak it along the beam's axis; cooler slag crusts over in patches.
		// A cut face drawn on a back face lies in front of it (negative depth): it keeps the back
		// face's own depth, so nothing that really covers the part (a skirt) is drawn under it.
		if (h.depth > 0.0) {
			vec3 view_hit = VERTEX + normalize(VERTEX) * h.depth;
			vec4 clip = PROJECTION_MATRIX * vec4(view_hit, 1.0);
			depth = clip.z / clip.w;
		}
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * part_to_model * vec4(h.normal_part, 0.0)).xyz);
		NORMAL = melt_bump(NORMAL, dpdx, dpdy, dhx, dhy);
		// Melt and slag in patches, a little fine grain; deeper in the bore the wall is seen
		// through a narrow opening and catches less light: it reads as a hole.
		float runs = smoothstep(0.25, 0.75, patches_in) * 0.75 + melt * 0.25;
		// A cut face is drawn in front of the back face it is on (negative depth): no dimming,
		// and no brightening either (exp of a negative depth made it glare white at angles).
		float deep = exp(-max(h.depth, 0.0) / 1.6);
		float t = h.temperature * (0.82 + 0.2 * runs + 0.12 * melt);
		albedo = mix(vec3(0.05, 0.045, 0.04), vec3(0.12, 0.105, 0.09), runs) * (0.4 + 0.6 * deep);
		// Re-solidified slag is rough: glossy, its bumps mirrored the planet and sun in
		// specks that slid with the view.
		rough = 0.72 + 0.18 * runs;
		metal = 0.55;
		emit = hole_blackbody(t) * hole_glow(t) * (0.25 + 0.75 * deep);
	} else if (!FRONT_FACING) {
		// The suit's inside (a back face: only ever seen through an opening): rough torn and
		// re-melted metal, as the bores are, never an empty painted shell; lit by a hole's
		// glow nearby.
		NORMAL = melt_bump(NORMAL, dpdx, dpdy, dhx, dhy);
		float runs = smoothstep(0.25, 0.75, patches_inner) * 0.75 + melt_inner * 0.25;
		albedo = mix(vec3(0.05, 0.045, 0.04), vec3(0.12, 0.105, 0.09), runs);
		rough = 0.72 + 0.18 * runs;
		metal = 0.55;
		emit = hole_blackbody(h.near_heat) * hole_glow(h.near_heat) * 0.25;
	} else {
		// Around a mouth: the molten lip (beaded, glossy), glowing metal fading out, a
		// narrow band of heat tint, then soot fading smoothly into the paint.
		NORMAL = melt_bump(NORMAL, dpdx, dpdy, dhx, dhy);
		float grain = hole_noise(UV * 160.0);
		// Over the part, not around the hole: no rays out of the rim.
		float soft = melt_out;
		float beads = smoothstep(0.55, 0.8, patches_out);
		float t = h.temperature * (0.9 + 0.15 * soft) * mix(1.0, 0.85 + 0.3 * beads, h.lip);
		vec3 soot = vec3(0.035, 0.028, 0.022) * (0.75 + 0.5 * grain);
		albedo = mix(albedo, soot, h.scorch * (0.85 + 0.15 * soft));
		vec3 tint = mix(vec3(0.5, 0.36, 0.16), vec3(0.2, 0.22, 0.4), soft);
		albedo = mix(albedo, tint * 0.5, h.tint * (1.0 - clamp(h.temperature / 1000.0, 0.0, 1.0)) * 0.3);
		rough = mix(rough, mix(0.5, 0.75, beads), h.lip);
		metal = mix(metal, 0.6, h.lip);
		albedo = mix(albedo, vec3(0.07, 0.06, 0.05) * (0.7 + 0.6 * beads), h.lip);
		emit += hole_blackbody(t) * hole_glow(t);
	}
	DEPTH = depth;
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = specular;
	EMISSION = emit;
}
