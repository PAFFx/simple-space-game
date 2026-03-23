# SensorHead

**File:** `Common/PanoramicDisplay/sensor_head.gd`
**Scene:** `Common/PanoramicDisplay/sensor_head.tscn`
**Class:** `SensorHead extends Node3D`

---

## Purpose

`SensorHead` is the sensor camera manager. It owns a `SubViewport` and a `Camera3D` that render
the world from the mech's head pivot, producing the texture that `PanoramicScreen` uses to fill
the cockpit display.

Every frame it:
1. Aims the sensor camera in the viewer's look direction
2. Casts 9 frustum rays through the screen sphere and decomposes hits into separate horizontal
   and vertical angular spans
3. Sets a rectangular viewport sized to exactly match the required H/V coverage at the target
   display quality — no wasted pixels on either axis

---

## Exports

```gdscript
@export var viewer_camera: Camera3D
```
The active player camera. Its `global_transform` is read each frame to track look direction.
Set automatically by `CockpitDisplayController._ready()`, but can also be assigned in the
Inspector or swapped at runtime for cutscene cameras.

```gdscript
@export var panoramic_screen: PanoramicScreen
```
Reference to the screen sphere. Used to get `global_position` and `screen_radius` for the
FOV geometry computation. Set by `CockpitDisplayController._ready()`. If null, falls back
to the static 90° margin path.

```gdscript
@export var quality_scale: float = 1.0
```
Render quality relative to the player's actual display resolution. The `pixels_per_degree`
value is computed automatically each frame as:
```
ppd = (display_height_px / viewer_vfov_degrees) × quality_scale
```
This means `quality_scale = 1.0` always produces exactly 1 sensor pixel per display pixel
on the vertical axis, regardless of whether the player is on 1080p, 2K, or 4K. Users never
need to manually calculate pixels-per-degree.

| `quality_scale` | Meaning |
|----------------|---------|
| 0.5 | Half display resolution — cheaper, visibly blurry |
| 1.0 | Matches display resolution — good default |
| 1.5 | 1.5× super-sampled — noticeably sharper |
| 2.0 | 2× super-sampled — maximum quality, expensive |

```gdscript
@export var fov_safety_margin_degrees: float = 2.0
```
Degrees added to the geometry-computed FOV on each axis. Covers the 1-frame lag between
viewer rotation and viewport update, and floating-point imprecision at sphere edges. 2–8°
is a good range; lower values give tighter viewports with a small risk of 1-frame edge seams
during fast head movement.

```gdscript
@export var min_viewport_size: int = 256
@export var max_viewport_size: int = 4096
```
Hard floor and ceiling for each viewport dimension independently. `min` prevents zero-size
on pathological camera angles. `max` caps GPU memory use at extreme FOVs.

---

## Internal Nodes

Both nodes are created dynamically in `_ready()` — they do not exist in `sensor_head.tscn`.

```gdscript
var _viewport: SubViewport   # own_world_3d = false, UPDATE_ALWAYS
var _camera:   Camera3D      # child of _viewport, cull_mask = WORLD | FX
```

### Why create them in code, not in the scene?

SubViewport's `own_world_3d` must be `false` so it shares the main scene's `World3D`. If the
node were placed in the scene file by hand, editors sometimes reset this property on reimport.
Creating it in code guarantees the correct configuration regardless of how the scene is opened.

---

## The SubViewport Position Trick

`SubViewport` is a `Node`, not `Node3D`. It has no spatial transform. The renderer skips it
entirely when resolving the camera's world-space transform — using the camera's **local**
transform directly as its world-space transform.

**Consequence:** setting `_camera.global_transform` routes through `SensorHead`'s own spatial
hierarchy (SensorHead → SubViewport is a non-spatial parent → result is unpredictable). Setting
`_camera.transform` (the local property) works correctly because local == world in this context.

```gdscript
# Always use .transform, never .global_transform for the sensor camera
_camera.transform = Transform3D(basis, global_position)
```

The same applies to the data accessors:
```gdscript
func get_world_pos() -> Vector3:
    return _camera.transform.origin          # NOT _camera.global_position

func get_view_proj() -> Projection:
    var view := _camera.transform.affine_inverse()   # NOT get_camera_transform()
    return _camera.get_camera_projection() * Projection(view)
```

---

## Dynamic FOV Computation

### The problem with `viewer_fov + static_margin`

The sensor camera renders a perspective image that the shader reprojects onto the sphere. For the
reprojection to work without seams, the sensor camera must be able to "see" every world direction
that any visible screen fragment points to.

