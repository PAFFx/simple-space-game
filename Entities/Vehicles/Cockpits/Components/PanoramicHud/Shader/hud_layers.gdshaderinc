// HUD layers: fixed pictures drawn once by GDScript (PanoramicHud.add_layer_drawer), each
// in its own frame, turned into place here per pixel by a rotation uniform. Small symbols
// (control centre, flight path marker) are drawn here outright. Same
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

// Flight path markers, prograde drawn at the layer's -X and retrograde at +X (both upright),
// turned onto the velocity. Coverage: R = stripe, G = halo, B = other strokes × their fade;
// the highlight, tint, fade-in and pulse are applied here.
uniform sampler2D hud_fpm_texture : hint_default_transparent, filter_linear, repeat_enable;
uniform mat3 hud_fpm_frame = mat3(1.0);
uniform vec4 hud_fpm_color : source_color, color_conversion_disabled = vec4(0.88, 0.91, 0.93, 0.92);
uniform vec4 hud_fpm_retro_color : source_color, color_conversion_disabled = vec4(0.88, 0.91, 0.93, 0.644);
uniform vec4 hud_fpm_accent_color : source_color, color_conversion_disabled = vec4(0.9, 0.42, 0.66, 0.9);
uniform vec4 hud_fpm_halo_color : source_color, color_conversion_disabled = vec4(0.0, 0.0, 0.0, 0.55);
// As drawn: x = bar start, y = bar length, z = stripe lean (signed), w = stripe half height (deg).
uniform vec4 hud_fpm_bar = vec4(3.0, 24.0, 0.75, 0.45);
// x = stripe count, y = spacing power, z = base alpha, w = highlight width (fraction of bar).
uniform vec4 hud_fpm_stripes = vec4(16.0, 1.7, 0.3, 0.12);
// x = grow (0 = hidden), y = highlight head, z = full boost, w = kick.
uniform vec4 hud_fpm_anim = vec4(0.0);
uniform float hud_fpm_pulse = 1.0;
// Half the side of the marker triangle at the middle, deg.
uniform float hud_fpm_marker = 1.0;

// Symbols drawn here from distance functions instead of from a layer: sharp at any zoom,
// and nothing to redraw. Their dark edge, as on the canvas:
uniform vec4 hud_symbol_halo_color : source_color, color_conversion_disabled = vec4(0.0, 0.0, 0.0, 0.55);
uniform float hud_symbol_halo_deg = 0.13;

// Control centre: chevrons around the control frame's -Z (display → control frame).
// Off while the colour's alpha is 0.
uniform mat3 hud_control_frame = mat3(1.0);
uniform vec4 hud_control_color : source_color, color_conversion_disabled = vec4(0.0);
uniform vec4 hud_control_accent_color : source_color, color_conversion_disabled = vec4(0.9, 0.42, 0.66, 0.54);
// The bands' fill, as a share of their border's alpha.
uniform float hud_control_fill = 0.75;
uniform float hud_control_scale = 1.0;


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


// One more stroke on a symbol built up the way the canvas blends (premultiplied).
void hud_ink(inout vec4 acc, vec4 c, float coverage) {
	float a = c.a * clamp(coverage, 0.0, 1.0);
	acc = vec4(c.rgb * a + acc.rgb * (1.0 - a), a + acc.a * (1.0 - a));
}


// Converted and composited like hud_texture.
vec3 hud_compose(vec3 color, vec4 acc, float brightness) {
	return mix(color, hud_srgb_to_linear(acc.rgb) * brightness, acc.a);
}


// Coverage of a shape from its signed distance (deg, < 0 inside), antialiased over `aa`.
float hud_fill(float sd, float aa) {
	return 1.0 - smoothstep(-aa, aa, sd);
}


float hud_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}


// Chevron with its point at `tip`, mirrored in x (q.x = |x|): one arm runs along `arm`
// (unit) for `len`, `half_width` to each side. Sharp at the point, cut square at the ends.
float hud_chevron(vec2 q, vec2 tip, vec2 arm, float len, float half_width) {
	vec2 r = q - tip;
	return max(abs(dot(r, vec2(-arm.y, arm.x))) - half_width, dot(r, arm) - len);
}


