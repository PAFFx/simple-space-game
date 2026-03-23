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
2. Computes the exact sensor FOV needed using frustum-sphere geometry
3. Resizes the viewport proportionally to maintain constant pixels-per-degree quality

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
@export var pixels_per_degree: float = 32.0
```
Target render quality. The viewport size is set to `pixels_per_degree × computed_fov` each
frame (clamped). Higher values = sharper image, larger texture, more GPU memory and fill-rate.
Common values: 16 (performance), 32 (quality), 48 (ultra).

```gdscript
@export var fov_safety_margin_degrees: float = 8.0
```
Degrees added to the geometry-computed FOV. Covers the 1-frame lag between viewer rotation
and viewport update, and floating-point imprecision at sphere edges. 5–10° is a good range.

```gdscript
@export var min_viewport_size: int = 256
@export var max_viewport_size: int = 4096
```
Hard floor and ceiling for the SubViewport dimension. `min` prevents zero-size on pathological
camera angles. `max` prevents out-of-memory on very wide FOVs.

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
head, above the cockpit), viewer frustum corners that are at ±30° from forward can hit the sphere
at points whose panoramic direction (from sphere centre) is ±60° from forward. The sensor must
cover ±60°, not ±30°.

A static margin cannot account for this — the actual overshoot depends on the viewer's FOV,
the sphere radius, and the sensor-to-sphere-centre distance.

### The geometric solution

For each of 5 frustum sample points (centre + 4 corners), cast a ray from the viewer through the
sphere. For each hit point `P`:

```
panoramic_dir = normalize(P - sphere_centre)
```

`panoramic_dir` is the world direction that the shader will actually sample for that screen
fragment. This equals `sensor_basis * local_dir(UV2)` for that vertex.

The sensor camera (aimed in `world_look = -viewer_basis.z`) must cover `panoramic_dir` within
its FOV. So:

```
half_angle = acos(dot(panoramic_dir, world_look))
required_fov = 2 × max(half_angle across all hits) + safety_margin
```

### Why aim in `world_look`, not toward the sphere hit?

The shader samples directions of the form `sensor_world_pos + world_dir * 500`, where `world_dir`
comes from UV2 panoramic encoding. These directions are centred around the viewer's look direction.
Pointing the sensor camera toward the **physical sphere hit location** instead would aim it off to
the side of `world_look`, causing all fragments near `world_look` to fall outside the sensor FOV.

```gdscript
# Correct: sensor tracks viewer look direction
var world_look := -viewer_basis.z
_camera.transform = Transform3D(Basis.looking_at(world_look, up), sensor_pos)

# Wrong: aims toward sphere surface geometry (breaks shader sampling)
# center_dir = (hit - sensor_pos).normalized()  ← DO NOT USE
```

### Code

```gdscript
func _update_camera() -> void:
    var world_look := -viewer_basis.z
    _camera.transform = Transform3D(Basis.looking_at(world_look, up), sensor_pos)

    # Sample 5 frustum points: centre + 4 corners
    for idx in range(sample_pixels.size()):
        var ray_dir := viewer_camera.project_ray_normal(sample_pixels[idx])
        var t := _ray_sphere_intersect(viewer_pos, ray_dir, sphere_center, sphere_radius)
        if t < 0.0:
            continue
        var panoramic_dir := (viewer_pos + ray_dir * t - sphere_center).normalized()
        var angle := acos(clampf(panoramic_dir.dot(world_look), -1.0, 1.0))
        max_half_angle = maxf(max_half_angle, angle)

    required_fov = rad_to_deg(max_half_angle) * 2.0 + fov_safety_margin_degrees
    _camera.fov = clampf(required_fov, 10.0, 160.0)
```

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

## Dynamic Viewport Sizing

```gdscript
var new_size := int(clampf(pixels_per_degree * required_fov, min_viewport_size, max_viewport_size))
if absf(float(new_size - _viewport.size.x)) > float(_viewport.size.x) * 0.1:
    _viewport.size = Vector2i(new_size, new_size)
```

The **10% hysteresis** prevents per-frame viewport reallocation. SubViewport resize is expensive:
it deallocates and reallocates the GPU render target. Small continuous FOV changes (camera sway,
head bob) would otherwise trigger this every frame. With 10% hysteresis, the size changes in
discrete steps, producing at most ~23 size levels between `min` and `max`.

Square viewport (`x == y`) avoids aspect-ratio bias. A 16:9 viewport would give more pixels/degree
horizontally than vertically, causing vertical seams at a lower angular separation.

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
    _camera.transform = Transform3D(Basis.looking_at(world_look, up), global_position)
    _camera.fov = clampf(viewer_camera.fov + 90.0, 10.0, 160.0)
```

Static 90° margin, same as the original implementation. This is a wide-but-functional fallback —
the image will be blurrier and may have edge seams, but the system remains usable while
`panoramic_screen` is being set up.
