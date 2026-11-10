shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// The sensor camera's rendered viewport texture.
uniform sampler2D sensor_viewport : source_color, hint_default_black, filter_linear_mipmap;

// Combined (projection * view) matrix of the sensor camera, updated every frame.
uniform mat4 sensor_view_proj;

// World-space position of the sensor camera.
// Used as the ray origin when projecting panoramic directions.
uniform vec3 sensor_world_pos;

// World-space orientation of the screen itself. A screen-local direction d
// shows the world in direction display_basis * d, so the picture stays true
// even when the cockpit (and screen) rotate relative to the sensor.
uniform mat3 display_basis;

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

// HUD overlay drawn in equirectangular panoramic space:
// x = azimuth (forward at 0.5, wraps at the back), y = elevation (top = +90°).
uniform sampler2D hud_texture : source_color, hint_default_transparent, filter_linear, repeat_enable;
uniform float hud_brightness : hint_range(0.0, 5.0) = 1.2;

// Hatch aperture: a rectangle in (azimuth, elevation) radians that is cut out of
// the screen while the hatch is open. It opens from the centre line outward.
uniform float aperture_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 aperture_center = vec2(0.0, 0.0);
uniform vec2 aperture_half_size = vec2(0.61, 0.61);


void fragment() {
	// --- Step 1: Recover azimuth and elevation from UV2 ---
	// UV2.x = azimuth / TAU  (absolute angle, may be negative or > 1 due to arc_offset)
	// UV2.y = elevation normalised [0, 1]  (0 = bottom edge, 1 = top edge)
	float azimuth   = UV2.x * TAU;
	float elevation = (UV2.y - 0.5) * panoramic_elevation_range;

	// --- Step 2: Cut the hatch aperture while the hatch is open ---
	if (aperture_amount > 0.0) {
		float d_az = mod(azimuth - aperture_center.x + PI, TAU) - PI;
		float d_el = elevation - aperture_center.y;
		if (abs(d_az) < aperture_half_size.x && abs(d_el) < aperture_half_size.y * aperture_amount) {
			discard;
		}
	}

	// --- Step 3: Check the segment mask ---
	// fract() wraps any arc_offset so the mask always indexes [0, 1] correctly.
	float active = texture(segment_mask, vec2(fract(UV2.x), 0.5)).r;

	vec3 color;
	if (active < 0.5) {
		color = damaged_color.rgb;
	} else {
		// --- Step 4: Build the world-space direction this fragment represents ---
		// Local convention: azimuth=0 → forward = (0, 0, -1) in sensor local space.
		float cos_el   = cos(elevation);
		vec3 local_dir = vec3(
			 sin(azimuth) * cos_el,   // right
			 sin(elevation),           // up
			-cos(azimuth) * cos_el    // forward (-Z in Godot right-hand convention)
		);
		vec3 world_dir = display_basis * local_dir;

		// --- Step 5: Project the direction through the sensor camera ---
		// Project a point far along the ray to avoid near-plane clipping artefacts.
		vec4 clip = sensor_view_proj * vec4(sensor_world_pos + world_dir * 500.0, 1.0);

		color = no_signal_color.rgb;
		if (clip.w > 0.0) {
			// Perspective divide → NDC [-1, 1].
			vec2 ndc = clip.xy / clip.w;

			// Remap NDC to UV [0, 1].
			// Godot SubViewport texture origin is top-left (Y increases downward),
			// while NDC Y increases upward — so flip Y during remap.
			vec2 sample_uv = vec2(
				 ndc.x * 0.5 + 0.5,
				1.0 - (ndc.y * 0.5 + 0.5)
			);

			// --- Step 6: Bounds check, then sample ---
			if (all(greaterThanEqual(sample_uv, vec2(0.0))) && all(lessThanEqual(sample_uv, vec2(1.0)))) {
				color = texture(sensor_viewport, sample_uv).rgb * screen_brightness;
			}
		}

		// --- Step 7: Composite the HUD on top of the sensor image ---
		vec2 hud_uv = vec2(fract(UV2.x + 0.5), 1.0 - UV2.y);
		vec4 hud = texture(hud_texture, hud_uv);
		color = mix(color, hud.rgb * hud_brightness, hud.a);
	}

	ALBEDO   = color;
	EMISSION = color;
}
