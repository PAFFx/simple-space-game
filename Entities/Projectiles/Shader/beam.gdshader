// A flying bolt and the wake it leaves: a camera-facing strip from the bolt's head (model
// z = 0) back along its path (z = 1, scaled by the node to the strip's length in metres).
// The head is a white-hot spear; behind it the wake spreads, breaks up and fades over
// beam_trail seconds. Positions are built in view space (double precision safe).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

instance uniform vec3 beam_color : source_color = vec3(1.0, 0.15, 0.1);
instance uniform float beam_length = 100.0;    // m, head to tail
instance uniform float beam_speed = 4000.0;    // m/s
instance uniform float beam_width = 0.9;       // core radius, m
instance uniform float beam_bolt = 60.0;       // bright head length, m
instance uniform float beam_trail = 0.55;      // wake life, s
instance uniform float beam_intensity = 9.0;
instance uniform float beam_dead = 0.0;        // s since the bolt stopped (0 = flying)
instance uniform float beam_seed = 0.0;
// Never thinner on screen than this (rad), so a far beam stays a visible line.
uniform float min_angle = 0.0017;
// Nor wider than this (rad): a wake passing right by the camera stays a streak, not a wall.
uniform float max_angle = 0.03;

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
	float side = VERTEX.x;
	v_along = VERTEX.z * beam_length;
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, VERTEX.z, 1.0)).xyz;
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	float age = v_along / beam_speed + beam_dead;
	// The wake spreads as it ages.
	float half_width = beam_width * 3.0 * (1.0 + 0.9 * clamp(age / beam_trail, 0.0, 1.0));
	float dist = length(centre);
	float wanted = min(half_width, max_angle * dist);
	half_width = max(wanted, min_angle * dist);
	// Stretched to stay visible: the core then fills more of the strip.
	v_widen = half_width / wanted;
	vec3 to_eye = normalize(-centre);
	vec3 right = cross(axis, to_eye);
	float len = length(right);
	right = len > 1e-4 ? right / len : vec3(1.0, 0.0, 0.0);
	VERTEX = centre + right * side * half_width;
	NORMAL = to_eye;
	v_side = side;
}

void fragment() {
	float age = v_along / beam_speed + beam_dead;
	float t = clamp(age / beam_trail, 0.0, 1.0);
	// Across the strip in core radii: the core is the middle third.
	float r = abs(v_side) * 3.0 / min(v_widen, 3.0);
	float flying = 1.0 - step(0.0001, beam_dead);

	// The bolt: a spear tapering to a point at the head, brightest just behind it.
	float tip = smoothstep(0.0, beam_bolt * 0.14, v_along);
	float bolt = flying * (1.0 - smoothstep(beam_bolt * 0.35, beam_bolt, v_along));
	float taper = mix(0.25, 1.0, tip);
	float core = exp(-r * r * 2.6 / (taper * taper));
	float sheath = exp(-r * r * 0.42 / (taper * taper));
	vec3 spear = (mix(beam_color, vec3(1.0), 0.82) * core * 3.2 + beam_color * sheath * 1.3) * bolt;

	// The wake: a hot thread that dies quickly inside a ragged glow that breaks up as it
	// fades (the particles disperse after the bolt has passed).
	float thread = exp(-r * r * 3.0) * pow(1.0 - t, 5.0) * 1.6;
	float n = noise(vec2(v_along * 0.3 + beam_seed * 31.0, v_side * 1.6 + beam_seed * 7.0))
			* 0.6 + noise(vec2(v_along * 0.9 - beam_seed * 13.0, v_side * 3.0 + age * 2.0)) * 0.4;
	float ragged = smoothstep(t * 1.1 - 0.45, t * 1.1 + 0.45, n + 0.3 * (1.0 - r / 3.0));
	float glow = exp(-r * r * 0.9) * (1.0 - t) * (1.0 - t) * ragged;
	vec3 wake = beam_color * glow * 0.4 + mix(beam_color, vec3(1.0), 0.55) * thread;

	float edge = 1.0 - smoothstep(0.76, 1.0, abs(v_side));
	ALBEDO = (spear + wake) * beam_intensity * edge;
}
