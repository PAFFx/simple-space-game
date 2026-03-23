# panoramic_screen.gdshader

**File:** `Common/PanoramicDisplay/panoramic_screen.gdshader`

---

## What This Shader Does in One Sentence

For each pixel on the sphere mesh, it asks: *"which real-world direction does this pixel represent,
and where does the sensor camera see that direction?"* — then samples the sensor's rendered texture
at that location.

---

## Render Mode

```glsl
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
```

**`unshaded`** — No lighting calculation is performed. `ALBEDO` and `EMISSION` are written directly
to the output without any light contribution. This is correct because the screen is a self-emitting
display, not a surface reflecting ambient light. Lighting would dim or tint the image based on
cockpit light placement, which is wrong for a display panel.

**`cull_back`** — Back faces are discarded by the GPU before the fragment shader runs. The mesh
normals point **inward** (toward the sphere centre), so the "front face" is the inner surface.
This means:
- Camera inside the sphere (pilot, first-person): sees the inner face → rendered ✓
- Camera outside the sphere (third-person, far away): depends on viewing angle. When the
  third-person camera looks into the cockpit through an open hatch it can see the inner face
  at glancing angles; faces pointing directly away from it are culled ✓

**`depth_draw_opaque`** — Writes to the depth buffer even though `EMISSION` is set, ensuring the
screen mesh correctly occludes objects behind it in the cockpit.

---

## Uniforms Reference

### Sensor Camera Data (updated every frame by `PanoramicScreen._push_shader_uniforms()`)

```glsl
uniform sampler2D sensor_viewport : hint_default_black, filter_linear_mipmap;
```
The rendered texture from the sensor SubViewport. `hint_default_black` means unset = black
(no signal), which is the correct safe default. `filter_linear_mipmap` enables bilinear
interpolation plus mipmapping. Mipmaps matter here: when the viewer is far from the screen
(third-person), many screen pixels map to a large region of the sensor texture and without
mipmaps you'd get aliasing/flickering.

```glsl
uniform mat4 sensor_view_proj;
```
The combined `projection × view` matrix of the sensor camera, computed as:
```gdscript
_camera.get_camera_projection() * Projection(_camera.transform.affine_inverse())
```
This is the matrix that transforms a world-space point into the sensor camera's clip space
(`[-1,1]` NDC after perspective divide). Used in Step 4 of the fragment shader.

```glsl
uniform vec3 sensor_world_pos;
```
World-space position of the sensor camera (`_camera.transform.origin`). Used as the ray
origin when building the sample point. Note: this is read from `_camera.transform.origin`,
not `_camera.global_position`, because `Camera3D` inside a `SubViewport` (a non-spatial Node)
uses its local transform directly as world-space — see `sensor_head.md` for details.

```glsl
uniform mat3 sensor_basis;
```
World-space orientation of the sensor head node (`SensorHead.global_transform.basis`). This
is the **fixed** orientation of the mech's sensor coordinate frame — it rotates when the mech
body rotates, but does **not** rotate when the sensor camera tracks the viewer's head movement.

This is the most critical uniform. See the dedicated section below.

### Screen Geometry (set once on `_setup_material()`)

```glsl
uniform float panoramic_elevation_range = 1.5707963; // PI/2 = ±45°
```
Total vertical angle span of the screen in radians. Matches `PanoramicScreen.elevation_range`.
Used to recover elevation from `UV2.y`: `elevation = (UV2.y - 0.5) * panoramic_elevation_range`.
The default `PI/2` covers ±45°. A full hemisphere is `PI` (±90°).

```glsl
uniform sampler2D segment_mask : hint_default_white, filter_nearest;
```
A `segment_count × 1` R8 texture. Each pixel represents one horizontal arc segment:
`1.0` = active (normal display), `0.0` = disabled (damaged panel, open door).
`hint_default_white` means all segments active when unset. `filter_nearest` is used because
this is a 1D mask — bilinear blending between active and disabled segments would create
partial-transparency artefacts at segment boundaries.

### Visual Tuning (can be changed at runtime)

```glsl
uniform float screen_brightness : hint_range(0.0, 5.0) = 1.5;
```
Multiplier applied to the final sampled colour. `1.0` = match sensor render exactly.
`1.5` makes the screen slightly brighter than the world, which reads as a self-lit display
in a dark cockpit. Increase for a harsh, washed-out look; decrease for a dim or damaged feel.

```glsl
uniform vec4 no_signal_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);
```
Colour for fragments whose projected UV falls outside the sensor viewport bounds. Nearly black
with a very slight blue tint — mimics the look of a monitor with no input. This appears when:
- The sensor camera FOV is slightly too narrow (edge case, covered by `fov_safety_margin_degrees`)
- The viewer looks at the edge of the screen while the sensor hasn't caught up (1-frame lag)