When the viewer is **inside** the sphere and the sensor is **outside** (positioned at the mech
head, above the cockpit), viewer frustum corners at ±30° from forward can hit the sphere at points
whose panoramic direction (from sphere centre) is ±60° from forward. The sensor must cover ±60°,
not ±30°. A static margin cannot account for this — the actual overshoot depends on the viewer's
FOV, the sphere radius, and the sensor-to-sphere-centre distance.

### The geometric solution

For each of 9 frustum sample points, cast a ray from the viewer through the sphere. For each hit
point `P`, the panoramic direction is:

```
panoramic_dir = normalize(P - sphere_centre)
```

This is the world direction the shader will sample for that screen fragment. Decompose it into
the sensor camera's local horizontal and vertical planes to get separate H/V half-angles.

### Why separate H/V FOV?

A square viewport was previously used with a single FOV value, making H pixels == V pixels. For
a typical 16:9 display, the viewer's horizontal frustum spans ~1.78× more angular width than
vertical. Rendering a square sensor viewport wastes ~44% of the vertical pixels while
underallocating horizontal pixels. Separate H/V fixes this:

- **Vertical FOV** drives `Camera3D.fov` (Godot's `fov` is always vertical with the default
  `keep_aspect = KEEP_HEIGHT`)
- **Horizontal FOV** drives the viewport width via the perspective aspect ratio formula
- The camera derives its horizontal FOV automatically from the viewport aspect ratio

### Decomposing panoramic directions into H/V angles

After building the sensor camera's basis, extract its local right and up axes:

```gdscript
var cam_basis := _camera.transform.basis
var cam_right := cam_basis.x   # camera local +X (rightward)
var cam_up    := cam_basis.y   # camera local +Y (upward)
```

For each sphere hit, project the panoramic direction against these axes:

```gdscript
var d_fwd   := panoramic_dir.dot(world_look)              # depth component
var h_angle: float = abs(atan2(panoramic_dir.dot(cam_right), d_fwd))
var v_angle: float = abs(atan2(panoramic_dir.dot(cam_up),    d_fwd))
```

`atan2(lateral, forward)` gives the true perspective angle in each plane — the same formula
a pinhole camera uses to map a 3D point to a 2D sensor coordinate.

### Why aim in `world_look`, not toward the sphere hit?

The shader samples directions of the form `sensor_world_pos + world_dir * 500`, where `world_dir`
comes from UV2 panoramic encoding. These directions are centred around the viewer's look direction.
Pointing the sensor camera toward the **physical sphere hit location** instead would aim it off to
the side of `world_look`, causing all fragments near `world_look` to fall outside the sensor FOV.

```gdscript
# Correct: sensor tracks viewer look direction
_camera.transform = Transform3D(Basis.looking_at(world_look, up), sensor_pos)

# Wrong: aims toward sphere surface geometry (breaks shader sampling)
# center_dir = (hit - sensor_pos).normalized()  ← DO NOT USE
```

### The 9 sample points

```gdscript
var sample_pixels: Array[Vector2] = [
    vp_size * 0.5,                              # centre
    Vector2(0.0,       0.0),                    # top-left     (corner)
    Vector2(vp_size.x, 0.0),                    # top-right    (corner)
    Vector2(0.0,       vp_size.y),              # bottom-left  (corner)
    vp_size,                                     # bottom-right (corner)
    Vector2(vp_size.x * 0.5, 0.0),             # top-centre   (pure V)
    Vector2(vp_size.x * 0.5, vp_size.y),       # bottom-centre(pure V)
    Vector2(0.0,       vp_size.y * 0.5),        # left-centre  (pure H)
    Vector2(vp_size.x, vp_size.y * 0.5),       # right-centre (pure H)
]
```

Corners capture the diagonal worst-case (both H and V at maximum simultaneously). Edge midpoints
isolate each axis cleanly so that a pure horizontal or vertical extreme is never missed.

---

## Dynamic Viewport Sizing

```gdscript
# pixels_per_degree derived from actual display resolution and viewer FOV
var display_h := viewer_camera.get_viewport().get_visible_rect().size.y
var ppd       := (display_h / viewer_camera.fov) * quality_scale

# Vertical pixels from V FOV
var new_vpx := int(clampf(ppd * required_vfov, min_viewport_size, max_viewport_size))

# Horizontal pixels from true perspective aspect ratio
# tan(hfov/2) / tan(vfov/2) is exact; hfov/vfov would be wrong at large angles
var aspect  := tan(deg_to_rad(required_hfov * 0.5)) / tan(deg_to_rad(required_vfov * 0.5))
var new_hpx := int(clampf(float(new_vpx) * aspect, min_viewport_size, max_viewport_size))

_viewport.size = Vector2i(new_hpx, new_vpx)
```

