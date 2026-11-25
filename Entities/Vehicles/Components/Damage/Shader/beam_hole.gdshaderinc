// Beam holes drawn from records (Docs/Damage/beam_effects.md). A hole is a cylinder in the
// part's space (a bone's, or the mesh's own for rigid things): origin, axis (the beam's
// line), radius, where the line enters / leaves the part (s_in, s_out) and how far it has
// been drilled (s_drill). Inside the mouth the view ray is cast into the cylinder: the bore's
// wall or the crater floor is drawn at its true depth, and through holes are open.
// Around the mouth: a ragged molten lip, a heat-affected zone glowing by blackbody
// temperature, scorch. Everything cools with the hole's age. A record with s_drill < 0 is a
// scorch mark only (a beam an I-field took): soot round the point, no crater, no melt.
//
// Use: in vertex(), `v_part_pos = hole_part_pos(VERTEX); v_part_cam = hole_part_cam(MODELVIEW_MATRIX);`
// in fragment(), `HoleHit h = hole_fragment(v_part_pos, v_part_cam, FRONT_FACING);` and apply it
// (see damage_surface.gdshader).

const int HOLE_MAX = 16;
uniform int hole_count = 0;
uniform vec4 hole_a[HOLE_MAX];   // origin.xyz (part space, m), radius
uniform vec4 hole_b[HOLE_MAX];   // axis.xyz, s_in
uniform vec4 hole_c[HOLE_MAX];   // s_drill, s_out, time it formed, peak temperature (K)
// Where the part's real skin is along the axis (the hull is convex, a plate's is not): metal
// where s <= x or s >= y; elsewhere the bore crosses the part's empty inside.
uniform vec4 hole_d[HOLE_MAX];
uniform mat4 part_to_model = mat4(1.0);
uniform mat4 model_to_part = mat4(1.0);
uniform float hole_now = 0.0;
// Whole-mesh heat (a part thrown off a breaching reactor): K above ambient, and when.
uniform vec2 body_heat = vec2(0.0, -1000.0);
// A cut through the part (it broke there): plane normal (part space) and offset; side +1
// keeps where n·p < offset, -1 where it is greater, 0 = no cut. The cut surface is bumpy
// (cut_bump m); back faces seen through the opening draw it at its place, hot and cooling.
uniform vec4 cut_plane = vec4(0.0, 1.0, 0.0, 0.0);
uniform float cut_side = 0.0;
uniform vec2 cut_heat = vec2(1800.0, -1000.0);
// The cut's outline in its plane (where it meets the part's skin): half-planes nx·u + ny·v <= c in
// the plane's coordinates; the face is only drawn inside it. 0 = no outline (anywhere).
uniform int cut_edge_count = 0;
// The cut face is drawn by a stencil cap (cut_cap.gdshaderinc), not traced here.
uniform bool cut_capped = false;
uniform vec4 cut_edges[24];
uniform float cut_bump = 0.22;

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
	vec3 tex_p;         // inside: where on the bore / floor / cut face, in the hole's own frame
	vec3 tex_n;         //   (e1, e2, axis; m) and its normal there: texture it triplanar
	vec2 zone;          // around a mouth: angle and distance from the rim (in radii)
	bool interior;      // a back face (the shell's inside) near a hole: seen through it
};

// Height of the cut surface above its plane at `p` (torn, uneven).
float cut_offset(vec3 p) {
	vec3 n = cut_plane.xyz;
	vec3 e1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec2 uv = vec2(dot(p, e1), dot(p, cross(n, e1)));
	return cut_bump * ((hole_noise(uv * 1.4) - 0.5) + 0.45 * (hole_noise(uv * 4.3 + 3.1) - 0.5));
}

// Signed distance-ish to the cut surface: > 0 on the side the cut removes.
float cut_field(vec3 p) {
	return (dot(p, cut_plane.xyz) - cut_plane.w - cut_offset(p)) * cut_side;
}