```glsl
uniform vec4 damaged_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
```
Colour for fragments in a disabled segment (via the segment mask). Pure black by default.
Could be changed to a static pattern (e.g. static noise via a noise texture) for a more
cinematic damaged-screen look.

---

## Fragment Shader — Step by Step

### Step 1 — Recover Azimuth and Elevation from UV2

```glsl
float azimuth   = UV2.x * TAU;
float elevation = (UV2.y - 0.5) * panoramic_elevation_range;
```

`UV2` is the second UV channel baked into the mesh by `PanoramicScreen._build_mesh()`:
```
UV2.x = azimuth_absolute / TAU       ← may be outside [0,1] if arc_offset ≠ 0
UV2.y = elevation_normalised [0,1]   ← 0 = bottom edge, 1 = top edge
```

`UV2.x * TAU` recovers the absolute azimuth in radians. The mesh uses absolute azimuth
(not the arc-relative `t_arc`) so that the panoramic direction is correct regardless of
the screen's arc offset. sin/cos of the absolute azimuth give the correct world direction
in sensor-local space.

`(UV2.y - 0.5) * elevation_range` centres the elevation around 0:
- `UV2.y = 0` → `elevation = -elevation_range / 2` (bottom)
- `UV2.y = 0.5` → `elevation = 0` (equator)
- `UV2.y = 1` → `elevation = +elevation_range / 2` (top)

### Step 2 — Check the Segment Mask

```glsl
float active = texture(segment_mask, vec2(fract(UV2.x), 0.5)).r;
if (active < 0.5) {
    ALBEDO   = damaged_color.rgb;
    EMISSION = damaged_color.rgb;
} else {
    // ... steps 3-6
}
```

`fract(UV2.x)` maps the absolute azimuth back to `[0,1]` so it correctly indexes the segment
mask regardless of `arc_offset`. For example:
- `arc_offset = PI` → UV2.x starts at `PI/TAU ≈ 0.5`, so `fract(0.5) = 0.5` → samples mask
  at the halfway point, which is the correct position for that direction.

The `0.5` threshold treats anything below half-brightness as disabled. Since the mask uses
pure black (0.0) and pure white (1.0), this threshold is unambiguous.

**Why does the entire chain use `if/else` instead of `return`?**
Godot's GLSL compiler does not allow `return` in the `fragment()` function (it causes a
compile error in Godot 4). All early-exit logic must use nested `if/else` blocks.

### Step 3 — Build the World-Space Direction

```glsl
float cos_el   = cos(elevation);
vec3 local_dir = vec3(
     sin(azimuth) * cos_el,    // X: rightward
     sin(elevation),            // Y: upward
    -cos(azimuth) * cos_el     // Z: forward (-Z convention in Godot)
);
vec3 world_dir = sensor_basis * local_dir;
```

`local_dir` is the direction this fragment represents in the **sensor's local coordinate frame**,
using the standard spherical coordinate conversion:

```
x = sin(azimuth) × cos(elevation)    ← east/right component
y = sin(elevation)                    ← up component
z = -cos(azimuth) × cos(elevation)   ← forward component (-Z because Godot is right-handed, -Z forward)
```

At `azimuth = 0, elevation = 0`: `local_dir = (0, 0, -1)` — the forward direction. This is
consistent with how Godot's `Camera3D` and `Node3D` work: `-Z` is "forward" for any node.

`sensor_basis * local_dir` rotates `local_dir` into world space using the sensor head's fixed
orientation. If the mech has turned 90° left, `sensor_basis` encodes that rotation and `world_dir`
points in the correct world direction.

### Step 4 — Project Through the Sensor Camera

```glsl
vec4 clip = sensor_view_proj * vec4(sensor_world_pos + world_dir * 500.0, 1.0);
```

Instead of projecting a point on the sphere surface, the shader projects a point **500 metres
along the ray** from the sensor position. This is effectively at infinity for any in-game object
and has two advantages:
- Avoids near-plane clipping (`_camera.near = 0.5`) since the point is always far away
- Treats the sensor as a "sky dome" renderer — parallax between sensor and real object positions
  is negligible beyond ~20 m (relevant for space games with no close geometry)

`clip` is now in homogeneous clip space. The `w` component is the depth; negative `w` means the
point is behind the camera (below the near plane or flipped).

```glsl
if (clip.w <= 0.0) {
    ALBEDO   = no_signal_color.rgb;
    EMISSION = no_signal_color.rgb;
} else {
```

The `clip.w <= 0.0` guard is essential. Without it, the perspective divide by a negative `w`
would flip the NDC coordinates, causing fragments behind the camera to appear mirrored on the
opposite side of the screen.

### Step 5 — Perspective Divide and Y-Flip

```glsl
vec2 ndc = clip.xy / clip.w;

vec2 sample_uv = vec2(
     ndc.x * 0.5 + 0.5,
    1.0 - (ndc.y * 0.5 + 0.5)
);
```

