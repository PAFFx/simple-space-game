// A round glow that always faces the camera: bolt heads, muzzle flashes, impacts.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

instance uniform vec3 flash_color : source_color = vec3(1.0, 0.3, 0.2);
instance uniform float flash_intensity = 1.0;
instance uniform float flash_size = 5.0;     // radius, m
// Share of white-hot core in the middle, 0..1.
instance uniform float flash_core = 0.5;
// Streaks radiating from the middle, 0..1.
instance uniform float flash_rays = 0.0;
instance uniform float flash_seed = 0.0;
uniform float min_angle = 0.0016;
// Nor bigger than this (rad), and faded out right at the camera: a hit on the viewer's
// own suit is a flash, not a white screen.
uniform float max_angle = 0.22;

varying float v_near;

void vertex() {
	vec3 centre = MODELVIEW_MATRIX[3].xyz;
	float dist = length(centre);
	float size = max(min(flash_size, max_angle * dist), min_angle * dist);
	v_near = smoothstep(1.0, 14.0, dist);
	VERTEX = centre + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float glow = exp(-r * r * 5.0);
	float core = exp(-r * r * 45.0) * flash_core * 3.0;
	float a = atan(p.y, p.x);
	float rays = pow(abs(sin(a * 4.0 + flash_seed * 6.0)) * abs(sin(a * 7.0 - flash_seed * 11.0)), 6.0)
			* exp(-r * 3.0) * flash_rays * 4.0;
	float edge = 1.0 - smoothstep(0.75, 1.0, r);
	ALBEDO = (flash_color * (glow + rays) + vec3(1.0) * (core + rays * 0.5)) * flash_intensity * edge * v_near;
}
