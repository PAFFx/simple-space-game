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

// Camera coverage (DamageModel): the live cameras' fields, world direction and cos of the
// half field (+2 marks the head's main camera). Every camera gives the full picture;
// directions none of them sees have no signal.
uniform int coverage_on = 0;
uniform int camera_count = 0;
uniform vec4 camera_cones[32];

// Beams through the screen (PanoramicScreen.add_beam_hole), the lines the chest's holes were
// drilled along, in the screen mesh's space: origin and radius, axis and when (HoleSet clock).
// The opening is that cylinder, a bit wider (glass shatters), its edge hot and cooling.
uniform int beam_count = 0;
uniform vec4 beam_a[8];
uniform vec4 beam_b[8];
uniform float hole_now = 0.0;
// Where they cross the screen: direction and the opening's angular radius; the composite
// screens (bits) each crossing's opening touches, whose glass cracks from it; the sub-screens
// (bit composite·4 + sub) any opening touches, which die.
uniform int crossing_count = 0;
uniform vec4 crossings[16];
uniform int crossing_glass[16];
uniform int dead_subs = 0;
uniform int flicker_subs = 0;
const float OPENING = 1.15;
const float SCREEN_PEAK = 2000.0;

varying vec3 v_local;
// The twin outside cameras see (PanoramicScreen): the picture is for the pilot's eye, so from
// outside the screen is dark glass unless the door is open.
instance uniform bool outside_view = false;
// The screen is built from composite screens, each of a few sub-screens behind one glass:
// the door (centre front, its lower half the hatch), two big ones either side of it, two
// sides, the rear, the top and the bottom. Azimuth edges (deg from the front): door half
// width, front screens' outer edge, sides' outer edge; the door's split elevation. Then the
// top and bottom screens' edges (elevation, deg). A beam kills the sub-screen it goes through
// and cracks that composite's glass. Bezels: frame between composites, a seam between subs.
uniform vec4 panel_layout = vec4(19.0, 75.0, 145.0, -13.5);
uniform vec2 panel_caps = vec2(45.0, -61.0);
uniform float bezel_deg = 0.55;
uniform float seam_deg = 0.16;
uniform vec3 bezel_color : source_color = vec3(0.018, 0.02, 0.024);

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


// The zoom window: a magnified view (sensor head's zoom camera) in a rectangle on the
// screen, columns of zoom_frame = its right, up and centre in the display's local frame,
// half size as tangents. While zoom_reveal goes 0 → 1 it resolves in from blocks.
uniform sampler2D zoom_viewport : source_color, hint_default_black, filter_linear;
uniform float zoom_reveal = 0.0;
uniform mat3 zoom_frame = mat3(1.0);
uniform vec2 zoom_half_tan = vec2(0.12, 0.09);
uniform float zoom_block_px = 32.0;
// The HUD inside the window is faded to this, so the magnified target reads (its frame
// sits on the edge, just outside the fade).
uniform float zoom_hud_alpha = 0.35;


// Its frame, drawn here rather than on the HUD canvas (recording it there cost ~1.3 ms a
// frame): a faint rim, bold corners, and over the top left a row of cells, one per zoom
// level, filled up to the one shown. The level number stays on the canvas.
uniform vec4 zoom_frame_color : source_color, color_conversion_disabled = vec4(0.88, 0.91, 0.93, 0.92);
uniform int zoom_level_count = 0;
uniform int zoom_level_shown = 0;
const vec2 ZOOM_CELL = vec2(1.25, 0.42);   // deg
const float ZOOM_CELL_GAP = 0.24;
const vec2 ZOOM_CELLS_AT = vec2(0.1, 0.48); // left edge from the frame's, bottom above its top


float sd_box(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}