// Radius of hole j's bore at axial position s (a through hole's exit flares).
float hole_rr(int j, float s) {
	float r = hole_a[j].w;
	float s_in = hole_b[j].w;
	float s_out = hole_c[j].y;
	bool through = hole_c[j].x >= s_out - 1e-3;
	return r * (through ? mix(1.0, 1.3, clamp((s - s_in) / max(s_out - s_in, 1e-3), 0.0, 1.0)) : 1.0);
}

// Whether part-space point x is in metal hole j removed (its bore, from the mouth to its floor
// or, through, to the far end). Scorch-only records remove nothing.
bool hole_holds(int j, vec3 x) {
	float s_dr = hole_c[j].x;
	if (s_dr < 0.0) {
		return false;
	}
	vec3 a = hole_b[j].xyz;
	vec3 q = x - hole_a[j].xyz;
	float s = dot(q, a);
	float s_out = hole_c[j].y;
	bool through = s_dr >= s_out - 1e-3;
	if (s < hole_b[j].w - hole_a[j].w * 2.0 || s > (through ? s_out : s_dr)) {
		return false;
	}
	return length(q - a * s) < hole_rr(j, s);
}

// From x inside hole j's removed metal along rd (bore radius rr): how far to where the ray
// leaves it, and through what: 0 its wall, 1 its floor, 2 out of the part (a through hole's far
// end, or back out of the mouth).
vec2 hole_leave(int j, vec3 x, vec3 rd, float rr) {
	vec3 a = hole_b[j].xyz;
	vec3 q = x - hole_a[j].xyz;
	float s = dot(q, a);
	vec3 u = q - a * s;
	vec3 w = rd - a * dot(rd, a);
	float A = dot(w, w);
	float B = dot(u, w);
	float C = dot(u, u) - rr * rr;
	float tc = A > 1e-8 ? (-B + sqrt(max(B * B - A * C, 0.0))) / A : 1e6;
	float ra = dot(rd, a);
	float s_dr = hole_c[j].x;
	float s_out = hole_c[j].y;
	bool through = s_dr >= s_out - 1e-3;
	float tf = ra > 1e-4 ? ((through ? s_out : s_dr) - s) / ra : 1e6;
	float tb = ra < -1e-4 ? (hole_b[j].w - s) / ra : 1e6;
	tc = max(tc, 0.0);
	tf = max(tf, 0.0);
	if (tc <= tf && tc <= tb) {
		return vec2(tc, 0.0);
	}
	if (tf <= tb) {
		return vec2(tf, through ? 2.0 : 1.0);
	}
	return vec2(tb, 2.0);
}

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
	h.tex_p = vec3(0.0);
	h.tex_n = vec3(0.0, 0.0, 1.0);
	h.zone = vec2(0.0, 99.0);
	h.interior = false;
	vec3 rd = normalize(p - cam);
	if (cut_side != 0.0) {
		float f = cut_field(p);
		if (f > 0.0) {
			h.discard_it = true;
			return h;
		}
		float age = hole_now - cut_heat.y;
		if (!front_facing && !cut_capped) {
			// Seen through the opening: the cut surface, between the camera and this face.
			float dist = length(p - cam);
			float t = dist;
			for (int k = 0; k < 4; k++) {
				vec3 q = cam + rd * t;
				float g = cut_field(q);
				float slope = dot(rd, cut_plane.xyz) * cut_side;
				if (abs(slope) < 1e-3) {
					break;
				}
				t -= g / slope;
			}
			vec3 qb = cam + rd * t;
			vec3 cn = cut_plane.xyz;
			vec3 c1 = normalize(cross(cn, abs(cn.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			vec2 uv = vec2(dot(qb, c1), dot(qb, cross(cn, c1)));
			bool in_box = true;
			for (int k = 0; k < 24; k++) {
				if (k >= cut_edge_count) {
					break;
				}
				if (dot(cut_edges[k].xy, uv) > cut_edges[k].z) {
					in_box = false;
					break;
				}
			}
			if (t > 0.0 && t < dist && in_box) {
				vec3 q = cam + rd * t;
				h.inside = true;
				h.depth = t - dist;
				h.normal_part = cut_plane.xyz * cut_side;
				vec3 n = cut_plane.xyz;
				vec3 e1 = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
				h.tex_p = vec3(dot(q, e1), dot(q, cross(n, e1)), 0.0);
				h.tex_n = vec3(0.0, 0.0, 1.0);
				h.temperature = hole_cool(cut_heat.x * (0.85 + 0.3 * hole_noise(h.tex_p.xy * 1.6)), age);
				return h;
			}
		} else if (f > -0.25) {
			// The torn rim along the cut.
			float k = 1.0 - smoothstep(0.0, 0.25, -f);
			h.lip = max(h.lip, k * 0.9);
			h.scorch = max(h.scorch, 1.0 - smoothstep(0.0, 0.9, -f));
			h.temperature = max(h.temperature, 290.0 + (hole_cool(cut_heat.x, age) - 290.0) * k);
		}
	}
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
		if (s_dr < 0.0) {
			if (d < r * 1.4 && abs(s - s_in) < r * 0.6) {
				vec3 m1 = normalize(cross(a, abs(a.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
				vec2 c = vec2(dot(radial, m1), dot(radial, cross(a, m1))) / r;
				float edge = 0.75 + 0.3 * hole_noise(c * 2.3 + float(i) * 3.1);
				h.scorch = max(h.scorch, (1.0 - smoothstep(edge * 0.35, edge, d / r)) * 0.95);
			}
			continue;
		}
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
			// A panel's opening (wide and short): torn, not melted, open to its ragged edge.
			bool panel_hole = (s_out - s_in) < r * 0.9;
			if (d >= r * flare && !panel_hole) {
				// Between the true bore and the ragged outline: melted lip.
				h.lip = 1.0;
				h.temperature = max(h.temperature, t_now);
				h.zone = vec2(ang + seed, 0.0);
				continue;
			}
			// Cast the view ray through the removed metal: the union of every hole it is in
			// (overlapping holes from shots into the same spot), to the first wall or floor
			// left standing; past a through hole's far end it has left the part (open).
			float rr0 = panel_hole ? max(rw, d + 1e-3) : r * flare;
			vec2 lv = hole_leave(i, p, rd, rr0);
			float t_hit = lv.x;
			float kind = lv.y;
			int last = i;
			for (int k = 0; k < 6; k++) {
				if (kind > 1.5) {
					break;
				}
				vec3 y = p + rd * (t_hit + 0.004);
				int nxt = -1;
				for (int j = 0; j < HOLE_MAX; j++) {
					if (j >= hole_count) {
						break;
					}
					if (j != last && hole_holds(j, y)) {
						nxt = j;
						break;
					}
				}
				if (nxt < 0) {
					break;
				}
				vec2 l2 = hole_leave(nxt, y, rd, hole_rr(nxt, dot(y - hole_a[nxt].xyz, hole_b[nxt].xyz)));
				t_hit += 0.004 + l2.x;
				kind = l2.y;
				last = nxt;
			}
			// The surface it stops on, in hole `last`'s terms.
			vec3 lo = hole_a[last].xyz;
			vec3 la = hole_b[last].xyz;
			// Never open: where the ray would leave the part (a through hole's far end) or come
			// out of the armour into the part's hollow inside, the opening is closed there by
			// rough re-melted metal (the torn insides), as a floor across the bore.
			bool cap = kind > 1.5;
			float t_cap = t_hit;
			float l_hs = dot(p + rd * t_hit - lo, la);
			if (l_hs > hole_d[last].x && l_hs < hole_d[last].y) {
				cap = true;
				float ra_l = dot(rd, la);
				t_cap = ra_l > 1e-4 ? clamp((hole_d[last].x - dot(p - lo, la)) / ra_l, 0.0, t_hit) : t_hit;
			}
			if (cap) {
				vec3 g1 = normalize(cross(la, abs(la.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
				vec3 cp = p + rd * t_cap - lo;
				float c_seed = float(last) * 1.73 + hole_c[last].z * 0.37 + 11.0;
				h.inside = true;
				h.depth = t_cap;
				h.normal_part = -la;
				h.tex_p = vec3(dot(cp, g1), dot(cp, cross(la, g1)), dot(cp, la)) + c_seed;
				h.tex_n = vec3(0.0, 0.0, -1.0);
				h.temperature = hole_cool(hole_c[last].w * 0.75, hole_now - hole_c[last].z);
				return h;
			}
			float l_s_in = hole_b[last].w;
			float l_dr = hole_c[last].x;
			float l_out = hole_c[last].y;
			float l_age = hole_now - hole_c[last].z;
			float l_peak = hole_c[last].w;
			float l_seed = float(last) * 1.73 + hole_c[last].z * 0.37;
			vec3 f1 = normalize(cross(la, abs(la.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			vec3 f2 = cross(la, f1);
			vec3 hp = p + rd * t_hit - lo;
			float hs = dot(hp, la);
			vec3 hr = hp - la * hs;
			h.inside = true;
			h.depth = t_hit;
			if (kind > 0.5) {
				// A crater's floor at s_drill, rounded off toward the wall.
				float lrr = hole_rr(last, hs);
				float fr = clamp(length(hr) / lrr, 0.0, 1.0);
				h.normal_part = normalize(-la + hr / lrr * fr * 0.8);
				// The face the beam is still on is white-hot.
				h.temperature = hole_cool(l_peak + 500.0 * exp(-l_age * 6.0), l_age) * mix(1.0, 0.85, fr * fr);
			} else {
				h.normal_part = -normalize(hr);
				bool l_through = l_dr >= l_out - 1e-3;
				float l_f = clamp((hs - l_s_in) / max((l_through ? l_out : l_dr) - l_s_in, 1e-3), 0.0, 1.0);
				h.temperature = hole_cool(l_peak * (l_through ? 1.0 - 0.12 * l_f : 0.9 + 0.1 * l_f), l_age);
			}
			h.tex_p = vec3(dot(hp, f1), dot(hp, f2), hs) + l_seed;
			h.tex_n = vec3(dot(h.normal_part, f1), dot(h.normal_part, f2), dot(h.normal_part, la));
			return h;
		}
		// Around the mouth.
		float x = max(d - rw, 0.0) / r;
		// Fades out (no hard edge) past the far end and well before the entry.
		float zone = along ? 1.0 : (1.0 - smoothstep(s_out + r * 0.5, s_out + r * 1.5, s))
				* smoothstep(s_in - r * 3.0, s_in - r * 2.0, s);
		if (zone > 0.0) {
			float spread = exp(-x * 2.6) * zone;
			if (x < h.zone.y) {
				h.zone = vec2(ang + seed, x);
			}
			h.temperature = max(h.temperature, 290.0 + (t_now - 290.0) * spread);
			h.lip = max(h.lip, (1.0 - smoothstep(0.0, 0.22, x)) * 0.85 * zone);
			h.scorch = max(h.scorch, (1.0 - smoothstep(0.1, 1.6 + 0.5 * hole_noise(vec2(ang * 2.0, seed)), x)) * zone);
			h.tint = max(h.tint, (1.0 - smoothstep(0.4, 1.1, x)) * smoothstep(0.05, 0.3, x) * zone);
		}
		if (!front_facing) {
			h.near_heat = max(h.near_heat, 290.0 + (t_now - 290.0) * exp(-x * 0.5));
			h.interior = h.interior || x < 4.0;
		}
	}
	return h;
}
