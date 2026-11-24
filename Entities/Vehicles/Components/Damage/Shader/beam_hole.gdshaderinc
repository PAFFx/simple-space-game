// Beam holes drawn from records (Docs/Damage/beam_effects.md). A hole is a cylinder in the
// part's space (a bone's, or the mesh's own for rigid things): origin, axis (the beam's
// line), radius, where the line enters / leaves the part (s_in, s_out) and how far it has
// been drilled (s_drill). Inside the mouth the view ray is cast into the cylinder: the bore's
// wall or the crater floor is drawn at its true depth, and through holes are open.
// Around the mouth: a ragged molten lip, a heat-affected zone glowing by blackbody
// temperature, scorch. Everything cools with the hole's age.
//
// Use: in vertex(), `v_part_pos = hole_part_pos(VERTEX); v_part_cam = hole_part_cam(MODELVIEW_MATRIX);`
// in fragment(), `HoleHit h = hole_fragment(v_part_pos, v_part_cam, FRONT_FACING);` and apply it
// (see damage_surface.gdshader).

const int HOLE_MAX = 16;
uniform int hole_count = 0;
uniform vec4 hole_a[HOLE_MAX];   // origin.xyz (part space, m), radius
uniform vec4 hole_b[HOLE_MAX];   // axis.xyz, s_in
uniform vec4 hole_c[HOLE_MAX];   // s_drill, s_out, time it formed, peak temperature (K)
uniform mat4 part_to_model = mat4(1.0);
uniform mat4 model_to_part = mat4(1.0);
uniform float hole_now = 0.0;
// Whole-mesh heat (a part thrown off a breaching reactor): K above ambient, and when.
uniform vec2 body_heat = vec2(0.0, -1000.0);

varying vec3 v_part_pos;
varying vec3 v_part_cam;

vec3 hole_part_pos(vec3 vertex) {
	return (model_to_part * vec4(vertex, 1.0)).xyz;
}

vec3 hole_part_cam(mat4 modelview) {
	return (model_to_part * (inverse(modelview) * vec4(0.0, 0.0, 0.0, 1.0))).xyz;
}

// Colour of hot metal by temperature (K), unit brightness.
vec3 hole_blackbody(float t) {
	float x = clamp((t - 700.0) / 2300.0, 0.0, 1.0);
	vec3 c = mix(vec3(0.45, 0.012, 0.0), vec3(1.0, 0.12, 0.01), smoothstep(0.0, 0.2, x));
	c = mix(c, vec3(1.0, 0.42, 0.06), smoothstep(0.15, 0.45, x));
	c = mix(c, vec3(1.0, 0.78, 0.4), smoothstep(0.4, 0.75, x));
	return mix(c, vec3(1.0, 0.96, 0.9), smoothstep(0.7, 1.0, x));
}

// How bright hot metal glows (HDR energy): next to nothing below ~750 K, ∝ T⁴ beyond.
float hole_glow(float t) {
	float k = max(t - 720.0, 0.0) / 1300.0;
	return min(k * k * k * 1.6 + k * 0.45, 5.0);
}

// Temperature a spot that peaked at `peak` K has after `age` s in vacuum: radiation
// (T⁻³ grows linearly) and conduction into the rest of the part.
float hole_cool(float peak, float age) {
	return 290.0 + (peak - 290.0) * pow(1.0 + max(age, 0.0) / 4.0, -0.3333) * exp(-max(age, 0.0) / 28.0);
}

