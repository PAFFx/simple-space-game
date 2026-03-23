# PanoramicScreen

**Script:** `Common/PanoramicDisplay/panoramic_screen.gd`
**Shader:** `Common/PanoramicDisplay/panoramic_screen.gdshader`
**Scene:** `Common/PanoramicDisplay/panoramic_screen.tscn`
**Class:** `PanoramicScreen extends Node3D`

---

## Purpose

`PanoramicScreen` owns the spherical mesh that forms the cockpit display surface. It:

1. Generates an `ArrayMesh` with **UV2 panoramic direction coordinates** baked into each vertex
2. Assigns a `ShaderMaterial` that reprojects those directions through the sensor camera
3. Pushes updated sensor uniforms to the shader every frame
4. Manages a 1D segment mask texture for per-arc-segment damage / door-open effects

The script is `@tool` — the mesh rebuilds live in the editor when any geometry export is changed,
and shows a semi-transparent blue placeholder so the sphere is visible during placement.

---

## Exports

### Geometry

```gdscript
@export var arc_angle: float = TAU        # total horizontal span in radians
@export var arc_offset: float = 0.0       # azimuth start offset in radians
@export var elevation_range: float = PI   # total vertical span in radians (±elevation_range/2)
@export var screen_radius: float = 1.2    # sphere radius in metres
@export var arc_segments: int = 128       # horizontal mesh resolution
@export var elevation_segments: int = 128 # vertical mesh resolution
```

All geometry exports have setters that call `_rebuild_in_editor()`, so the mesh updates
immediately in the Godot editor Inspector without running the scene.

**`arc_angle`** — How much of the 360° circle the screen covers.
- `TAU` (6.283): full 360° panoramic — the sphere completely encloses the pilot.
- `PI` (3.14): 180° semicircle — only the forward half.

**`elevation_range`** — How tall the screen is (vertical span).
- `PI` (3.14): full ±90°, top-to-bottom hemisphere. This is the most common default.
- `PI / 2` (1.57): ±45°, a narrower band around the equator.
- The shader reads this value as `panoramic_elevation_range` and uses it to recover the elevation
  angle from UV2: `elevation = (UV2.y - 0.5) * elevation_range`.

**`screen_radius`** — The sphere radius in world units (metres in Godot default physics scale).
Should be large enough that the pilot camera sits comfortably inside, and not so large that the
near-clip plane clips into the sphere surface. 1.2 m works for a human-scale cockpit.

### Mask

```gdscript
@export var segment_count: int = 64
```

The number of independently togglable horizontal segments in the damage/door mask. Each segment
spans `arc_angle / segment_count` radians. Higher values = finer damage granularity at the cost
of a larger texture (still 1D, so 64 px is trivial).

---

## The UV2 Panoramic Encoding

Every vertex has two UV channels:

- **UV0** (`ARRAY_TEX_UV`): standard spherical wrap `(t_arc, 1 - t_elev)`. Reserved for optional
  cockpit-detail overlays (cracks, wear, HUD elements) that future shaders may sample.

- **UV2** (`ARRAY_TEX_UV2`): panoramic direction encoding used by the reprojection shader.
  ```
  UV2.x = azimuth / TAU      ← normalised absolute azimuth (may be outside [0,1] if arc_offset ≠ 0)
  UV2.y = t_elev             ← elevation normalised to [0, 1] (0 = bottom, 1 = top)
  ```

Using **absolute** azimuth (not `t_arc`) is intentional. It means:
- A vertex at azimuth = 2.5 rad has UV2.x = 2.5 / TAU ≈ 0.398 regardless of `arc_offset`.
- The shader uses `fract(UV2.x)` to sample the segment mask, correctly wrapping any offset.
- The shader uses `UV2.x * TAU` to recover the absolute azimuth for direction math, which is
  always correct because sin/cos are periodic.

### Why UV2 and not UV0?

The reprojection shader needs a separate, clean channel for direction data. UV0 could be shared
if there were no overlay textures, but UV2 avoids a conflict if a second shader or decal layer
is added later.

### Vertex formula

```gdscript
azimuth   = arc_offset + t_arc * arc_angle
elevation = (t_elev - 0.5) * elevation_range
cos_el    = cos(elevation)

vertex = Vector3(
    screen_radius * sin(azimuth) * cos_el,   # X (rightward)
    screen_radius * sin(elevation),           # Y (upward)
   -screen_radius * cos(azimuth) * cos_el    # Z (forward is -Z in Godot)
)
```

