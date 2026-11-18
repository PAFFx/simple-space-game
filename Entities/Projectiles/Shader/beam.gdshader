// A beam: one straight line of condensed Minovsky particles. A thin white-hot core in a
// tight coloured glow, with fine grain flowing along it, a pointed front, and behind it a
// faint wake where it has just passed, breaking up within beam_trail.
// Drawn on a camera-facing strip from the front (model z = 0) back (z = 1, scaled by the
// node to beam_length m), widened in view space (double precision safe).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

instance uniform vec3 beam_color : source_color = vec3(1.0, 0.15, 0.1);
instance uniform float beam_length = 1000.0;  // strip, m: the beam and its wake
// Metres of beam from the front back to its tail; beyond that is wake. Negative once the
// tail has passed the front (the beam is gone, only the wake is left).
instance uniform float beam_body = 1000.0;
instance uniform float beam_width = 0.7;      // core radius, m
instance uniform float beam_speed = 3000.0;
instance uniform float beam_trail = 0.15;     // wake life, s
instance uniform float beam_intensity = 10.0;
// 1: the front is free and comes to a point; 0: it ends on something it hit.
instance uniform float beam_tip = 1.0;
// 0..1: the front has reached its range and is dissipating there.
instance uniform float beam_fizzle = 0.0;
// 0: the tail is on the barrel; 1: let go, the tail tapers off.
instance uniform float beam_free = 0.0;
instance uniform float beam_seed = 0.0;
uniform float min_angle = 0.0022;
uniform float max_angle = 0.02;
// Strip half-width, in core radii.
uniform float spread = 4.0;
uniform float core_share = 0.3;   // core radius / glow radius
uniform float grain = 0.15;       // particle grain in the glow (0 = smooth)
uniform float grain_flow = 900.0; // m/s the grain seems to stream outward
uniform float wake_glow = 0.22;
uniform float fizzle_length = 140.0;

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
	float half_width = beam_width * spread;
	float dist = length(centre);
	float wanted = min(half_width, max_angle * dist);
	half_width = max(wanted, min_angle * dist);
	// Stretched to stay visible far away: the beam then fills more of the strip.
	v_widen = half_width / wanted;
	vec3 to_eye = normalize(-centre);
	vec3 right = cross(axis, to_eye);
	float len = length(right);
	right = len > 1e-4 ? right / len : vec3(1.0, 0.0, 0.0);
	VERTEX = centre + right * v_side * half_width;
	NORMAL = to_eye;
}

void fragment() {
	// Across the strip in core radii.
	float r = abs(v_side) * spread / min(v_widen, spread);
	float t = TIME;
	float a = v_along;
	// Metres behind the tail (negative: inside the beam), and how long ago it passed there.
	float behind = a - beam_body;
	float glow_r = 1.0 / core_share;

	// --- The beam itself ---
	float in_beam = 1.0 - step(0.0, behind);
	// Pointed front, and a tapering tail once let go.
	float tip = mix(1.0, smoothstep(0.0, beam_width * 30.0, a), beam_tip);
	float tail = mix(1.0, smoothstep(0.0, beam_width * 30.0, -behind), beam_free);
	float shape = tip * tail;
	// Dissipating at its range: the front fades and loosens into grain.
	float fz = beam_fizzle * (1.0 - smoothstep(0.0, fizzle_length, a));
	float flow = a + t * grain_flow;
	float g = noise(vec2(flow * 0.08 + beam_seed * 37.0, v_side * 6.0 + t * 9.0));
	float g2 = noise(vec2(flow * 0.31 - beam_seed * 11.0, v_side * 13.0 - t * 5.0));
	float grainy = mix(1.0, 0.55 + 0.9 * g * g2 * 1.6, grain + fz * 0.6);
	float core = exp(-r * r * 2.0) * (1.0 - fz);
	float halo_r = glow_r * mix(0.9, 1.3, fz) * mix(0.6, 1.0, shape);
	float halo = exp(-r * r * 2.6 / (halo_r * halo_r)) * grainy * (1.0 - fz * 0.75);
	vec3 beam = (mix(beam_color, vec3(1.0), 0.9) * core * 2.6 + beam_color * halo * 1.3)
			* shape * in_beam;

	// --- The wake it leaves where it has just passed ---
	float age = clamp(behind / max(beam_speed * beam_trail, 1.0), 0.0, 1.0);
	float n = noise(vec2(a * 0.045 + beam_seed * 19.0, v_side * 3.0 + t * 1.5));
	float broken = smoothstep(age * 1.1 - 0.25, age * 1.1 + 0.15, n);
	float wake_r = glow_r * (0.45 + 0.7 * age);
	float wake = exp(-r * r * 2.0 / (wake_r * wake_r)) * broken * (1.0 - age) * (1.0 - age)
			* step(0.0, behind) * wake_glow;
	vec3 trail = mix(beam_color, vec3(1.0), 0.25) * wake;

	float edge = 1.0 - smoothstep(0.8, 1.0, abs(v_side));
	ALBEDO = (beam + trail) * beam_intensity * edge;
}
