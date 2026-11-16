// A round glow that always faces the camera: bolt heads, muzzle flashes, charges, impacts.
// As a ball (flash_ball = 1) it is a sphere of light instead: a solid white-hot disc with a
// coloured limb and halo, cooling to its colour as flash_heat goes 0 → 1 (explosions).
// As a charge (flash_charge = 1) it is energy gathering at a muzzle: a boiling, ragged
// knot with arcs crackling off it and a white core that grows with flash_core (0..1).
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
instance uniform float flash_ball = 0.0;
instance uniform float flash_charge = 0.0;
// Ball: 0 white-hot, 1 cooled to its colour.
instance uniform float flash_heat = 0.0;
// Never bigger on screen than this (rad), and faded out right at the camera: a hit on the
// viewer's own suit is a flash, not a white screen.
instance uniform float flash_max_angle = 0.22;
uniform float min_angle = 0.0016;
// Never smaller on screen than this (rad): a charge stays readable at any range, the way a
// camera blooms a bright point into a halo. Its body keeps its real size inside it.
instance uniform float flash_min_angle = 0.0;
// Camera glare on a charge: a halo and a cross of streaks, 0..1.
instance uniform float flash_glare = 0.0;

varying float v_near;
// Real size / drawn size (≤ 1): how much the floor above enlarged the sprite.
varying float v_shrink;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 centre = MODELVIEW_MATRIX[3].xyz;
	float dist = length(centre);
	float size = max(min(flash_size, flash_max_angle * dist), min_angle * dist);
	float natural = size;
	size = max(size, flash_min_angle * dist);
	v_shrink = natural / size;
	v_near = smoothstep(1.0, 14.0, dist);
	VERTEX = centre + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = 1.0 - smoothstep(0.75, 1.0, r);
	vec3 col;
	if (flash_ball > 0.5) {
		// Slightly lumpy rim, so it reads as a burning ball rather than a disc.
		float a = atan(p.y, p.x);
		float rim = 0.84 + (noise(vec2(a * 2.5 + flash_seed * 40.0, flash_heat * 3.0)) - 0.5) * 0.05;
		float disc = 1.0 - smoothstep(rim - 0.04, rim, r);
		float limb = smoothstep(rim * 0.35, rim, r);
		vec3 hot = mix(vec3(1.0), flash_color, clamp(limb * 0.8 + flash_heat * 0.9, 0.0, 1.0));
		// Bright limb and a soft halo outside the ball.
		float halo = exp(-pow(max(r - rim, 0.0) * 9.0, 2.0)) * (1.0 - disc);
		col = hot * disc * (1.0 + limb * 0.6) + flash_color * halo * 0.9;
		edge = 1.0 - smoothstep(0.9, 1.0, r);
	} else if (flash_charge > 0.5) {
		// The knot keeps its real size (at least a quarter of the sprite); halo and glare
		// fill the rest.
		vec2 q = p;
		float shrink = max(v_shrink, 0.25);
		p = q / shrink;
		r = length(p);
		float a = atan(p.y, p.x);
		float t = TIME * 26.0 + flash_seed * 40.0;
		// A ragged outline that boils, so it never settles into a disc.
		float rim = 0.3 + 0.2 * noise(vec2(a * 1.6 + flash_seed * 9.0, t))
				+ 0.14 * noise(vec2(a * 5.0 - flash_seed * 3.0, t * 1.9));
		float body = exp(-pow(r / rim, 2.0) * 2.2);
		float hot = exp(-pow(r / (rim * 0.45), 2.0) * 2.0);
		// Arcs: thin crooked filaments flicking off it, re-rolled several times a second.
		float arcs = 0.0;
		float roll = floor(t * 0.45);
		for (int i = 0; i < 5; i++) {
			float fi = float(i);
			float ang = hash(vec2(fi * 3.1, roll + flash_seed * 7.0)) * 6.2832;
			float bend = (noise(vec2(r * 7.0 + fi * 5.0, t * 0.8)) - 0.5) * 1.6;
			float d = a - ang - bend * r;
			d = abs(mod(d + 3.14159, 6.28318) - 3.14159);
			float reach = 0.45 + 0.5 * hash(vec2(fi + 11.0, roll));
			arcs += exp(-d * d * r * r * 1400.0) * smoothstep(0.08, 0.2, r)
					* (1.0 - smoothstep(reach * 0.55, reach, r));
		}
		float flick = 0.55 + 0.9 * noise(vec2(t * 1.4, flash_seed * 5.0));
		float core = exp(-r * r * 70.0) * (0.6 + 2.4 * flash_core) * (0.7 + 0.6 * noise(vec2(t * 2.3, 1.0)));
		col = flash_color * (body * 1.3 + hot * 0.8) * flick
				+ mix(flash_color, vec3(1.0), 0.65) * arcs * (0.6 + flash_core)
				+ vec3(1.0) * core;
		// Glare in the sprite's own frame: a soft halo and a cross that stretches as the
		// charge nears the shot.
		// Only once the floor has enlarged it (seen from afar): a charge right by the viewer
		// (its own barrel) stays a clean knot.
		float rq = length(q);
		float reach = 1.5 + 4.0 * flash_core;
		float streak = exp(-abs(q.y) * 22.0) * exp(-abs(q.x) * (6.0 / reach))
				+ exp(-abs(q.x) * 22.0) * exp(-abs(q.y) * (6.0 / reach));
		float halo = exp(-rq * rq * 4.0) * 0.6;
		float far = 1.0 - smoothstep(0.35, 0.9, v_shrink);
		col += mix(flash_color, vec3(1.0), 0.45) * (streak * 1.6 + halo) * flash_glare * far * flick;
		edge = 1.0 - smoothstep(0.85, 1.0, rq);
	} else {
		float glow = exp(-r * r * 5.0);
		float core = exp(-r * r * 45.0) * flash_core * 3.0;
		float a = atan(p.y, p.x);
		float rays = pow(abs(sin(a * 4.0 + flash_seed * 6.0)) * abs(sin(a * 7.0 - flash_seed * 11.0)), 6.0)
				* exp(-r * 3.0) * flash_rays * 4.0;
		col = flash_color * (glow + rays) + vec3(1.0) * (core + rays * 0.5);
	}
	ALBEDO = col * flash_intensity * edge * v_near;
}