// Triangle with a corner pointing up, sides 2 × r, centred on its middle.
float hud_triangle(vec2 p, float r) {
	const float k = 1.7320508;
	p.x = abs(p.x) - r;
	p.y = p.y + r / k;
	if (p.x + k * p.y > 0.0) {
		p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
	}
	p.x -= clamp(p.x, -2.0 * r, 0.0);
	return -length(p) * sign(p.y);
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


float hud_fpm_glow(float u, float head, float width) {
	float d = abs(u - head);
	d = min(d, 1.0 - d);
	return exp(-pow(d / width, 2.0));
}


// Bar position (0 = inner end) of the stripe nearest the patch point p (deg). A stripe at
// x runs from (x + lean, h) to (x − lean, −h), its lean growing a little outward.
float hud_fpm_stripe_u(vec2 p) {
	float n = hud_fpm_stripes.x - 1.0;
	float k = p.y / hud_fpm_bar.w;
	float ax = abs(p.x);
	float x0 = ax - hud_fpm_bar.z * 0.85 * k;
	float guess = round(pow(clamp((x0 - hud_fpm_bar.x) / hud_fpm_bar.y, 0.0, 1.0),
			1.0 / hud_fpm_stripes.y) * n);
	float best = 1e9;
	float best_u = 0.0;
	for (float i = max(guess - 1.0, 0.0); i <= min(guess + 1.0, n); i += 1.0) {
		float u = i / n;
		float x = hud_fpm_bar.x + hud_fpm_bar.y * pow(u, hud_fpm_stripes.y)
				+ hud_fpm_bar.z * (0.7 + 0.3 * u) * k;
		float e = abs(ax - x);
		if (e < best) {
			best = e;
			best_u = u;
		}
	}
	return best_u;
}


// The marker at the middle: prograde a filled triangle pointing down with a solid core and
// wings; retrograde its empty counterpart pointing up, only the rim's three corners and a
// hollow core. `m` in marker units.
void hud_fpm_marker_ink(inout vec4 acc, vec2 m, bool pro, vec4 c, float aa) {
	vec2 up = pro ? vec2(m.x, -m.y) : m;
	float tri = hud_triangle(up, 1.0);
	float rim = abs(tri + 0.07) - 0.07;
	float strokes = rim;
	if (pro) {
		float core = hud_triangle(up, 0.36);
		float wings = max(abs(m.y) - 0.065, abs(abs(m.x) - 1.95) - 0.45);
		float inner = abs(tri + 0.36) - 0.03;
		strokes = min(rim, min(core, wings));
		hud_ink(acc, hud_symbol_halo_color, hud_fill(strokes - hud_symbol_halo_deg, aa));
		hud_ink(acc, vec4(c.rgb, c.a * 0.16), hud_fill(tri, aa));
		hud_ink(acc, vec4(c.rgb, c.a * 0.5), hud_fill(max(inner, -core), aa));
		hud_ink(acc, c, hud_fill(strokes, aa));
	} else {
		// Only the three corners of the rim, and a hollow core.
		float corner = min(length(vec2(abs(up.x) - 1.0, up.y + 0.57735)), length(up - vec2(0.0, 1.1547)));
		float core = abs(hud_triangle(up, 0.46) + 0.05) - 0.05;
		strokes = min(max(rim, corner - 0.72), core);
		hud_ink(acc, hud_symbol_halo_color, hud_fill(strokes - hud_symbol_halo_deg, aa));
		hud_ink(acc, c, hud_fill(strokes, aa));
	}
}


vec3 hud_fpm(vec3 color, vec3 local_dir, float brightness, float aa) {
	float grow = hud_fpm_anim.x;
	if (grow <= 0.0) {
		return color;
	}
	vec3 d = hud_fpm_frame * local_dir;
	bool pro = d.x < 0.0;
	// Patch degrees: right is -Z for the prograde marker, +Z for the retrograde one.
	float depth = abs(d.x);
	vec2 p = degrees(vec2(atan(pro ? -d.z : d.z, depth), atan(d.y, depth)));
	float unit = hud_fpm_marker * grow;
	bool at_marker = depth > 0.5 && max(abs(p.x), abs(p.y)) < unit * 2.8;
	vec4 cov = hud_sample(hud_fpm_texture, hud_fpm_frame, local_dir);
	if (cov.r + cov.g + cov.b < 0.002 && !at_marker) {
		return color;
	}
	vec4 c = pro ? hud_fpm_color : hud_fpm_retro_color;

	float stripe_a = 0.0;
	vec3 stripe_rgb = mix(c.rgb, hud_fpm_accent_color.rgb, hud_fpm_anim.z * 0.7);
	if (cov.r > 0.002) {
		float u = hud_fpm_stripe_u(p);
		float shown = clamp((grow * 1.15 - u) / 0.15, 0.0, 1.0);
		float head = pro ? hud_fpm_anim.y : 1.0 - hud_fpm_anim.y;
		float width = hud_fpm_stripes.w;
		float glow = hud_fpm_glow(u, head, width);
		glow = max(glow, hud_fpm_glow(u, fract(head + 0.5), width) * hud_fpm_anim.z);
		if (pro && hud_fpm_anim.w > 0.0) {
			glow = max(glow, exp(-pow((u - (1.0 - hud_fpm_anim.w)) / 0.08, 2.0)) * hud_fpm_anim.w);
		}
		stripe_a = c.a * mix(hud_fpm_stripes.z, 1.0, glow) * shown * hud_fpm_pulse * min(cov.r, 1.0);
	}
	float mark_a = c.a * grow * min(cov.b, 1.0);

	vec4 acc = vec4(0.0);
	hud_ink(acc, hud_fpm_halo_color, cov.g);
	vec3 stroke = (stripe_rgb * stripe_a + c.rgb * mark_a) / max(stripe_a + mark_a, 1e-5);
	hud_ink(acc, vec4(stroke, 1.0), stripe_a + mark_a);
	if (at_marker) {
		hud_fpm_marker_ink(acc, p / unit, pro, vec4(c.rgb, c.a * min(grow * 2.0, 1.0)), aa / unit);
	}
	return hud_compose(color, acc, brightness);
}


vec3 hud_control(vec3 color, vec3 local_dir, float brightness, float aa) {
	if (hud_control_color.a <= 0.0) {
		return color;
	}
	vec3 d = hud_control_frame * local_dir;
	if (d.z > -0.985) {
		return color;
	}
	vec2 q = degrees(vec2(atan(abs(d.x), -d.z), atan(d.y, -d.z))) / hud_control_scale;
	aa /= hud_control_scale;
	vec2 arm = normalize(vec2(1.0, 0.6));
	vec2 arm_down = vec2(arm.x, -arm.y);
	// V above the middle, ^ and an accent ^ below: wide bands with a bright border and a
	// faint fill.
	float above = hud_chevron(q, vec2(0.0, 1.7), arm, 1.2, 0.21);
	float below = hud_chevron(q, vec2(0.0, -1.7), arm_down, 1.2, 0.21);
	float accent = hud_chevron(q, vec2(0.0, -2.8), arm_down, 1.2, 0.21);
	float plain = min(above, below);
	float plain_border = abs(plain + 0.04) - 0.04;
	float accent_border = abs(accent + 0.04) - 0.04;

	vec4 acc = vec4(0.0);
	float halo = hud_symbol_halo_deg / hud_control_scale;
	hud_ink(acc, hud_symbol_halo_color, hud_fill(min(plain_border, accent_border) - halo, aa));
	hud_ink(acc, vec4(hud_control_color.rgb, hud_control_color.a * hud_control_fill), hud_fill(plain, aa));
	hud_ink(acc, vec4(hud_control_accent_color.rgb, hud_control_accent_color.a * hud_control_fill), hud_fill(accent, aa));
	hud_ink(acc, hud_control_color, hud_fill(plain_border, aa));
	hud_ink(acc, hud_control_accent_color, hud_fill(accent_border, aa));
	return hud_compose(color, acc, brightness);
}


vec3 hud_layers(vec3 color, vec3 local_dir, float brightness) {
	// Degrees across a pixel, for the edges of the symbols drawn here.
	float aa = degrees(length(fwidth(local_dir))) * 0.7;
	color = hud_over(color, hud_sample(hud_static_texture, mat3(1.0), local_dir), brightness);
	color = hud_over(color, hud_sample(hud_heading_texture, hud_heading_frame, local_dir), brightness);
	color = hud_ladder(color, local_dir, brightness);
	color = hud_over(color, hud_sample(hud_suit_texture, hud_suit_frame, local_dir), brightness);
	color = hud_control(color, local_dir, brightness, aa);
	color = hud_fpm(color, local_dir, brightness, aa);
	return color;
}