float hole_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hole_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hole_hash(i), hole_hash(i + vec2(1.0, 0.0)), f.x),
			mix(hole_hash(i + vec2(0.0, 1.0)), hole_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

struct HoleHit {
	bool discard_it;    // open: see through
	bool inside;        // the fragment shows a bore wall or crater floor
	float depth;        // ...this far along the view ray past the fragment (m)
	vec3 normal_part;   // its normal, part space
	float temperature;  // K of whatever the fragment shows (inside or on the surface)
	float scorch;       // 0..1 darkening of the surface around holes
	float lip;          // 0..1 molten lip
	float tint;         // 0..1 heat tint (cooled metal)
	float near_heat;    // K of the hottest hole near a back face (interior light)
	vec2 wall;          // inside: angle around the bore and depth (texture coordinates)
	vec2 zone;          // around a mouth: angle and distance from the rim (in radii)
};

HoleHit hole_fragment(vec3 p, vec3 cam, bool front_facing) {
	HoleHit h;
	h.discard_it = false;
	h.inside = false;
	h.depth = 0.0;
	h.normal_part = vec3(0.0, 1.0, 0.0);
	h.temperature = 290.0;
	h.scorch = 0.0;
	h.lip = 0.0;
	h.tint = 0.0;
	h.near_heat = 290.0;
	h.wall = vec2(0.0);
	h.zone = vec2(0.0, 99.0);
	vec3 rd = normalize(p - cam);
	if (body_heat.x > 0.0) {
		float t = hole_cool(290.0 + body_heat.x, hole_now - body_heat.y);
		h.temperature = max(h.temperature, t);
		h.near_heat = max(h.near_heat, t);
		h.scorch = max(h.scorch, 0.6);
	}
	for (int i = 0; i < HOLE_MAX; i++) {
		if (i >= hole_count) {
			break;
		}
		vec3 o = hole_a[i].xyz;
		float r = hole_a[i].w;
		vec3 a = hole_b[i].xyz;
		float s_in = hole_b[i].w;
		float s_dr = hole_c[i].x;
		float s_out = hole_c[i].y;
		float age = hole_now - hole_c[i].z;
		float peak = hole_c[i].w;
		vec3 q = p - o;
		float s = dot(q, a);
		vec3 radial = q - a * s;
		float d = length(radial);
		if (d > r * 7.0 || s < s_in - r * 3.0 || s > s_out + r * 3.0) {
			continue;
		}
		// Ragged outline: the radius wanders around the axis.
		vec3 e1 = normalize(cross(a, abs(a.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 e2 = cross(a, e1);
		float ang = atan(dot(radial, e2), dot(radial, e1));
		float seed = float(i) * 1.73 + hole_c[i].z * 0.37;
		float wob = 1.0 + 0.11 * sin(5.0 * ang + seed) + 0.06 * sin(11.0 * ang + seed * 2.1)
				+ 0.05 * (hole_noise(vec2(ang * 4.0 + seed, s * 2.0)) - 0.5);
		bool through = s_dr >= s_out - 1e-3;
		bool along = s >= s_in - r * 2.0 && s <= s_dr + r * 0.25;
		float t_now = hole_cool(peak, age);
		// Exit side flares (blow-out).
		float flare = through ? mix(1.0, 1.3, clamp((s - s_in) / max(s_out - s_in, 1e-3), 0.0, 1.0)) : 1.0;
		float rw = r * wob * flare;
		if (along && d < rw) {
			if (!front_facing) {
				// The shell's inside where the channel crosses it: open.
				h.discard_it = true;
				return h;
			}
			if (d >= r * flare) {
				// Between the true bore and the ragged outline: melted lip.
				h.lip = 1.0;
				h.temperature = max(h.temperature, t_now);
				h.zone = vec2(ang + seed, 0.0);
				continue;
			}
			// Cast the view ray into the bore (an infinite cylinder of radius r·flare).
			float rr = r * flare;
			vec3 u = radial;
			vec3 w = rd - a * dot(rd, a);
			float A = dot(w, w);
			float B = dot(u, w);
			float C = dot(u, u) - rr * rr;
			float t1 = A > 1e-8 ? (-B + sqrt(max(B * B - A * C, 0.0))) / A : 1e6;
			float s_hit = s + dot(rd, a) * t1;
			float ra = dot(rd, a);
			if (through) {
				if (s_hit > s_out || s_hit < s_in) {
					h.discard_it = true;
					return h;
				}
				h.inside = true;
				h.depth = t1;
				vec3 hp = q + rd * t1;
				vec3 hr = hp - a * dot(hp, a);
				h.normal_part = -normalize(hr);
				h.wall = vec2(atan(dot(hr, e2), dot(hr, e1)) + seed, s_hit / r);
				float along_f = clamp((s_hit - s_in) / max(s_out - s_in, 1e-3), 0.0, 1.0);
				h.temperature = hole_cool(peak * (1.0 - 0.12 * along_f), age);
				return h;
			}
			// A crater: the floor at s_drill, rounded off toward the wall.
			float t_floor = ra > 1e-4 ? (s_dr - s) / ra : 1e6;
			h.inside = true;
			if (t_floor < t1) {
				h.depth = max(t_floor, 0.0);
				vec3 fp = q + rd * h.depth;
				float fr = length(fp - a * dot(fp, a)) / rr;
				h.normal_part = normalize(-a + (fp - a * dot(fp, a)) / rr * fr * 0.8);
				vec3 fr3 = fp - a * dot(fp, a);
				h.wall = vec2(atan(dot(fr3, e2), dot(fr3, e1)) + seed, fr * 4.0 + 20.0);
				// The face the beam is still on is white-hot.
				h.temperature = hole_cool(peak + 500.0 * exp(-age * 6.0), age) * mix(1.0, 0.85, fr * fr);
			} else {
				h.depth = t1;
				vec3 hp = q + rd * t1;
				vec3 hr = hp - a * dot(hp, a);
				h.normal_part = -normalize(hr);
				h.wall = vec2(atan(dot(hr, e2), dot(hr, e1)) + seed, s_hit / r);
				h.temperature = hole_cool(peak * (0.9 + 0.1 * clamp((s_hit - s_in) / max(s_dr - s_in, 1e-3), 0.0, 1.0)), age);
			}
			return h;
		}
		// Around the mouth.
		float x = max(d - rw, 0.0) / r;
		float zone = along || s <= s_out + r ? 1.0 : 0.0;
		if (zone > 0.0) {
			float spread = exp(-x * 2.6);
			if (x < h.zone.y) {
				h.zone = vec2(ang + seed, x);
			}
			h.temperature = max(h.temperature, 290.0 + (t_now - 290.0) * spread);
			h.lip = max(h.lip, (1.0 - smoothstep(0.0, 0.22, x)) * 0.85);
			h.scorch = max(h.scorch, 1.0 - smoothstep(0.1, 1.6 + 0.5 * hole_noise(vec2(ang * 2.0, seed)), x));
			h.tint = max(h.tint, (1.0 - smoothstep(0.4, 1.1, x)) * smoothstep(0.05, 0.3, x));
		}
		if (!front_facing) {
			h.near_heat = max(h.near_heat, 290.0 + (t_now - 290.0) * exp(-x * 0.5));
		}
	}
	return h;
}