vec3 composite_zoom_frame(vec3 color, vec3 local_dir, float brightness, float aa) {
	if (zoom_reveal <= 0.0) {
		return color;
	}
	float depth = dot(local_dir, zoom_frame[2]);
	if (depth <= 0.0) {
		return color;
	}
	// Degrees from the window's middle (gnomonic; a 14° window bends by well under a pixel).
	vec2 p = degrees(vec2(dot(local_dir, zoom_frame[0]), dot(local_dir, zoom_frame[1])) / depth);
	vec2 half_deg = degrees(zoom_half_tan);
	float reach = max(half_deg.x, half_deg.y) + 2.0;
	if (abs(p.x) > reach || abs(p.y) > reach) {
		return color;
	}
	float rim = abs(sd_box(p, half_deg)) - max(0.045, aa * 0.5);
	float leg = min(half_deg.x, half_deg.y) * 0.25;
	float near_corner = step(half_deg.x - leg, abs(p.x)) * step(half_deg.y - leg, abs(p.y));
	float corner = near_corner > 0.5 ? abs(sd_box(p, half_deg)) - max(0.1, aa) : 1e9;
	float cells_outline = 1e9;
	float cells_fill = 1e9;
	vec2 origin = vec2(-half_deg.x + ZOOM_CELLS_AT.x, half_deg.y + ZOOM_CELLS_AT.y);
	for (int i = 0; i < zoom_level_count; i++) {
		vec2 centre = origin + vec2(float(i) * (ZOOM_CELL.x + ZOOM_CELL_GAP), 0.0) + ZOOM_CELL * 0.5;
		float box = sd_box(p - centre, ZOOM_CELL * 0.5);
		cells_outline = min(cells_outline, abs(box) - max(0.06, aa * 0.6));
		if (i < zoom_level_shown) {
			cells_fill = min(cells_fill, box);
		}
	}
	vec4 c = vec4(zoom_frame_color.rgb, zoom_frame_color.a * zoom_reveal);
	float strokes = min(min(corner, cells_outline), cells_fill);
	vec4 acc = vec4(0.0);
	hud_ink(acc, vec4(hud_symbol_halo_color.rgb, hud_symbol_halo_color.a * zoom_reveal), hud_fill(strokes - hud_symbol_halo_deg, aa));
	hud_ink(acc, vec4(c.rgb, c.a * 0.35), hud_fill(rim, aa));
	hud_ink(acc, c, hud_fill(strokes, aa));
	return hud_compose(color, acc, brightness);
}


// 1 inside the zoom window (a little short of its edge), else 0.
float zoom_inside(vec3 local_dir) {
	float depth = dot(local_dir, zoom_frame[2]);
	if (zoom_reveal <= 0.0 || depth <= 0.0) {
		return 0.0;
	}
	vec2 q = vec2(dot(local_dir, zoom_frame[0]), dot(local_dir, zoom_frame[1])) / depth / zoom_half_tan;
	return step(max(abs(q.x), abs(q.y)), 0.96);
}

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


vec3 composite_zoom(vec3 color, vec3 local_dir) {
	if (zoom_reveal <= 0.0) {
		return color;
	}
	float depth = dot(local_dir, zoom_frame[2]);
	if (depth <= 0.0) {
		return color;
	}
	vec2 q = vec2(dot(local_dir, zoom_frame[0]), dot(local_dir, zoom_frame[1])) / depth / zoom_half_tan;
	if (abs(q.x) >= 1.0 || abs(q.y) >= 1.0) {
		return color;
	}
	vec2 uv = vec2(q.x * 0.5 + 0.5, 0.5 - q.y * 0.5);
	vec3 seen = texture(zoom_viewport, uv).rgb * screen_brightness;
	if (zoom_reveal >= 1.0) {
		return seen;
	}
	// Resolving: blocks halving in size, popping in at random, blue until they settle.
	float e = zoom_reveal;
	vec2 size = vec2(textureSize(zoom_viewport, 0));
	float block = exp2(floor(mix(log2(zoom_block_px), 0.0, e * e * (3.0 - 2.0 * e)) + 0.5));
	vec2 px = uv * size;
	vec2 cell = floor(px / block);
	vec3 rgb = texture(zoom_viewport, (cell + 0.5) * block / size).rgb * screen_brightness;
	float h = fract(sin(dot(cell + vec2(block * 13.1, block * 7.7), vec2(12.9898, 78.233))) * 43758.5453);
	float shown = step(h, e * 1.5);
	vec2 f = fract(px / block);
	float edge = block > 2.0 ? step(min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)) * block, 1.0) : 0.0;
	float lum = dot(rgb, vec3(0.3, 0.5, 0.2));
	vec3 blue = overlay_tint * (0.35 + lum * 1.2) * (1.0 + edge * 0.8);
	float settle = smoothstep(0.55, 1.0, e);
	return mix(color, mix(blue, rgb, settle), shown);
}