**Why `tan(hfov/2) / tan(vfov/2)` and not `hfov / vfov`?**
Perspective FOV is nonlinear. At large FOVs (e.g. 150° H vs 110° V) the linear ratio gives
the wrong pixel count. The tangent form is the exact relationship between angular field of view
and physical sensor dimensions in a pinhole camera model.

**10% hysteresis** on both dimensions prevents per-frame GPU texture reallocation. SubViewport
resize is expensive — it deallocates and reallocates the render target. Small continuous FOV
changes (head bob, smooth panning) would otherwise trigger this every frame.

---

## Angular Amplification Asymmetry

Due to the viewer being offset **above** the sphere centre (0.34m in the RX-0 scene), the
required sensor FOV is asymmetric depending on look direction:

```
Distance to TOP wall    = sphere_radius - viewer_offset = 1.2 - 0.34 = 0.86m
Distance to BOTTOM wall = sphere_radius + viewer_offset = 1.2 + 0.34 = 1.54m
```

**Near wall (looking up):** frustum corners hit the sphere close to the viewer. The panoramic
directions of those hit points are relatively close to the viewer's look direction →
**deamplification** — sensor FOV can be *smaller* than player FOV.

**Far wall (looking down):** corners travel further before hitting the sphere. Hit points are
displaced more from the sphere centre axis → **amplification** — sensor FOV is notably larger
than player FOV.

For a 75° player VFOV and a 37.5° corner ray:

| Look direction | Wall distance | Corner ray | Panoramic angle | Sensor VFOV needed |
|----------------|--------------|------------|-----------------|-------------------|
| Straight up | 0.86m | 37.5° | ~27.5° | ~63° |
| Forward | ~1.15m | 37.5° | ~41° | ~90° |
| Straight down | 1.54m | 37.5° | ~47° | ~102° |

This asymmetry is physically correct and unavoidable — it is the geometric consequence of the
sensor and viewer being at different positions relative to the sphere. The 9-point separate H/V
computation handles it correctly per-axis per-frame.

**Mitigation:** centering `PanoramicScreen` at the viewer's eye position (not the cockpit
geometric centre) minimises the offset from sphere centre, reducing amplification across all
directions and making the viewport size more uniform.

---

## Ray-Sphere Intersection

Uses the half-b form of the quadratic (cleaner when `a = 1` for unit rays):

```
d    = ray_origin - sphere_centre
b    = dot(d, ray_dir)            ← half-b in standard form
c    = dot(d, d) - r²
disc = b² - c
```

- `disc < 0` → ray misses sphere → return -1
- `t0 = -b - sqrt(disc)`, `t1 = -b + sqrt(disc)`
- Return the smallest positive t (nearest intersection in front of the ray)

**Inside vs outside the sphere:**

When the viewer is inside the sphere, `c < 0` so `disc > b²`. This guarantees `t0 < 0`
and `t1 > 0` — the function returns `t1`, the hit on the sphere wall in front of the viewer.
When the viewer is outside, `t0 > 0` is the near (outer surface) hit, returned first.

```gdscript
func _ray_sphere_intersect(ray_origin, ray_dir, sphere_center, sphere_radius) -> float:
    var d    := ray_origin - sphere_center
    var b    := d.dot(ray_dir)
    var c    := d.dot(d) - sphere_radius * sphere_radius
    var disc := b * b - c
    if disc < 0.0: return -1.0
    var sq := sqrt(disc)
    var t0 := -b - sq
    var t1 := -b + sq
    if t0 > 0.001: return t0
    if t1 > 0.001: return t1
    return -1.0
```

---

## Performance

### Two render passes

Every frame there are two full Forward+ render passes:

1. **Sensor pass** — SubViewport's Camera3D renders the world into a rectangular texture
2. **Main pass** — player camera renders the scene; the panoramic sphere shader samples the texture

The sensor pass is the expensive one. The reprojection shader in the main pass is cheap (a few
ALU ops + one texture fetch per fragment).

### Sensor pass cost factors

- **Viewport size:** scales quadratically. At `quality_scale = 1.0` on 1080p with 75° VFOV and
  ~100° sensor VFOV, the viewport is roughly `1440 × 810` (about 1.16 MP) — much cheaper than
  the old square 2048×2048 (4.2 MP).
- **Shadow maps:** Godot re-evaluates shadow cascades for the sensor camera. For a space scene
  this is manageable. Disabling shadow casting on the sensor camera's `Environment` saves 30–50%.
