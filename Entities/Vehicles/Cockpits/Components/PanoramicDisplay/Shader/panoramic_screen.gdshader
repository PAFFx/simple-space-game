shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// The sensor camera's rendered viewport texture.
uniform sampler2D sensor_viewport : source_color, hint_default_black, filter_linear_mipmap;

// Combined (projection * view) matrix of the sensor camera, updated every frame.
uniform mat4 sensor_view_proj;

// World-space position of the sensor camera.
// Used as the ray origin when projecting panoramic directions.
uniform vec3 sensor_world_pos;

// World-space orientation of the sensor camera (columns: right, up, -forward).
// Transforms local panoramic directions into world space.
uniform mat3 sensor_basis;

// Total vertical angle span of the screen in radians (default PI/2 = ±45°).
uniform float panoramic_elevation_range = 1.5707963;

// 1D segment mask texture (segment_count × 1 pixels).
// R channel: 1.0 = segment active, 0.0 = segment disabled (damaged / door open).
// Sampled via fract(UV2.x) so any arc_offset is handled automatically.
uniform sampler2D segment_mask : hint_default_white, filter_nearest;

// Emissive brightness multiplier for the screen output.
uniform float screen_brightness : hint_range(0.0, 5.0) = 1.5;

// Color shown when the projected UV falls outside the sensor viewport.
uniform vec4 no_signal_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);

// Color shown when a segment is disabled (damaged panel or open door).
uniform vec4 damaged_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);


void fragment() {
	// --- Step 1: Recover azimuth and elevation from UV2 ---
	// UV2.x = azimuth / TAU  (absolute angle, may be negative or > 1 due to arc_offset)
	// UV2.y = elevation normalised [0, 1]  (0 = bottom edge, 1 = top edge)
	float azimuth   = UV2.x * TAU;
	float elevation = (UV2.y - 0.5) * panoramic_elevation_range;

	// --- Step 2: Check the segment mask ---
	// fract() wraps any arc_offset so the mask always indexes [0, 1] correctly.
	float active = texture(segment_mask, vec2(fract(UV2.x), 0.5)).r;

	if (active < 0.5) {
		ALBEDO   = damaged_color.rgb;
		EMISSION = damaged_color.rgb;
	} else {
		// --- Step 3: Build the world-space direction this fragment represents ---
		// Local convention: azimuth=0 → forward = (0, 0, -1) in sensor local space.
		float cos_el   = cos(elevation);
		vec3 local_dir = vec3(
			 sin(azimuth) * cos_el,   // right
			 sin(elevation),           // up
			-cos(azimuth) * cos_el    // forward (-Z in Godot right-hand convention)
		);
		vec3 world_dir = sensor_basis * local_dir;

		// --- Step 4: Project the direction through the sensor camera ---
		// Project a point far along the ray to avoid near-plane clipping artefacts.
		vec4 clip = sensor_view_proj * vec4(sensor_world_pos + world_dir * 500.0, 1.0);

		if (clip.w <= 0.0) {
			// Fragment is behind the sensor camera.
			ALBEDO   = no_signal_color.rgb;
			EMISSION = no_signal_color.rgb;
		} else {
			// Perspective divide → NDC [-1, 1].
			vec2 ndc = clip.xy / clip.w;

			// Remap NDC to UV [0, 1].
			// Godot SubViewport texture origin is top-left (Y increases downward),
			// while NDC Y increases upward — so flip Y during remap.
			vec2 sample_uv = vec2(
				 ndc.x * 0.5 + 0.5,
				1.0 - (ndc.y * 0.5 + 0.5)
			);

			// --- Step 5: Bounds check, then sample ---
			if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
				ALBEDO   = no_signal_color.rgb;
				EMISSION = no_signal_color.rgb;
			} else {
				vec3 color = texture(sensor_viewport, sample_uv).rgb * screen_brightness;
				ALBEDO   = color;
				EMISSION = color;
			}
		}
	}
}
