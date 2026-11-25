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

// Bump from a height field (m) over the surface at `pos` (view space), screen derivatives:
// works on any mesh, tangents or not.
vec3 melt_bump(vec3 n, vec3 pos, float height) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhx = dFdx(height);
	float dhy = dFdy(height);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

void vertex() {
	v_part_pos = hole_part_pos(VERTEX);
	v_part_cam = hole_part_cam(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 base = texture(albedo_texture, UV) * albedo_color;
	HoleHit h = hole_fragment(v_part_pos, v_part_cam, FRONT_FACING);
	if (h.discard_it) {
		discard;
	}
	float depth = FRAGCOORD.z;
	// One height per fragment, worked out before any branch (derivatives need every pixel):
	// inside, in the wall's own coordinates; outside, around the hole's rim.
	vec2 wall_uv = vec2(h.wall.x * 0.55, h.wall.y * 0.22);
	// Outside, isotropic over the part (its own space, metres): no streaks round the hole.
	vec2 zone_uv = vec2(v_part_pos.x + v_part_pos.z * 0.62, v_part_pos.y + v_part_pos.z * 0.41) * 0.9;
	float melt = texture(melt_height, h.inside ? wall_uv : zone_uv).r;
	float relief = h.inside ? melt_depth : lip_depth * max(h.lip, clamp((h.temperature - 650.0) / 900.0, 0.0, 1.0) * 0.8);
	vec3 bump_pos = VERTEX + normalize(VERTEX) * h.depth;
	float bump_h = melt * relief;
	vec3 albedo = base.rgb;
	float rough = roughness;
	float metal = metallic;
	vec3 emit = emission_color * emission_energy;
	if (h.inside) {
		// Bore wall or crater floor: re-melted metal, drawn where it really is. Melt runs
		// streak it along the beam's axis; cooler slag crusts over in patches.
		vec3 view_hit = VERTEX + normalize(VERTEX) * h.depth;
		vec4 clip = PROJECTION_MATRIX * vec4(view_hit, 1.0);
		depth = clip.z / clip.w;
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * part_to_model * vec4(h.normal_part, 0.0)).xyz);
		NORMAL = melt_bump(NORMAL, bump_pos, bump_h);
		// Broad melt runs along the axis, a little fine grain; deeper in the bore the wall is
		// seen through a narrow opening and catches less light: it reads as a hole.
		float runs = hole_noise(vec2(h.wall.x * 1.6, h.wall.y * 0.35)) * 0.7 + hole_noise(vec2(h.wall.x * 5.0, h.wall.y * 1.2)) * 0.3;
		float deep = exp(-h.depth / 1.6);
		float t = h.temperature * (0.82 + 0.2 * runs + 0.12 * melt);
		albedo = mix(vec3(0.05, 0.045, 0.04), vec3(0.12, 0.105, 0.09), runs) * (0.4 + 0.6 * deep);
		rough = 0.25 + 0.2 * runs;
		metal = 0.9;
		emit = hole_blackbody(t) * hole_glow(t) * (0.25 + 0.75 * deep);
	} else if (!FRONT_FACING && (h.near_heat > 400.0 || h.interior)) {
		// The shell's inside, seen through a hole: dark, lit by the hole's glow.
		albedo = vec3(0.045, 0.045, 0.05);
		rough = 0.8;
		metal = 0.6;
		emit = hole_blackbody(h.near_heat) * hole_glow(h.near_heat) * 0.25;
	} else {
		// Around a mouth: the molten lip (beaded, glossy), glowing metal fading out, a
		// narrow band of heat tint, then soot fading smoothly into the paint.
		if (relief > 0.0005) {
			NORMAL = melt_bump(NORMAL, bump_pos, bump_h);
		}
		float grain = hole_noise(UV * 160.0);
		float soft = hole_noise(vec2(h.zone.x * 3.0, h.zone.y * 1.5));
		float beads = smoothstep(0.45, 0.75, hole_noise(vec2(h.zone.x * 12.0, h.zone.y * 8.0)));
		float t = h.temperature * (0.9 + 0.15 * soft) * mix(1.0, 0.85 + 0.3 * beads, h.lip);
		vec3 soot = vec3(0.035, 0.028, 0.022) * (0.75 + 0.5 * grain);
		albedo = mix(albedo, soot, h.scorch * (0.85 + 0.15 * soft));
		vec3 tint = mix(vec3(0.5, 0.36, 0.16), vec3(0.2, 0.22, 0.4), soft);
		albedo = mix(albedo, tint * 0.5, h.tint * (1.0 - clamp(h.temperature / 1000.0, 0.0, 1.0)) * 0.3);
		rough = mix(rough, mix(0.15, 0.45, beads), h.lip);
		metal = mix(metal, 0.9, h.lip);
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
