// HUD layers: fixed pictures drawn once by GDScript (PanoramicHud.add_layer_drawer), each
// in its own frame, turned into place here per pixel by a rotation uniform. Same
// equirectangular layout as hud_texture; `frame` maps a display direction into the layer's.
// Needs panoramic_elevation_range (declared by the including shader).

// Display frame (not moving): ring outlines, box frames, fixed pointers.
uniform sampler2D hud_static_texture : source_color, hint_default_transparent, filter_linear, repeat_enable;
// Course ring marks, turned with the heading.
uniform sampler2D hud_heading_texture : source_color, hint_default_transparent, filter_linear, repeat_enable;
uniform mat3 hud_heading_frame = mat3(1.0);
// Suit line and its arrowheads, in the suit body's frame.
uniform sampler2D hud_suit_texture : source_color, hint_default_transparent, filter_linear, repeat_enable;
uniform mat3 hud_suit_frame = mat3(1.0);

// Pitch ladder, turned with the pitch. Coverage, not colour: R = stroke, G = halo,
// B = stroke × tick strength, so fade and climb highlight can follow the pitch here.
uniform sampler2D hud_ladder_texture : hint_default_transparent, filter_linear, repeat_enable;
uniform mat3 hud_ladder_frame = mat3(1.0);
// Colours as drawn on the HUD canvas: sRGB, so Godot must not linearize them on the way in.
uniform vec4 hud_ladder_color : source_color, color_conversion_disabled = vec4(0.58, 0.72, 0.82, 0.8);
uniform vec4 hud_ladder_lit_color : source_color, color_conversion_disabled = vec4(0.88, 0.91, 0.93, 0.92);
uniform vec4 hud_ladder_halo_color : source_color, color_conversion_disabled = vec4(0.0, 0.0, 0.0, 0.55);
uniform float hud_pitch_deg = 0.0;
// x = focus, y = fade length, z = fade floor (deg, deg, 0..1).
uniform vec3 hud_ladder_fade = vec3(25.0, 30.0, 0.3);
// x = eased reveal (0 = off), y = highlight head (deg from pitch), z = span, w = width (deg).
uniform vec4 hud_climb = vec4(0.0, 0.0, 35.0, 5.0);


vec2 hud_layer_uv(mat3 frame, vec3 local_dir) {
	vec3 d = frame * local_dir;
	float az = atan(d.x, -d.z);
	float el = asin(clamp(d.y, -1.0, 1.0));
	return vec2(az / TAU + 0.5, 0.5 - el / panoramic_elevation_range);
}


// A layer's texel for a display direction; nothing outside the canvas's elevation range
// (the textures repeat for the azimuth seam, which must not wrap them vertically).
vec4 hud_sample(sampler2D layer, mat3 frame, vec3 local_dir) {
	vec2 uv = hud_layer_uv(frame, local_dir);
	if (uv.y < 0.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(layer, uv);
}


vec3 hud_over(vec3 color, vec4 layer, float brightness) {
	return mix(color, layer.rgb * brightness, layer.a);
}


vec3 hud_srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}


// The ladder as the 2D canvas would have blended it (halo, then the lit stroke over it),
// converted and composited like hud_texture.
vec3 hud_ladder(vec3 color, vec3 local_dir, float brightness) {
	vec3 d = hud_ladder_frame * local_dir;
	vec4 cov = hud_sample(hud_ladder_texture, hud_ladder_frame, local_dir);
	if (cov.r + cov.g < 0.002) {
		return color;
	}
	// A tick's pitch is its angle about the ladder's right axis; ticks run along it.
	float off = degrees(atan(d.y, -d.z)) - hud_pitch_deg;
	float fade = mix(1.0, hud_ladder_fade.z,
			clamp((abs(off) - hud_ladder_fade.x) / hud_ladder_fade.y, 0.0, 1.0));
	float glow = 0.0;
	if (hud_climb.x > 0.0 && abs(off) <= hud_climb.z) {
		float band = hud_climb.z * 2.0;
		float dist = abs(off - hud_climb.y);
		dist = min(dist, band - dist);
		glow = exp(-pow(dist / hud_climb.w, 2.0)) * hud_climb.x;
	}
	float strength = cov.r > 0.002 ? clamp(cov.b / cov.r, 0.0, 1.0) : 0.0;
	vec3 lit = mix(hud_ladder_color.rgb, hud_ladder_lit_color.rgb, glow);
	float lit_a = mix(hud_ladder_color.a * fade * strength, hud_ladder_lit_color.a, glow);

	float halo_a = hud_ladder_halo_color.a * cov.g;
	vec3 rgb = hud_ladder_halo_color.rgb * halo_a;
	float a = halo_a;
	float stroke_a = lit_a * cov.r;
	rgb = lit * stroke_a + rgb * (1.0 - stroke_a);
	a = stroke_a + a * (1.0 - stroke_a);
	return mix(color, hud_srgb_to_linear(rgb) * brightness, a);
}


vec3 hud_layers(vec3 color, vec3 local_dir, float brightness) {
	color = hud_over(color, hud_sample(hud_static_texture, mat3(1.0), local_dir), brightness);
	color = hud_over(color, hud_sample(hud_heading_texture, hud_heading_frame, local_dir), brightness);
	color = hud_ladder(color, local_dir, brightness);
	color = hud_over(color, hud_sample(hud_suit_texture, hud_suit_frame, local_dir), brightness);
	return color;
}
