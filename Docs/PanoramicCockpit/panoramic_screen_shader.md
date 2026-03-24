# panoramic_screen.gdshader

**File:** `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/Shader/panoramic_screen.gdshader`

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

**`cull_back`** — Back faces are discarded. The mesh normals point **inward** (toward the sphere
centre), so the "front face" is the inner surface — visible from inside (pilot) and at glancing
angles from outside (third-person through open hatch).

**`depth_draw_opaque`** — Writes to the depth buffer even though `EMISSION` is set, ensuring the
screen mesh correctly occludes objects behind it in the cockpit.

---

## Uniforms Reference

### Sensor Camera Data (updated every frame by `PanoramicScreen._push_shader_uniforms()`)

```glsl
uniform sampler2D sensor_viewport : hint_default_black, filter_linear_mipmap;
```
The rendered texture from the sensor SubViewport. `hint_default_black` = unset means black
(no signal). `filter_linear_mipmap` enables bilinear interpolation plus mipmapping — mipmaps
matter when the viewer is far from the screen (third-person), where many screen pixels map to
a large region of the sensor texture and without mipmaps you'd get aliasing/flickering.

```glsl
uniform mat4 sensor_view_proj;
```
The combined `projection × view` matrix of the sensor camera:
```gdscript
_camera.get_camera_projection() * Projection(_camera.transform.affine_inverse())
```
Transforms a world-space point into the sensor camera's clip space (`[-1,1]` NDC after perspective
divide). Note: uses `_camera.transform`, not `global_transform` — see SubViewport position trick
in `sensor_head.md`.

```glsl
uniform vec3 sensor_world_pos;
```
World-space position of the sensor camera (`_camera.transform.origin`). Used as the ray origin
when building the sample point.

```glsl
uniform mat3 sensor_basis;
```
World-space orientation of the sensor head node (`SensorHead.global_transform.basis`). This is
the **fixed** orientation of the mech's sensor coordinate frame — rotates with the mech body,
but does **not** rotate when the sensor camera tracks the viewer's head movement.

This is the most critical uniform. See the dedicated section below.

### Screen Geometry (set once on `_setup_material()`)

```glsl
uniform float panoramic_elevation_range = 1.5707963; // PI/2 = ±45°
```
Total vertical angle span of the screen in radians. Must match `PanoramicScreen.elevation_range`.
Used to recover elevation from `UV2.y`: `elevation = (UV2.y - 0.5) * panoramic_elevation_range`.

```glsl
uniform sampler2D segment_mask : hint_default_white, filter_nearest;
```
A `segment_count × 1` R8 texture. `1.0` = active, `0.0` = disabled. `filter_nearest` prevents
partial-transparency artefacts at segment boundaries.

### Visual Tuning

```glsl
uniform float screen_brightness : hint_range(0.0, 5.0) = 1.5;
```
Multiplier applied to the final sampled colour. `1.5` makes the screen slightly brighter than
the world — reads as a self-lit display in a dark cockpit.

```glsl
uniform vec4 no_signal_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);
```
Colour for fragments whose projected UV falls outside the sensor viewport bounds. Nearly black
with a slight blue tint — mimics a monitor with no input signal.

```glsl
uniform vec4 damaged_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
```
Colour for fragments in a disabled segment (via the segment mask). Pure black by default.

---

## Fragment Shader — Step by Step

### Step 1 — Recover Azimuth and Elevation from UV2

```glsl
float azimuth   = UV2.x * TAU;
float elevation = (UV2.y - 0.5) * panoramic_elevation_range;
```

UV2 is baked into the mesh by `PanoramicMeshBuilder.build()`:
```
UV2.x = azimuth_absolute / TAU       ← may be outside [0,1] if arc_offset ≠ 0
UV2.y = elevation_normalised [0,1]   ← 0 = bottom, 1 = top
```

### Step 2 — Check the Segment Mask

```glsl
float active = texture(segment_mask, vec2(fract(UV2.x), 0.5)).r;
if (active < 0.5) {
    ALBEDO = EMISSION = damaged_color.rgb;
} else {
    // steps 3–6
}
```

`fract(UV2.x)` maps absolute azimuth back to `[0,1]` to correctly index the mask regardless of
`arc_offset`.

**Why `if/else` instead of `return`?** Godot 4's GLSL compiler does not allow `return` inside
`fragment()`. All early-exit logic must use nested `if/else`.

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

