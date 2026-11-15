// A cockpit display showing its page. The page is drawn much larger than it shows on
// screen, so each pixel averages a 4×4 grid of samples over its own footprint on the page
// (an area filter): small text stays readable instead of breaking up into jagged pixels.
shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

uniform sampler2D page : source_color, filter_linear;
uniform float brightness = 1.15;

void fragment() {
	// The panels face the eye turned past 90°: flip the page to read upright.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			vec2 o = (vec2(float(i), float(j)) + 0.5) / 4.0 - 0.5;
			sum += texture(page, uv + dx * o.x + dy * o.y).rgb;
		}
	}
	ALBEDO = sum / 16.0 * brightness;
}