// 0: no camera sees `dir`, 1: a camera does (soft edge between).
float coverage(vec3 dir) {
	float seen = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= camera_count) {
			break;
		}
		vec4 c = camera_cones[i];
		float cos_half = c.w > 1.5 ? c.w - 2.0 : c.w;
		seen = max(seen, smoothstep(cos_half - 0.02, cos_half + 0.02, dot(dir, c.xyz)));
	}
	return seen;
}

float cov_hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.7);
}

// Which composite screen and sub-screen a direction falls on (az, el in deg; az 0 front,
// + right): vec4(composite, sub, distance to the composite's edge, distance to a sub seam),
// distances in deg on the sphere. The screens aren't a grid: the door narrows above the hatch
// (a trapezoid), the front screens' outer edges lean out at the top, the sides lean back, the
// top screen's edge sits higher in front, the bottom rises toward the sides, and sub-screens
// are split on slants.
vec4 screen_panel(float az, float el) {
	float aa = abs(az);
	float ce = max(cos(radians(el)), 0.05);
	float split = panel_layout.w;
	float top = panel_caps.x + 7.0 * cos(radians(az));
	float bottom = panel_caps.y + 9.0 * smoothstep(panel_layout.x, panel_layout.y, aa);
	float mid = (top + bottom) * 0.5;
	if (el >= top || el <= bottom) {
		bool up = el >= top;
		float a = mod(az + (up ? 25.0 : 65.0), 360.0);
		float r = mod(a, 90.0);
		return vec4(up ? 0.0 : 1.0, floor(a / 90.0), up ? el - top : bottom - el, min(r, 90.0 - r) * ce);
	}
	float d_el = min(top - el, el - bottom);
	// The door: the hatch's rectangle below the split, narrowing to the top above it.
	float door = el < split ? panel_layout.x : mix(panel_layout.x, panel_layout.x * 0.65, clamp((el - split) / max(top - split, 1.0), 0.0, 1.0));
	float front = panel_layout.y + (el - mid) * 0.35;
	float side = panel_layout.z - (el - mid) * 0.3;
	if (aa <= door) {
		return vec4(2.0, el < split ? 0.0 : 1.0, min((door - aa) * ce, d_el), abs(el - split));
	}
	if (aa <= front) {
		float m = (door + front) * 0.5 + (el - mid) * 0.25;
		float me = mid + (aa - m) * 0.2;
		float sub = (aa < m ? 0.0 : 1.0) + (el < me ? 0.0 : 2.0);
		return vec4(az < 0.0 ? 3.0 : 4.0, sub, min(min(aa - door, front - aa) * ce, d_el), min(abs(aa - m) * ce, abs(el - me)));
	}
	if (aa <= side) {
		float m = (front + side) * 0.5 - (el - mid) * 0.2;
		float me = mid - (aa - m) * 0.18;
		float sub = (aa < m ? 0.0 : 1.0) + (el < me ? 0.0 : 2.0);
		return vec4(az < 0.0 ? 5.0 : 6.0, sub, min(min(aa - front, side - aa) * ce, d_el), min(abs(aa - m) * ce, abs(el - me)));
	}
	float me = mid + (180.0 - aa) * 0.15;
	float sub = (az < 0.0 ? 0.0 : 1.0) + (el < me ? 0.0 : 2.0);
	return vec4(7.0, sub, min((aa - side) * ce, d_el), min((180.0 - aa) * ce, abs(el - me)));
}

#include "res://Entities/Vehicles/Components/Damage/Shader/hole_heat.gdshaderinc"

