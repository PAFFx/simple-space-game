shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Exhaust plume on the thruster's cone mesh (axis +Y, nozzle at y = -0.5, tip at +0.5).
// Hot near the nozzle, cooling and breaking up downstream, with standing shock diamonds.
// Burst (pintles open): 4x the throat at the same exit, so the jet leaves under-expanded and
// balloons past the lip; 16x the mass on the same power runs denser and cooler.

uniform vec3 hot_color : source_color = vec3(1.0, 0.96, 0.9);
uniform vec3 mid_color : source_color = vec3(0.52, 0.8, 1.0);
uniform vec3 tail_color : source_color = vec3(0.25, 0.45, 1.0);
uniform float energy = 2.0;
// How sharply the plume fades toward its silhouette (higher = thinner, softer edge).
uniform float edge_power = 1.6;
// Radius profile: < 1 keeps the plume full for longer before it pinches to the tip.
uniform float taper_power = 0.65;
// The mesh's own radii, so the profile can be reshaped from them.
uniform float base_radius = 0.38;
uniform float tip_radius = 0.06;
uniform float diamond_strength = 0.65;
// How much the jet dims between diamonds (0 = not at all), so the bands read.
uniform float diamond_dip = 0.15;
uniform float turbulence = 0.55;
uniform float noise_scale = 2.2;
uniform float scroll_speed = 9.0;    // turbulence downstream speed, plume lengths/s-ish
// Burst look: extra radius past the lip (fraction), how much fuller the body reads
// (edge_power multiplier), extra brightness, and the cooler, denser colours.
uniform float burst_spread = 0.7;
uniform float burst_edge = 0.45;
uniform float burst_energy = 0.7;
uniform vec3 burst_hot_color : source_color = vec3(1.0, 0.94, 0.84);
uniform vec3 burst_mid_color : source_color = vec3(0.86, 0.9, 1.0);

instance uniform float throttle = 1.0;
instance uniform float length_m = 5.0;     // plume length now, m
instance uniform float diamonds = 4.0;     // shock diamonds over the plume's length
instance uniform float seed = 0.0;
instance uniform float burst = 0.0;        // 0 = pintles closed, 1 = fully open

varying float s;
varying vec3 ring;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	s = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	float linear_r = mix(base_radius, tip_radius, s);
	float shaped_r = mix(tip_radius, base_radius, pow(1.0 - s, taper_power));
	// Under-expanded: the lip stays the nozzle's size, the jet swells just past it.
	shaped_r *= 1.0 + burst * burst_spread * smoothstep(0.0, 0.2, s) * (1.0 - 0.5 * s);
	VERTEX.xz *= shaped_r / max(linear_r, 1e-4);
	ring = vec3(normalize(VERTEX.xz + vec2(1e-5)), 0.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, edge_power * mix(1.0, burst_edge, burst));

	// Turbulence scrolls downstream and grows with distance from the nozzle.
	float t = TIME * scroll_speed;
	vec3 p = vec3(ring.xy * noise_scale, s * length_m * 0.6 - t) + seed;
	float n = noise(p) * 0.65 + noise(p * 2.3 + 7.1) * 0.35;
	float turb = mix(1.0, 0.35 + 1.3 * n, turbulence * smoothstep(0.0, 0.6, s));

	// Standing shock diamonds in the hot inner part, stronger at full throttle.
	float wave = 0.5 + 0.5 * cos((s * diamonds - 0.15) * TAU);
	float shocks = smoothstep(0.75, 0.05, s) * smoothstep(0.3, 1.0, throttle);
	float diamond = pow(wave, 6.0) * shocks * diamond_strength * (1.0 + 0.5 * burst) * facing;
	turb *= 1.0 - diamond_dip * shocks * (1.0 - wave);

	float fade = pow(1.0 - s, 1.1) * smoothstep(0.0, 0.04, s + 0.02);
	float intensity = body * fade * turb + diamond * fade;

	vec3 hot = mix(hot_color, burst_hot_color, burst);
	vec3 mid = mix(mid_color, burst_mid_color, burst);
	vec3 col = mix(hot, mid, smoothstep(0.0, 0.35 + 0.2 * burst, s));
	col = mix(col, tail_color, smoothstep(0.3, 1.0, s));
	col = mix(tail_color, col, body);
	col = mix(col, hot, clamp(diamond, 0.0, 1.0));

	ALBEDO = col * energy * mix(0.6, 1.0, throttle) * (1.0 + burst * burst_energy);
	ALPHA = clamp(intensity, 0.0, 1.0);
}
