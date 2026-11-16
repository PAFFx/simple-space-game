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

// Hatch aperture: a door-shaped rectangle cut out of the screen while the hatch is
// open, flat as seen from the centre (a rectangle on the plane facing aperture_center,
// half sizes as angles), so it reads as a doorway rather than a slice of the sphere.
// aperture_center = (azimuth, elevation) radians. It opens from the centre line outward.
uniform float aperture_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 aperture_center = vec2(0.0, 0.0);
uniform vec2 aperture_half_size = vec2(0.61, 0.61);

// The suit's own overlay (its outlines, or its body), drawn by the sensor head's second
// camera with the same view as sensor_viewport. While overlay_reveal goes 0 → 1 it
// resolves in: big blue blocks popping in at random, halving in size until they are the
// image itself; going 1 → 0 it breaks up the same way.
uniform sampler2D overlay_viewport : source_color, hint_default_transparent, filter_linear;
uniform float overlay_reveal = 0.0;
uniform vec3 overlay_tint : source_color = vec3(0.3, 0.62, 1.0);
uniform float overlay_block_px = 32.0;

#include "res://Entities/Vehicles/Cockpits/Components/PanoramicHud/Shader/hud_layers.gdshaderinc"


// Outlines mark their body with a faint fill (SensorOutline.fill_alpha): it counts while
// resolving, so the whole shape pixelates, and is dropped once in.
const float OVERLAY_FILL = 0.06;

vec4 overlay_drawn(vec4 o) {
	return vec4(o.rgb, clamp((o.a - OVERLAY_FILL) / (1.0 - OVERLAY_FILL), 0.0, 1.0));
}

vec3 composite_overlay(vec3 color, vec2 uv) {
	if (overlay_reveal <= 0.0) {
		return color;
	}
	if (overlay_reveal >= 1.0) {
		vec4 o = overlay_drawn(texture(overlay_viewport, uv));
		return mix(color, o.rgb, o.a);
	}
	float e = overlay_reveal;
	vec2 size = vec2(textureSize(overlay_viewport, 0));
	// Block size in steps of two: 32, 16, 8 ... 1 px.
	float block = exp2(floor(mix(log2(overlay_block_px), 0.0, e * e * (3.0 - 2.0 * e)) + 0.5));
	vec2 px = uv * size;
	vec2 cell = floor(px / block);
	vec2 origin = cell * block;
	// Over the block: how much of it is the shape, and the drawn image's average.
	vec3 rgb = vec3(0.0);
	float drawn = 0.0;
	float cover = 0.0;
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			vec4 s = texture(overlay_viewport, (origin + (vec2(float(i), float(j)) + 0.5) * block / 4.0) / size);
			cover += step(0.01, s.a);
			vec4 d = overlay_drawn(s);
			rgb += d.rgb * d.a;
			drawn += d.a;
		}
	}
	rgb /= max(drawn, 1e-4);
	cover /= 16.0;
	drawn /= 16.0;
	// Blocks pop in at random (a new pattern at each block size).
	float h = fract(sin(dot(cell + vec2(block * 13.1, block * 7.7), vec2(12.9898, 78.233))) * 43758.5453);
	float shown = step(h, e * 1.5);
	// Blue blocks over the whole shape while it resolves, with brighter block edges; at the
	// end only what is really drawn (the outline itself) is left, in its own colours.
	vec2 f = fract(px / block);
	float edge = block > 2.0 ? step(min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)) * block, 1.0) : 0.0;
	float lum = dot(rgb, vec3(0.3, 0.5, 0.2)) * drawn;
	vec3 blue = overlay_tint * (0.55 + lum * 1.5) * (1.0 + edge * 0.8);
	float settle = smoothstep(0.55, 1.0, e);
	float alpha = mix(clamp(cover * 1.6, 0.0, 0.85), clamp(drawn, 0.0, 1.0), settle) * shown;
	return mix(color, mix(blue, rgb, settle), alpha);
}


void fragment() {
	// --- Step 1: Recover azimuth and elevation from UV2 ---
	// UV2.x = azimuth / TAU  (absolute angle, may be negative or > 1 due to arc_offset)
	// UV2.y = elevation normalised [0, 1]  (0 = bottom edge, 1 = top edge)
	float azimuth   = UV2.x * TAU;
	float elevation = (UV2.y - 0.5) * panoramic_elevation_range;

	// --- Step 2: Cut the hatch aperture while the hatch is open ---
	if (aperture_amount > 0.0) {
		float ce = cos(aperture_center.y);
		vec3 c = vec3(sin(aperture_center.x) * ce, sin(aperture_center.y), -cos(aperture_center.x) * ce);
		vec3 r = vec3(cos(aperture_center.x), 0.0, sin(aperture_center.x));
		vec3 u = cross(r, c);
		float cel = cos(elevation);
		vec3 d = vec3(sin(azimuth) * cel, sin(elevation), -cos(azimuth) * cel);
		float depth = dot(d, c);
		if (depth > 0.0) {
			vec2 p = vec2(dot(d, r), dot(d, u)) / depth;
			if (abs(p.x) < tan(aperture_half_size.x)
					&& abs(p.y) < tan(aperture_half_size.y) * aperture_amount) {
				discard;
			}
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
				color = composite_overlay(color, sample_uv);
			}
		}

		// --- Step 7: Composite the HUD on top of the sensor image ---
		// Fixed layers first (drawn once, turned into place), then the per-frame canvas.
		color = hud_layers(color, local_dir, hud_brightness);
		vec2 hud_uv = vec2(fract(UV2.x + 0.5), 1.0 - UV2.y);
		vec4 hud = texture(hud_texture, hud_uv);
		color = mix(color, hud.rgb * hud_brightness, hud.a);
	}

	ALBEDO   = color;
	EMISSION = color;
}
