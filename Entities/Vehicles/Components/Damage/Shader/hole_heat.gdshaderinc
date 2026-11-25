// Hot metal: its blackbody colour and glow, and how a spot cools in vacuum. Shared by the
// beam holes and the cockpit screen's, so both glow and cool in step.

vec3 hole_blackbody(float t) {
	float x = clamp((t - 700.0) / 2300.0, 0.0, 1.0);
	vec3 c = mix(vec3(0.45, 0.012, 0.0), vec3(1.0, 0.12, 0.01), smoothstep(0.0, 0.2, x));
	c = mix(c, vec3(1.0, 0.42, 0.06), smoothstep(0.15, 0.45, x));
	c = mix(c, vec3(1.0, 0.78, 0.4), smoothstep(0.4, 0.75, x));
	return mix(c, vec3(1.0, 0.96, 0.9), smoothstep(0.7, 1.0, x));
}

// How bright hot metal glows (HDR energy): next to nothing below ~750 K, ∝ T⁴ beyond.
float hole_glow(float t) {
	float k = max(t - 720.0, 0.0) / 1300.0;
	return min(k * k * k * 1.6 + k * 0.45, 5.0);
}

// Temperature a spot that peaked at `peak` K has after `age` s in vacuum: radiation
// (T⁻³ grows linearly) and conduction into the rest of the part.
float hole_cool(float peak, float age) {
	return 290.0 + (peak - 290.0) * pow(1.0 + max(age, 0.0) / 4.0, -0.3333) * exp(-max(age, 0.0) / 28.0);
}