`local_dir` is the direction this fragment represents in the sensor's local coordinate frame.
At `azimuth = 0, elevation = 0`: `local_dir = (0, 0, -1)` — the forward direction.

`sensor_basis * local_dir` rotates it into world space using the sensor head's **fixed**
orientation. If the mech has turned 90° left, `sensor_basis` encodes that and `world_dir` points
in the correct world direction.

### Step 4 — Project Through the Sensor Camera

```glsl
vec4 clip = sensor_view_proj * vec4(sensor_world_pos + world_dir * 500.0, 1.0);
if (clip.w <= 0.0) {
    ALBEDO = EMISSION = no_signal_color.rgb;
} else {
```

Projecting a point 500 m along the ray (effectively at infinity) avoids near-plane clipping and
treats the sensor as a sky-dome renderer. The `clip.w <= 0` guard prevents the perspective divide
from flipping directions behind the camera.

### Step 5 — Perspective Divide and Y-Flip

```glsl
vec2 ndc = clip.xy / clip.w;
vec2 sample_uv = vec2(ndc.x * 0.5 + 0.5, 1.0 - (ndc.y * 0.5 + 0.5));
```

NDC `[-1,1]` → UV `[0,1]`. The **Y-flip** (`1.0 - (...)`) is required because Godot's
SubViewport texture has `Y = 0` at the top, opposite to OpenGL's NDC convention.

### Step 6 — Bounds Check and Sample

```glsl
if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
    ALBEDO = EMISSION = no_signal_color.rgb;
} else {
    vec3 color = texture(sensor_viewport, sample_uv).rgb * screen_brightness;
    ALBEDO = color; EMISSION = color;
}
```

Setting both `ALBEDO` and `EMISSION` to the same colour makes the screen self-illuminated.
With `render_mode unshaded`, only `ALBEDO` affects the final output — `EMISSION` is set
defensively in case `unshaded` is ever removed for testing.

---

## Why `sensor_basis` Is the Most Critical Uniform

**Option A — SensorHead's fixed orientation** (correct):
`sensor_basis` encodes where the mech is facing. The view matrix sees `world_dir` from a
different angle as the player looks around → the correct screen region is sampled.

**Option B — Sensor camera's current tracking rotation** (wrong):
If `sensor_basis` were the rotating camera basis `R`, and `sensor_view_proj` contains `R⁻¹`:
```
world_dir     = R  × local_dir
projected_dir = R⁻¹ × world_dir = R⁻¹ × R × local_dir = local_dir
```
The rotation cancels. Every fragment samples the same UV regardless of look direction.
The screen content is frozen.

---

## Coordinate System Summary

| Space | Convention | Notes |
|-------|-----------|-------|
| Sensor local | +X right, +Y up, -Z forward | Godot Node3D standard |
| Azimuth = 0 | (0, 0, -1) in sensor local | Forward direction |
| Azimuth increases | Counter-clockwise from above | Standard polar |
| NDC | [-1,1] × [-1,1], Y-up | OpenGL convention |
| Texture UV | [0,1] × [0,1], Y-down | Godot SubViewport |
| Y-flip | `v = 1.0 - v` | Applied during NDC → UV remap |

---

## Common Shader Artefacts and Causes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Screen entirely black | `sensor_view_proj` all zeros (uniforms not pushed) | Check `sensor_head` auto-discovered correctly, or set the export manually |
| Screen frozen / not moving | `sensor_basis` set to camera's rotating basis | Ensure `get_sensor_basis()` returns `global_transform.basis` (SensorHead's own orientation) |
| Screen upside-down | Y-flip missing or applied twice | Check `1.0 - (ndc.y * 0.5 + 0.5)` is exactly once |
| Thin black seam lines | Sensor FOV too narrow | Increase `fov_safety_margin_degrees` |
| Image mirrored left/right | `sensor_basis` has wrong handedness or X was negated | Verify `local_dir.z = -cos(azimuth)` and X is not negated |
| Dark band at top/bottom | `elevation_range` mismatch between mesh and shader | `panoramic_elevation_range` uniform must equal `PanoramicScreen.elevation_range` |
| Segment boundary has soft blur | `segment_mask` using `filter_linear` | Change sampler filter to `filter_nearest` |
