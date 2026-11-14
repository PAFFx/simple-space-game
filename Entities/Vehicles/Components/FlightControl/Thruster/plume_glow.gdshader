shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Camera-facing flare at the nozzle: a soft halo, a hot centre and a faint lens streak.

uniform vec3 color : source_color = vec3(0.6, 0.82, 1.0);
uniform vec3 core_color : source_color = vec3(1.0, 0.97, 0.92);
uniform float energy = 2.0;
uniform float streak = 0.35;
// Pulled toward the camera (in quad sizes) so armour around a recessed port doesn't hide it.
uniform float camera_pull = 0.5;

instance uniform float throttle = 1.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	// Billboard in view space, keeping the engine's view-space origin: rebuilding it from
	// MODEL_MATRIX[3] (world space, 32-bit on the GPU) jitters far from the world origin.
	MODELVIEW_MATRIX = mat4(vec4(scale.x, 0, 0, 0), vec4(0, scale.y, 0, 0), vec4(0, 0, scale.z, 0), MODELVIEW_MATRIX[3]);
	MODELVIEW_MATRIX[3].xyz += normalize(-MODELVIEW_MATRIX[3].xyz) * camera_pull * scale.x;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float halo = pow(max(0.0, 1.0 - d), 2.5);
	float core = pow(max(0.0, 1.0 - d), 14.0);
	float line = exp(-abs(uv.y) * 40.0) * max(0.0, 1.0 - abs(uv.x)) * streak;
	ALBEDO = (color * (halo + line) + core_color * core * 2.0) * energy;
	ALPHA = clamp((halo + core + line) * throttle, 0.0, 1.0);
}
