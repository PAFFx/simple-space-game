# SensorHead

**File:** `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/sensor_head.gd`
**Scene:** `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/sensor_head.tscn`
**Class:** `SensorHead extends Node3D`
**Helpers:** `SensorFovSolver` (Helper/), `SpatialMath` (Common/Calculations/)

---

## Purpose

`SensorHead` is the sensor camera manager. It owns a `SubViewport` and a `Camera3D` that render
the world from the mech's head pivot, producing the texture that `PanoramicScreen` uses to fill
the cockpit display.

Every frame it:
1. Aims the sensor camera in the viewer's look direction
2. Delegates to `SensorFovSolver.solve_required_fov()` which casts 9 frustum rays through the
   screen sphere and decomposes hits into separate horizontal and vertical angular spans
3. Delegates to `SensorFovSolver.compute_viewport_size()` to size a rectangular viewport to
   exactly match the required H/V coverage at the target display quality — no wasted pixels

---

## Auto-Discovery

Dependencies are found automatically in `_ready()` via `_auto_discover()`:

```gdscript
func _auto_discover() -> void:
    if viewer_camera != null and panoramic_screen != null:
        return  # manual overrides — skip
    var vehicle := VehicleBase.find_vehicle(self)   # walks up to MobileSuitRX0
    var cockpit := vehicle.get_cockpit()            # finds CockpitRX0 under CockpitMount
    if viewer_camera == null:
        viewer_camera = cockpit.get_player_camera()
    if panoramic_screen == null:
        panoramic_screen = cockpit.get_panoramic_screen()
```

No scene-level wiring or exported node paths are needed when `SensorHead` is placed under
`SensorHeadMount` inside a `VehicleBase` scene that also contains a `CockpitBase` child.

---

## Exports

```gdscript
@export var viewer_camera: Camera3D
```
The active player camera. Its `global_transform` is read each frame to track look direction.
**Auto-discovered** from `cockpit.get_player_camera()` if left empty. Can be set manually in the
Inspector for standalone testing or to swap to a cutscene camera at runtime.

```gdscript
@export var panoramic_screen: PanoramicScreen
```
Reference to the screen sphere. Used to get `global_position` and `screen_radius` for the
FOV geometry computation. **Auto-discovered** from `cockpit.get_panoramic_screen()` if left empty.
Falls back to the static 90° margin path when null.

```gdscript
@export var quality_scale: float = 1.0
```
Render quality relative to the player's actual display resolution. The `pixels_per_degree`
value is computed automatically each frame by `SensorFovSolver.compute_viewport_size()` as:
```
ppd = (display_height_px / viewer_vfov_degrees) × quality_scale
```
This means `quality_scale = 1.0` always produces exactly 1 sensor pixel per display pixel
on the vertical axis, regardless of whether the player is on 1080p, 2K, or 4K.

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

FOV computation is delegated to `SensorFovSolver.solve_required_fov()`. The full algorithm
and mathematical explanation lives in that helper class. Summary:

### The problem with `viewer_fov + static_margin`

When the viewer is **inside** the sphere and the sensor is **outside** (positioned at the mech
head, above the cockpit), viewer frustum corners at ±30° from forward can hit the sphere at points
whose panoramic direction (from sphere centre) is ±60° from forward. The sensor must cover ±60°,
not ±30°. A static margin cannot account for this — the actual overshoot depends on the viewer's
FOV, the sphere radius, and the sensor-to-sphere-centre distance.

### The geometric solution

For each of 9 frustum sample points, cast a ray from the viewer through the sphere via
`SpatialMath.ray_sphere_intersect()`. For each hit point `P`, the panoramic direction is:

```
panoramic_dir = normalize(P - sphere_centre)
```

Decompose it into the sensor camera's local horizontal and vertical planes to get separate
H/V half-angles. The maximum across all 9 points gives the required H/V FOV.

### Why separate H/V FOV?

A square viewport wastes ~44% of the vertical pixels for a typical 16:9 display. Separate H/V fixes this:

- **Vertical FOV** drives `Camera3D.fov` (Godot's `fov` is always vertical with `KEEP_HEIGHT`)
- **Horizontal FOV** drives the viewport width via the perspective aspect ratio formula
- The camera derives its horizontal FOV automatically from the viewport aspect ratio

---

## Dynamic Viewport Sizing

Delegated to `SensorFovSolver.compute_viewport_size()`:

```gdscript
var display_h := viewer_camera.get_viewport().get_visible_rect().size.y
var ppd       := (display_h / viewer_camera.fov) * quality_scale

var new_vpx := int(clampf(ppd * required_vfov, min_viewport_size, max_viewport_size))
var aspect  := tan(deg_to_rad(required_hfov * 0.5)) / tan(deg_to_rad(required_vfov * 0.5))
var new_hpx := int(clampf(float(new_vpx) * aspect, min_viewport_size, max_viewport_size))
```

**Why `tan(hfov/2) / tan(vfov/2)` and not `hfov / vfov`?**
Perspective FOV is nonlinear. At large FOVs (e.g. 150° H vs 110° V) the linear ratio gives
the wrong pixel count. The tangent form is the exact relationship between angular field of view
and physical sensor dimensions in a pinhole camera model.

**10% hysteresis** on both dimensions prevents per-frame GPU texture reallocation.

---

## Angular Amplification Asymmetry

Due to the viewer being offset **above** the sphere centre (0.34m in the RX-0 scene), the
required sensor FOV is asymmetric depending on look direction:

```
Distance to TOP wall    = sphere_radius - viewer_offset = 1.2 - 0.34 = 0.86m
Distance to BOTTOM wall = sphere_radius + viewer_offset = 1.2 + 0.34 = 1.54m
```

**Near wall (looking up):** deamplification — sensor FOV can be *smaller* than player FOV.
**Far wall (looking down):** amplification — sensor FOV is notably larger than player FOV.

For a 75° player VFOV and a 37.5° corner ray:

| Look direction | Wall distance | Panoramic angle | Sensor VFOV needed |
|----------------|--------------|-----------------|-------------------|
| Straight up | 0.86m | ~27.5° | ~63° |
| Forward | ~1.15m | ~41° | ~90° |
| Straight down | 1.54m | ~47° | ~102° |

**Mitigation:** centre `PanoramicScreen` at the viewer's eye position to minimise the offset.

---

## Ray-Sphere Intersection

Delegated to `SpatialMath.ray_sphere_intersect()`. Uses the half-b form of the quadratic
(cleaner when `a = 1` for unit rays):

```
d    = ray_origin - sphere_centre
b    = dot(d, ray_dir)
c    = dot(d, d) - r²
disc = b² - c
```

- `disc < 0` → ray misses sphere → return -1
- `t0 = -b - sqrt(disc)`, `t1 = -b + sqrt(disc)`
- Return the smallest positive t (nearest intersection in front of the ray)

When the viewer is inside the sphere, `c < 0` so `disc > b²`, guaranteeing `t0 < 0` and `t1 > 0`.
The function returns `t1` — the hit on the sphere wall in front of the viewer.

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

```gdscript
sensor_head.set_group_visible(Layers.SENSOR_BODY_PARTS, true)   # show mech body on screen
sensor_head.set_group_visible(Layers.SENSOR_WEAPONS,    false)  # hide weapons (stealth mode)
```

The sensor camera starts with `cull_mask = Layers.WORLD | Layers.FX`.

---

## Fallback Mode

When `panoramic_screen` is null (standalone testing, or auto-discovery failed):

```gdscript
func _update_camera_fallback() -> void:
    _camera.fov = clampf(viewer_camera.fov + 90.0, 10.0, 160.0)
    # Viewport sized at display resolution × quality_scale, display aspect ratio
```

Static 90° margin, same as the original implementation. Still rectangular and
display-resolution-aware — only degradation vs. the full path is the imprecise FOV.

---

## Debug Logging

Uncomment `_debug_log(...)` in `_update_camera()` to enable. Logs only when H FOV, V FOV, or
viewport size changes by more than 1°/1px — no per-frame spam. Output format:

```
[SensorHead] sensor H=156.2° V=102.4°  player_fov=75.0°  viewport=1639x921 (1.78)  ppd=14.4
```