float hole_like_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cov_hash(i), cov_hash(i + vec2(1.0, 0.0)), f.x),
			mix(cov_hash(i + vec2(0.0, 1.0)), cov_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
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

	// --- Step 2b: Composite screens, and beam holes in them ---
	// The sub-screen a hole is in goes dark; the glass of that composite screen cracks from
	// the hole (thin dark breaks with a glint where they catch the light), and its other
	// sub-screens keep their picture under the cracks, with a few dead blocks.
	float az_deg = degrees(atan(sin(azimuth), cos(azimuth)));
	float el_deg = degrees(elevation);
	vec4 my_panel = screen_panel(az_deg, el_deg);
	float panel_dead = 0.0;
	float rim_t = 0.0;
	float rim_w = 0.0;
	float char_w = 0.0;
	float crack_dark = 0.0;
	float crack_glint = 0.0;
	float block_dead = 0.0;
	float glass_broken = 0.0;
	int my_bit = int(my_panel.x) * 4 + int(my_panel.y);
	panel_dead = float((dead_subs >> my_bit) & 1);
	float flicker = float((flicker_subs >> my_bit) & 1);
	if (beam_count > 0) {
		for (int i = 0; i < 8; i++) {
			if (i >= beam_count) {
				break;
			}
			vec3 a = beam_b[i].xyz;
			float r = beam_a[i].w;
			vec3 q = v_local - beam_a[i].xyz;
			vec3 radial = q - a * dot(q, a);
			float d = length(radial);
			if (d > r * 2.5) {
				continue;
			}
			vec3 e1 = normalize(cross(a, abs(a.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			float ang = atan(dot(radial, cross(a, e1)), dot(radial, e1));
			float seed = float(i) * 1.73 + beam_b[i].w * 0.37;
			// Shattered glass: a jagged outline (sharp teeth over a slow wander).
			float teeth = abs(fract(ang * 4.5 + hole_like_noise(vec2(ang * 2.0, seed)) * 1.7) - 0.5);
			float open_r = r * OPENING * (1.0 + 0.07 * sin(3.0 * ang + seed) + 0.06 * (hole_like_noise(vec2(ang * 6.0, seed)) - 0.5)
					- 0.06 * teeth);
			if (d < open_r) {
				discard;
			}
			// The torn edge: a thin hot lip where the beam passed, cooling with the chest's hole,
			// and a charred band.
			float out_r = (d - open_r) / r;
			float w = 1.0 - smoothstep(0.0, 0.035, out_r);
			float t = hole_cool(SCREEN_PEAK, hole_now - beam_b[i].w);
			if (w * t > rim_w * rim_t) {
				rim_t = t;
				rim_w = w;
			}
			char_w = max(char_w, (1.0 - smoothstep(0.02, 0.25, out_r)) * (0.75 + 0.25 * hole_like_noise(vec2(ang * 8.0, out_r * 30.0))));
		}
		float cel2 = cos(elevation);
		vec3 dir_s = vec3(sin(azimuth) * cel2, sin(elevation), -cos(azimuth) * cel2);
		for (int i = 0; i < 16; i++) {
			if (i >= crossing_count) {
				break;
			}
			if (((crossing_glass[i] >> int(my_panel.x)) & 1) == 0) {
				continue;
			}
			glass_broken = 1.0;
			// Spiderweb from the opening's edge: radial cracks (wandering) and broken rings,
			// thinning out; distances in units of 16 deg, the opening's edge at 0.55.
			vec3 hd = crossings[i].xyz;
			float ang = (acos(clamp(dot(dir_s, hd), -1.0, 1.0)) - crossings[i].w) / radians(16.0) + 0.55;
			vec3 e1 = normalize(cross(hd, abs(hd.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			float around = atan(dot(dir_s, cross(hd, e1)), dot(dir_s, e1));
			float seed = float(i) * 3.7;
			float reach = 1.0 - smoothstep(2.0, 7.0, ang);
			float wob = 0.18 * (cov_hash(vec2(floor(ang * 3.0), seed)) - 0.5) + 0.08 * sin(ang * 4.0 + seed);
			float rays = abs(fract(around / TAU * 13.0 + wob + seed) - 0.5);
			float ray_d = 0.5 - rays;
			float ray_line = 1.0 - smoothstep(0.0, fwidth(ray_d) * 1.3, ray_d);
			ray_line *= step(0.6, ang) * step(0.35, cov_hash(vec2(floor(around / TAU * 13.0 + wob + seed), seed)) + 0.4);
			float ring_n = ang * 1.7 + 0.25 * (cov_hash(vec2(floor(around * 5.0), seed)) - 0.5);
			float ring_d = abs(fract(ring_n) - 0.5);
			float ring_line = (1.0 - smoothstep(0.0, fwidth(ring_n) * 1.3, 0.5 - ring_d))
					* step(0.5, cov_hash(vec2(floor(around * 4.0), floor(ring_n) + seed)));
			float c = max(ray_line, ring_line * (1.0 - smoothstep(0.8, 3.5, ang))) * reach;
			crack_dark = max(crack_dark, c);
			crack_glint = max(crack_glint, c * smoothstep(0.55, 0.9, hole_like_noise(vec2(around * 3.0, ang * 1.5) + seed)));
			if (panel_dead < 0.5) {
				vec2 cell = floor(vec2(azimuth, elevation) * 50.0);
				block_dead = max(block_dead, step(0.92, cov_hash(cell + seed)) * (1.0 - smoothstep(2.0, 5.0, ang)));
			}
		}
	}

	// --- Step 3: Check the segment mask ---
	// fract() wraps any arc_offset so the mask always indexes [0, 1] correctly.
	float active = texture(segment_mask, vec2(fract(UV2.x), 0.5)).r;

	vec3 color;
	if (outside_view && aperture_amount <= 0.0) {
		color = vec3(0.012, 0.013, 0.016) + vec3(0.02) * hole_like_noise(vec2(azimuth, elevation) * 6.0);
	} else if (active < 0.5) {
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
				float cov = coverage_on == 1 ? coverage(world_dir) : 1.0;
				color = texture(sensor_viewport, sample_uv).rgb * screen_brightness;
				color = composite_overlay(color, sample_uv);
				// No camera sees here: black.
				color *= smoothstep(0.6, 1.0, cov);
			}
		}

		color = composite_zoom(color, local_dir);
		vec3 under_hud = color;

		// --- Step 7: Composite the HUD on top of the sensor image ---
		// Fixed layers first (drawn once, turned into place), then the per-frame canvas.
		color = hud_layers(color, local_dir, hud_brightness);
		vec2 hud_uv = vec2(fract(UV2.x + 0.5), 1.0 - UV2.y);
		vec4 hud = texture(hud_texture, hud_uv);
		color = mix(color, hud.rgb * hud_brightness, hud.a);
		color = hud_locked_contact(color, local_dir, hud_brightness);
		color = mix(color, mix(under_hud, color, zoom_hud_alpha), zoom_inside(local_dir) * zoom_reveal);
		color = composite_zoom_frame(color, local_dir, hud_brightness, degrees(length(fwidth(local_dir))) * 0.7);
	}

	// The seams are invisible while the screen is whole; a broken composite shows its frame
	// and its sub-screens' seams (the glass gone dull around them, the edges catching light).
	if (glass_broken > 0.5) {
		float fw = max(fwidth(el_deg), 0.02);
		float frame = 1.0 - smoothstep(bezel_deg - fw, bezel_deg + fw, my_panel.z);
		float seam = 1.0 - smoothstep(seam_deg - fw, seam_deg + fw, my_panel.w);
		float edge_light = (1.0 - smoothstep(0.0, fw * 2.0, abs(my_panel.z - bezel_deg))) * 0.5;
		color = mix(color, bezel_color, max(frame, seam * 0.85));
		color += vec3(0.05, 0.055, 0.06) * edge_light;
	}
	if (flicker > 0.5) {
		// A sub-screen losing its signal: stutters dark and bright, torn lines.
		float t = floor(TIME * 24.0);
		float on = step(0.45, cov_hash(vec2(t, float(my_bit))));
		float tear = step(0.985, cov_hash(vec2(floor(elevation * 400.0), t + float(my_bit))));
		color = color * (on * 1.4 + 0.04) + vec3(0.12, 0.14, 0.16) * tear * on;
	}
	if (beam_count > 0 || dead_subs != 0) {
		// A dead panel is dark glass: a faint sheen of the cockpit's light across it.
		float sheen = 0.02 + 0.025 * hole_like_noise(vec2(azimuth, elevation) * 6.0);
		color = mix(color, vec3(0.004), block_dead);
		color = mix(color, vec3(sheen, sheen * 1.05, sheen * 1.15), panel_dead);
		color = mix(color, color * 0.1, crack_dark * 0.9 * (1.0 - panel_dead));
		color += vec3(0.6, 0.65, 0.72) * crack_glint * (0.5 + 1.2 * panel_dead);
		color += vec3(0.05, 0.055, 0.06) * crack_dark * panel_dead;
		color = mix(color, vec3(0.006, 0.005, 0.004), char_w * 0.9);
		color = mix(color, hole_blackbody(rim_t) * (0.3 + hole_glow(rim_t)), rim_w * smoothstep(750.0, 1100.0, rim_t));
	}
	ALBEDO   = color;
	EMISSION = color;
}
