// A pulse beam: a short, unstable burst of energy, white-hot inside a flickering coloured
// halo, trailing a few thin streaks that die within beam_trail. Drawn on a camera-facing
// strip from the head (model z = 0) back along the path (z = 1, scaled by the node to
// the strip's length in metres). Positions are built in view space (double precision safe).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

instance uniform vec3 beam_color : source_color = vec3(1.0, 0.15, 0.1);
instance uniform float beam_length = 100.0;    // m, head to tail
instance uniform float beam_speed = 3000.0;    // m/s
instance uniform float beam_width = 1.2;       // core radius, m
instance uniform float beam_bolt = 40.0;       // burst length, m
instance uniform float beam_trail = 0.03;      // streak life, s
instance uniform float beam_intensity = 9.0;
instance uniform float beam_dead = 0.0;        // s since the burst stopped (0 = flying)
instance uniform float beam_seed = 0.0;
// Never thinner on screen than this (rad), so a far burst stays visible.
uniform float min_angle = 0.0026;
// Nor wider than this (rad): one passing right by the camera stays a streak, not a wall.
uniform float max_angle = 0.04;

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
	float half_width = beam_width * 4.0;
	float dist = length(centre);
	float wanted = min(half_width, max_angle * dist);
	half_width = max(wanted, min_angle * dist);
	// Stretched to stay visible: the burst then fills more of the strip.
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
	float squeeze = min(v_widen, 4.0);
	// Across the strip in core radii (signed): the strip is four core radii each side.
	float s = v_side * 4.0 / squeeze;
	float r = abs(s);
	float flying = 1.0 - step(0.0001, beam_dead);
	float u = v_along / beam_bolt;
	float t = TIME * 22.0 + beam_seed * 50.0;

	// The burst: a spindle, fat just behind the head, whose outline boils.
	float body = smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.3, 1.0, u));
	float boil = 0.65 + 0.55 * noise(vec2(v_along * 0.22 + beam_seed * 31.0, t))
			+ 0.35 * (noise(vec2(v_along * 0.7 - beam_seed * 7.0, t * 1.7 + sign(s) * 5.0)) - 0.5);
	float radius = max(pow(body, 0.6) * boil, 0.02);
	float core = exp(-r * r * 3.2 / (radius * radius)) * body;
	float halo = exp(-r * r * 0.4 / (radius * radius)) * body
			* (0.7 + 0.5 * noise(vec2(s * 1.5 + beam_seed * 3.0, t * 1.3)));
	float flicker = 0.85 + 0.3 * noise(vec2(t * 0.8, beam_seed * 9.0));
	vec3 burst = (mix(beam_color, vec3(1.0), 0.85) * core * 3.0 + beam_color * halo * 1.6) * flicker * flying;

	// A few thin streaks behind it, each dying at its own length.
	float behind = v_along - beam_bolt * 0.55;
	float tail = clamp(behind / max(beam_speed * beam_trail, 1.0) + beam_dead / max(beam_trail, 0.001), 0.0, 1.0);
	float streaks = 0.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float lane = (fk - 1.0) * 0.7 + (noise(vec2(fk * 7.3 + beam_seed * 13.0, v_along * 0.05)) - 0.5) * 0.5;
		float reach = 0.45 + 0.55 * hash(vec2(fk, beam_seed * 17.0));
		float d = (s - lane) * 5.0;
		streaks += exp(-d * d) * (1.0 - smoothstep(reach * 0.6, reach, tail));
	}
	streaks *= step(0.0, behind) * (1.0 - tail) * (1.0 - tail);
	vec3 trail = mix(beam_color, vec3(1.0), 0.4) * streaks * 0.9;

	float edge = 1.0 - smoothstep(0.8, 1.0, abs(v_side));
	ALBEDO = (burst + trail) * beam_intensity * edge;
}
