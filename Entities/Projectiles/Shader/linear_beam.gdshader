// A LINEAR beam: a straight camera-facing strip from its front (model z = 0) back to the
// barrel (z = 1, scaled by the node to beam_length m), widened in view space. A white-hot
// core inside a thick, ragged coloured sheath that flows outward; as beam_fade goes 0 → 1
// (the barrel has let go) the core dies first and the sheath spreads and breaks up.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

instance uniform vec3 beam_color : source_color = vec3(1.0, 0.15, 0.1);
instance uniform float beam_length = 1000.0;
instance uniform float beam_width = 1.4;       // core radius, m
instance uniform float beam_speed = 3200.0;
instance uniform float beam_intensity = 10.0;
instance uniform float beam_fade = 0.0;
// 1: the front is free and comes to a point; 0: it ends on something it hit.
instance uniform float beam_tip = 1.0;
instance uniform float beam_seed = 0.0;
uniform float min_angle = 0.0026;
uniform float max_angle = 0.035;

varying float v_along;
varying float v_side;
varying float v_widen;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_along = VERTEX.z * beam_length;
	v_side = VERTEX.x;
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, VERTEX.z, 1.0)).xyz;
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	float half_width = beam_width * 3.0 * (1.0 + 1.2 * beam_fade);
	float dist = length(centre);
	float wanted = min(half_width, max_angle * dist);
	half_width = max(wanted, min_angle * dist);
	v_widen = half_width / wanted;
	vec3 to_eye = normalize(-centre);
	vec3 right = cross(axis, to_eye);
	float len = length(right);
	right = len > 1e-4 ? right / len : vec3(1.0, 0.0, 0.0);
	VERTEX = centre + right * v_side * half_width;
	NORMAL = to_eye;
}

void fragment() {
	float fade = beam_fade;
	float r = abs(v_side) * 3.0 / min(v_widen, 3.0);
	// Metres from the barrel, flowing outward.
	float from_barrel = beam_length - v_along;
	float m = from_barrel - TIME * 180.0;
	float t = TIME * 3.0;
	float tip = mix(1.0, smoothstep(0.0, beam_width * 25.0, v_along), beam_tip);
	float taper = mix(0.3, 1.0, tip);
	// Swells out of the barrel instead of starting at full width.
	taper *= mix(0.45, 1.0, smoothstep(0.0, beam_width * 12.0, from_barrel));

	float wobble = noise(vec2(m * 0.05 + beam_seed * 17.0, t)) * 0.6
			+ noise(vec2(m * 0.21 - beam_seed * 5.0, v_side * 2.0 + t * 1.7)) * 0.4;
	float sheath_r = taper * (0.75 + 0.6 * wobble);
	float core = exp(-r * r * 2.4 / (taper * taper)) * pow(1.0 - fade, 4.0);
	float sheath = exp(-r * r * 0.5 / (sheath_r * sheath_r));
	// Breaking up from the edges in once let go.
	float n = noise(vec2(from_barrel * 0.12 + beam_seed * 31.0, v_side * 2.5 + fade * 4.0));
	float ragged = smoothstep(fade * 1.2 - 0.4, fade * 1.2 + 0.2, n + 0.35 * (1.0 - r / 3.0));
	sheath *= ragged * pow(1.0 - fade, 1.5);

	vec3 col = mix(beam_color, vec3(1.0), 0.88) * core * 3.0 + beam_color * sheath * 1.4;
	float edge = 1.0 - smoothstep(0.8, 1.0, abs(v_side));
	ALBEDO = col * beam_intensity * tip * edge;
}