- **Post-processing:** SSAO, glow, SSIL run per-viewport. Disabling them on the sensor viewport
  (the feed doesn't need screen-space effects) gives further savings.
- **Geometry:** `cull_mask = WORLD | FX` excludes the cockpit interior — the most overdraw-heavy
  part — from the sensor render.

### Comparison to single-pass "move cockpit to head"

Many mech games (Armored Core series) avoid a second render pass entirely by parenting the cockpit
mesh to the mech's head bone. The player camera lives inside that cockpit at the sensor location,
so the player literally sees through the cockpit window. This is **1 render pass, zero shader
overhead**.

| | Move-cockpit-to-head | Spherical reprojection |
|---|---|---|
| Render passes | 1 | 2 |
| Shader overhead | None | Low (fillrate only) |
| First-person correctness | ✓ (pilot IS at sensor) | ✓ |
| Third-person screen visibility | ✗ (cockpit is at head) | ✓ |
| Cockpit ≠ head (Gundam chest) | ✗ | ✓ |
| Parallax between pilot and sensor | None | Correct |

The single-pass trick only works when the cockpit is physically at the head. For the RX-0 — chest
cockpit, sensor in the head, screen visible from outside through open hatch — it doesn't apply.

### Tips for reducing cost

1. **Disable sensor post-processing.** Attach a minimal `Environment` to the sensor camera with
   SSAO, glow, and DOF disabled.
2. **Lower `quality_scale`** to 0.75 — still very sharp in practice, ~44% fewer pixels than 1.0.
3. **Switch to `UPDATE_ONCE`** when the mech is stationary and the player isn't moving their head.
   Flip back to `UPDATE_ALWAYS` on significant camera movement.
4. **Reduce `max_viewport_size`** to 2048 — still 4× 1080p density, visually indistinguishable
   from 4096 at typical viewing distances.

---

## Debug Logging

```gdscript
_debug_log(required_hfov, required_vfov, Vector2i(new_hpx, new_vpx), ppd)
```

Logs only when H FOV, V FOV, or viewport size changes by more than 1°/1px — no per-frame spam.
Output format:
```
[SensorHead] sensor H=156.2° V=102.4°  player_fov=75.0°  viewport=1639x921 (1.78)  ppd=14.4
```

- `H` and `V` show sensor FOV per axis — `H > V` is expected for a 16:9 display
- `1.78` aspect ratio confirms the viewport matches the viewer's display ratio
- `ppd` is the actual pixels-per-degree achieved — at `quality_scale=1.0` on 1080p this should
  closely match `1080 / player_fov`

---

## `get_sensor_basis()` — The Fixed Orientation Rule

```gdscript
func get_sensor_basis() -> Basis:
    return global_transform.basis   # SensorHead's OWN orientation
```

This returns `SensorHead`'s fixed world orientation, **not** the sensor camera's current
tracking rotation.

**Why this matters:** The shader computes `world_dir = sensor_basis * local_dir`. The view matrix
of the sensor camera applies the inverse of the camera's rotation R: `clip = R⁻¹ * world_dir`.
If `sensor_basis = R` (camera's rotating basis), then `clip = R⁻¹ * R * local_dir = local_dir`,
a constant. The screen would never move — the rotation cancels itself out.

With `sensor_basis = SensorHead.global_transform.basis` (fixed), the cancellation does not happen
and the screen correctly shows the world in the direction the mech is facing.

---

## Occlusion Toggle Interface

```gdscript
func set_group_visible(layer_bit: int, visible: bool) -> void:
    if visible: _camera.cull_mask |= layer_bit
    else:       _camera.cull_mask &= ~layer_bit
```

Adds or removes a bit from the sensor camera's `cull_mask` without affecting any other camera.

**Usage after assigning sensor sub-layers to mesh nodes:**
```gdscript
sensor_head.set_group_visible(Layers.SENSOR_BODY_PARTS, true)   # show mech body on screen
sensor_head.set_group_visible(Layers.SENSOR_WEAPONS,    false)  # hide weapons (stealth mode)
```

The sensor camera starts with `cull_mask = Layers.WORLD | Layers.FX` — it sees the world
environment but not the mech body. This default prevents the mech from obscuring the sensor
view through its own torso while individual body parts have not yet been assigned sub-layers.

---

## Fallback Mode

When `panoramic_screen` is null (not yet wired, or during testing):

```gdscript
func _update_camera_fallback() -> void:
    _camera.fov = clampf(viewer_camera.fov + 90.0, 10.0, 160.0)
    # Viewport sized at display resolution × quality_scale, display aspect ratio
    var vpx := int(clampf(ppd * vfov, min_viewport_size, max_viewport_size))
    var hpx := int(clampf(vpx * (display_width / display_height), ...))
    _viewport.size = Vector2i(hpx, vpx)
```

Static 90° margin, same as the original implementation. The viewport is still rectangular and
display-resolution-aware — the only degradation vs the full path is the imprecise FOV.