This places each vertex on a sphere of radius `screen_radius` centred at `PanoramicScreen`'s
local origin, with azimuth = 0 pointing in the `-Z` (forward) direction.

### Inward normals

```gdscript
normal = Vector3(-sin(azimuth) * cos_el, -sin(elevation), cos(azimuth) * cos_el)
```

Normals point **toward the sphere's centre** (inward). Combined with `cull_back` in the shader,
this means:
- The surface is visible when the camera is **inside** the sphere (normals face toward the camera)
- The surface is culled when the camera is outside (normals face away)

This is correct for the first-person case. The third-person visibility (open hatch) works because
the third-person camera can sometimes look into the cockpit interior from outside, seeing the
inner face of the screen at grazing angles.

---

## The Reprojection Shader

### Uniforms

| Uniform | Type | Updated | Description |
|---------|------|---------|-------------|
| `sensor_viewport` | `sampler2D` | Every frame | Rendered texture from the sensor SubViewport |
| `sensor_view_proj` | `mat4` | Every frame | `projection × view` matrix of sensor camera |
| `sensor_world_pos` | `vec3` | Every frame | World position of the sensor camera |
| `sensor_basis` | `mat3` | Every frame | SensorHead's fixed world orientation |
| `panoramic_elevation_range` | `float` | Once on setup | Matches `PanoramicScreen.elevation_range` |
| `segment_mask` | `sampler2D` | On mask change | 1D R8 image, white = active, black = disabled |
| `screen_brightness` | `float` | Static | Emissive brightness multiplier (default 1.5) |
| `no_signal_color` | `vec4` | Static | Color for out-of-range projections (near-black) |
| `damaged_color` | `vec4` | Static | Color for disabled segments (black by default) |

### Fragment shader walkthrough

```glsl
void fragment() {
    // Step 1 — Recover azimuth and elevation from UV2
    float azimuth   = UV2.x * TAU;
    float elevation = (UV2.y - 0.5) * panoramic_elevation_range;
```
UV2.y is in [0, 1]. Subtracting 0.5 centres it around 0, then multiplying by
`elevation_range` gives the actual elevation angle in radians (negative = below equator).

```glsl
    // Step 2 — Check segment mask
    float active = texture(segment_mask, vec2(fract(UV2.x), 0.5)).r;
    if (active < 0.5) {
        ALBEDO = EMISSION = damaged_color.rgb;
    } else {
```
`fract(UV2.x)` maps absolute azimuth back to [0, 1] so the mask is indexed correctly
even when `arc_offset` makes UV2.x go outside [0, 1].

```glsl
        // Step 3 — Build world-space direction
        float cos_el   = cos(elevation);
        vec3 local_dir = vec3(sin(azimuth) * cos_el, sin(elevation), -cos(azimuth) * cos_el);
        vec3 world_dir = sensor_basis * local_dir;
```
`local_dir` is the direction this fragment represents in sensor-local space (azimuth = 0 → `-Z`).
`sensor_basis` transforms it to world space. `sensor_basis` is `SensorHead.global_transform.basis`
— **fixed** to the mech body, not the sensor camera's rotating orientation.

```glsl
        // Step 4 — Project through the sensor camera
        vec4 clip = sensor_view_proj * vec4(sensor_world_pos + world_dir * 500.0, 1.0);
        if (clip.w <= 0.0) {
            ALBEDO = EMISSION = no_signal_color.rgb;
        } else {
            vec2 ndc = clip.xy / clip.w;
```
Multiplying `world_dir` by 500 places the sample point 500 m from the sensor. This is effectively
infinity for world-scale objects and avoids any near-plane clipping. The `clip.w <= 0` guard
catches directions behind the sensor camera (below its near plane).

```glsl
            // Step 5 — NDC to UV with Y-flip
            vec2 sample_uv = vec2(ndc.x * 0.5 + 0.5, 1.0 - (ndc.y * 0.5 + 0.5));
```
NDC is `[-1, 1]` with Y increasing upward. Godot's SubViewport texture has its origin at
**top-left** with Y increasing downward. The `1.0 - (...)` flip is required, otherwise the
display appears vertically mirrored.

```glsl
            // Step 6 — Bounds check and sample
            if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
                ALBEDO = EMISSION = no_signal_color.rgb;
            } else {
                vec3 color = texture(sensor_viewport, sample_uv).rgb * screen_brightness;
                ALBEDO = color; EMISSION = color;
            }
        }
    }
}
```
Fragments that project outside the sensor viewport get `no_signal_color`. This happens when the
sensor FOV is slightly too narrow (covered by `fov_safety_margin_degrees`) or when the viewer
looks far from the screen. Setting both `ALBEDO` and `EMISSION` makes the screen self-illuminated
(unlit) — correct for a display inside a dark cockpit.

