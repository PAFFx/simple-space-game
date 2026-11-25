// Overlay on a part's mesh: its painted camera lenses glow. Each lens is an atlas UV rect;
// only the green paint inside it lights up, by that camera's energy (0 once it is shot out).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 glow_color : source_color = vec4(0.35, 1.0, 0.55, 1.0);
uniform int lens_count = 0;
uniform vec4 lens_rect[8];      // uv min xy, uv max xy
uniform float lens_energy[8];

void fragment() {
	vec3 c = texture(albedo_texture, UV).rgb;
	float green = smoothstep(0.02, 0.1, c.g - max(c.r * 1.2, c.b));
	float e = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= lens_count) {
			break;
		}
		vec4 r = lens_rect[i];
		if (all(greaterThanEqual(UV, r.xy)) && all(lessThanEqual(UV, r.zw))) {
			e = max(e, lens_energy[i]);
		}
	}
	ALBEDO = glow_color.rgb * green * e;
}