`clip.xy / clip.w` performs the **perspective divide**, converting from homogeneous clip space to
NDC (Normalized Device Coordinates). NDC range is `[-1, 1]` on both axes.

`ndc * 0.5 + 0.5` remaps `[-1, 1]` to `[0, 1]` — standard UV range.

The **Y-flip** (`1.0 - (...)`) is required because:
- In NDC: `Y = +1` is the top of the screen, `Y = -1` is the bottom (OpenGL convention)
- In Godot's SubViewport texture: `Y = 0` is the top, `Y = 1` is the bottom (texture convention)

Without the flip, the image would appear vertically mirrored on the panoramic screen.

### Step 6 — Bounds Check and Sample

```glsl
if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
    ALBEDO   = no_signal_color.rgb;
    EMISSION = no_signal_color.rgb;
} else {
    vec3 color = texture(sensor_viewport, sample_uv).rgb * screen_brightness;
    ALBEDO   = color;
    EMISSION = color;
}
```

`any(lessThan(...))` / `any(greaterThan(...))` are GLSL vector comparison functions that check
if **either** component of `sample_uv` is outside `[0, 1]`. This is equivalent to:
```glsl
if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0)
```
but using GLSL's vectorised comparison is idiomatic and often maps to a single GPU instruction.

Fragments outside bounds get `no_signal_color` — the sensor camera didn't render that direction.
This is a safety net; with correct `fov_safety_margin_degrees` it should rarely trigger.

Setting both `ALBEDO` and `EMISSION` to the same colour makes the screen appear self-illuminated.
`ALBEDO` is what lighting would affect; `EMISSION` bypasses lighting entirely. Because
`render_mode unshaded` is set, only `ALBEDO` matters for the final output — but setting
`EMISSION` too makes the values correct if `unshaded` is ever removed for testing.

---

## Why `sensor_basis` Is the Most Critical Uniform

The shader converts a UV2 panoramic direction to world space with:
```glsl
vec3 world_dir = sensor_basis * local_dir;
```

There are two candidates for what `sensor_basis` could be:

**Option A — SensorHead's fixed orientation** (what we use):
`sensor_basis` encodes where the mech is facing. Azimuth = 0 always maps to the mech's forward
direction. When the player looks left, the sensor camera rotates left, but `sensor_basis` doesn't
change. The view matrix `sensor_view_proj` now sees `world_dir` from a different angle → the
correct screen region is sampled → the screen appears to show what's ahead.

**Option B — Sensor camera's current tracking rotation** (wrong):
If `sensor_basis` were the camera's rotating basis `R`, then the view matrix inside
`sensor_view_proj` contains `R⁻¹`. The combined effect on `local_dir` is:
```
world_dir        = R  × local_dir
projected_dir    = R⁻¹ × world_dir = R⁻¹ × R × local_dir = local_dir
```
The rotation cancels. Every fragment samples the same UV regardless of where the player looks.
The screen content is frozen — it never moves. This was a real bug encountered during development.

---

## Coordinate System Summary

| Space | Convention | Notes |
|-------|-----------|-------|
| Sensor local | +X right, +Y up, -Z forward | Godot Node3D standard |
| Azimuth = 0 | (0, 0, -1) in sensor local | Forward direction |
| Azimuth increases | Counter-clockwise when viewed from above | Standard polar |
| NDC | [-1,1] × [-1,1], Y-up | OpenGL convention |
| Texture UV | [0,1] × [0,1], Y-down | Godot SubViewport |
| Y-flip | `v = 1.0 - v` | Applied during NDC → UV remap |

---

## Common Shader Artefacts and Causes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Screen entirely black | `sensor_view_proj` all zeros (uniforms not pushed) | Check `sensor_head` export is wired on `PanoramicScreen` |
| Screen frozen / not moving | `sensor_basis` is set to camera's rotating basis instead of SensorHead's fixed basis | Ensure `get_sensor_basis()` returns `global_transform.basis` |
| Screen upside-down | Y-flip missing or applied twice | Check `1.0 - (ndc.y * 0.5 + 0.5)` is exactly once |
| Thin black seam lines | Sensor FOV too narrow; edge fragments project outside viewport bounds | Increase `fov_safety_margin_degrees` or check `_update_camera()` computation |
| Image mirrored left/right | X was also flipped; or `sensor_basis` has wrong handedness | Verify `local_dir.z = -cos(azimuth)` and X is not negated |
| Dark band at top/bottom | `elevation_range` in shader doesn't match mesh `elevation_range` export | `panoramic_elevation_range` uniform must match `PanoramicScreen.elevation_range` |
| Segment boundary has a soft blur | `segment_mask` sampler using `filter_linear` instead of `filter_nearest` | Change sampler filter to `filter_nearest` |