### `render_mode unshaded`

The shader uses `unshaded` so the screen colour is not affected by cockpit lighting. The
`screen_brightness` uniform handles apparent brightness instead. This is correct behaviour —
a real display emits light rather than reflecting it.

---

## Segment Mask API

The segment mask is a `segment_count × 1` `Image.FORMAT_R8` texture stored as `_mask_image`.
It maps to the screen's azimuth: pixel index `i` covers the arc segment
`[i/segment_count, (i+1)/segment_count]` of the full 0..TAU range.

```gdscript
func set_segment_enabled(index: int, enabled: bool) -> void
```
Toggle a single segment by index (0-based from `arc_offset`). Writes one pixel to `_mask_image`
and calls `_mask_texture.update()`.

```gdscript
func set_arc_range_enabled(start_rad: float, end_rad: float, enabled: bool) -> void
```
Toggle all segments whose centre falls in `[start_rad, end_rad]`. Handles wraparound
(e.g. `start=5.5, end=0.5` crossing the 0/TAU boundary).

```gdscript
func enable_all_segments() -> void
func disable_all_segments() -> void
```
Bulk operations using `_mask_image.fill()` for efficiency.

**Example — Simulate open cockpit door on the right side:**
```gdscript
# Disable a 90° arc on the right (azimuth PI/2 … PI)
panoramic_screen.set_arc_range_enabled(PI * 0.25, PI * 0.75, false)
```

---

## Render Layers

```gdscript
_mesh_instance.layers = Layers.COCKPIT | Layers.VEHICLE_EXT
```

- **`COCKPIT`** — Visible to the first-person camera (`MASK_FIRST_PERSON` includes `COCKPIT`).
- **`VEHICLE_EXT`** — Visible to the third-person camera (`MASK_THIRD_PERSON` includes `VEHICLE_EXT`).
- **Not `MASK_SENSOR`** — The sensor camera deliberately cannot see the screen mesh. If it could,
  the screen would appear inside its own sensor feed, creating an infinite loop of reprojection.

---

## Editor `@tool` Behaviour

With `@tool`, `_ready()` runs in the editor. When `Engine.is_editor_hint()` is true:
- `_build_mesh()` is called and assigned — the sphere shape is visible in the editor.
- A semi-transparent blue `StandardMaterial3D` is applied as `material_override`.
- `_setup_material()` is **not** called — no shader material, no uniforms, no texture references.
- The function returns early.

This lets you position the sphere correctly in the editor and see its exact shape and size,
without needing the sensor head or viewport to be active.

When any geometry export is changed via the Inspector, the `set(v)` setter calls
`_rebuild_in_editor()`, which calls `_build_mesh()` again and assigns the new mesh — live update.

---

## `CockpitDisplayController` Wiring

The controller (`cockpit_display_controller.gd`) runs at `_ready()` in the assembled vehicle
scene, where both the cockpit and mech nodes exist:

```gdscript
func _ready() -> void:
    sensor_head.panoramic_screen = cockpit.panoramic_screen  # give SensorHead the sphere ref
    cockpit.panoramic_screen.sensor_head = sensor_head       # give PanoramicScreen the texture source
    sensor_head.viewer_camera = viewer_camera                # connect the player camera
```

`cockpit.panoramic_screen` is an `@export var panoramic_screen: PanoramicScreen` on `CockpitRX0`,
assigned in the Inspector to `NodePath("MeshInstance3D/PanoramicScreen")`. Because `CockpitRX0`
is a subscene instanced in the vehicle scene, the controller can reach the screen node through
the typed export without needing to know its full path.

---

## Placement Tips

- Place `PanoramicScreen` at **pilot eye level**, centred on the seat. The sphere should enclose
  the camera with comfortable clearance on all sides — the pilot should not be able to see the
  near-clip plane of their camera intersect the sphere.
- In the editor the sphere shows as semi-transparent blue. Toggle visibility of the
  `MeshInstance3D` parent (which holds the placeholder mesh) to see through it.
- The `PanoramicScreen` node itself has no material in the editor — only its `$ScreenMesh` child
  has the shader applied at runtime. The placeholder blue sphere is on the separate
  `MeshInstance3D` parent node in the cockpit scene.
- At runtime `_mesh_instance.layers` is set to `COCKPIT | VEHICLE_EXT`. In the editor the mesh
  has no layer restriction, so it appears in all viewport shading modes.
