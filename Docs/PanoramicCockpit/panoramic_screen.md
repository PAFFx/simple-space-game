# PanoramicScreen

**Script:** `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/panoramic_screen.gd`
**Shader:** `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/Shader/panoramic_screen.gdshader`
**Scene:** `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/panoramic_screen.tscn`
**Class:** `PanoramicScreen extends Node3D`
**Mesh helper:** `PanoramicMeshBuilder` (Mesh/)

---

## Purpose

`PanoramicScreen` owns the spherical mesh that forms the cockpit display surface. It:

1. Delegates sphere geometry generation to `PanoramicMeshBuilder.build()`
2. Assigns a `ShaderMaterial` that reprojects panoramic directions through the sensor camera
3. Pushes updated sensor uniforms to the shader every frame
4. Manages a 1D segment mask texture for per-arc-segment damage / door-open effects

The script is `@tool` — the mesh rebuilds live in the editor when any geometry export is changed,
and shows a semi-transparent blue placeholder so the sphere is visible during placement.

---

## Auto-Discovery

`sensor_head` is found automatically in `_ready()` via `_auto_discover()`:

```gdscript
func _auto_discover() -> void:
    if sensor_head != null:
        return  # manual override — skip
    var vehicle := VehicleBase.find_vehicle(self)   # walks up to MobileSuitRX0
    sensor_head = vehicle.get_sensor_head()         # finds SensorHead under SensorHeadMount
```

No scene-level wiring or exported node paths are needed when `PanoramicScreen` is placed under
`PanoramicDisplayMount` inside a `CockpitBase` that lives inside a `VehicleBase`.

The `@export var sensor_head: SensorHead` remains as an optional manual override for testing
outside a full vehicle hierarchy.

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

All geometry exports have setters that call `_rebuild_in_editor()`, which calls
`PanoramicMeshBuilder.build()` again so the mesh updates immediately in the Inspector
without running the scene.

**`arc_angle`** — How much of the 360° circle the screen covers.
- `TAU` (6.283): full 360° panoramic — the sphere completely encloses the pilot.
- `PI` (3.14): 180° semicircle — only the forward half.

**`elevation_range`** — How tall the screen is (vertical span).
- `PI` (3.14): full ±90°, top-to-bottom hemisphere. Most common default.
- `PI / 2` (1.57): ±45°, a narrower band around the equator.
- The shader reads this as `panoramic_elevation_range` to recover the elevation angle from UV2.

**`screen_radius`** — The sphere radius in world units. Should be large enough that the pilot
camera sits comfortably inside. 1.2 m works for a human-scale cockpit.

### Mask

```gdscript
@export var segment_count: int = 64
```

The number of independently togglable horizontal segments in the damage/door mask. Each segment
spans `arc_angle / segment_count` radians. Higher values = finer damage granularity.

---

## The UV2 Panoramic Encoding

Every vertex has two UV channels:

- **UV0** (`ARRAY_TEX_UV`): standard spherical wrap `(t_arc, 1 - t_elev)`. Reserved for optional
  cockpit-detail overlays that future shaders may sample.

- **UV2** (`ARRAY_TEX_UV2`): panoramic direction encoding used by the reprojection shader.
  ```
  UV2.x = azimuth / TAU      ← normalised absolute azimuth (may be outside [0,1] if arc_offset ≠ 0)
  UV2.y = t_elev             ← elevation normalised to [0, 1] (0 = bottom, 1 = top)
  ```

Using **absolute** azimuth (not the arc-relative `t_arc`) is intentional:
- A vertex at azimuth = 2.5 rad has UV2.x ≈ 0.398 regardless of `arc_offset`.
- The shader uses `fract(UV2.x)` to sample the segment mask, correctly wrapping any offset.
- The shader uses `UV2.x * TAU` to recover the absolute azimuth for direction math.

### Vertex formula (implemented in `PanoramicMeshBuilder.build()`)

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

### Inward normals

```gdscript
normal = Vector3(-sin(azimuth) * cos_el, -sin(elevation), cos(azimuth) * cos_el)
```

Normals point **toward the sphere's centre** (inward). With `cull_back` in the shader, the
surface is visible when the camera is inside the sphere, and culled when outside.

---

## Render Layers

```gdscript
_mesh_instance.layers = Layers.COCKPIT | Layers.VEHICLE_EXT
```

- **`COCKPIT`** — Visible to the first-person camera.
- **`VEHICLE_EXT`** — Visible to the third-person camera.
- **Not `MASK_SENSOR`** — The sensor camera deliberately cannot see the screen mesh. If it could,
  the screen would appear inside its own sensor feed, creating an infinite loop of reprojection.

---

## Segment Mask API

The segment mask is a `segment_count × 1` `Image.FORMAT_R8` texture. It maps to the screen's
azimuth: pixel index `i` covers the arc segment `[i/segment_count, (i+1)/segment_count]` of
the full 0..TAU range.

```gdscript
func set_segment_enabled(index: int, enabled: bool) -> void
```
Toggle a single segment by index (0-based from `arc_offset`).

```gdscript
func set_arc_range_enabled(start_rad: float, end_rad: float, enabled: bool) -> void
```
Toggle all segments whose centre falls in `[start_rad, end_rad]`. Handles wraparound.

```gdscript
func enable_all_segments() -> void
func disable_all_segments() -> void
```
Bulk operations using `_mask_image.fill()`.

**Example — Simulate open cockpit door on the right side:**
```gdscript
panoramic_screen.set_arc_range_enabled(PI * 0.25, PI * 0.75, false)
```

---

## Editor `@tool` Behaviour

With `@tool`, `_ready()` runs in the editor. When `Engine.is_editor_hint()` is true:
- `PanoramicMeshBuilder.build()` is called — the sphere shape is visible in the editor.
- A semi-transparent blue `StandardMaterial3D` is applied as `material_override`.
- `_auto_discover()` and `_setup_material()` are **not** called — no shader, no texture refs.
- The function returns early.

When any geometry export is changed via the Inspector, `_rebuild_in_editor()` calls
`PanoramicMeshBuilder.build()` again for a live update.

---

## Placement Tips

- Place `PanoramicDisplayMount` (the Marker3D parent) at **pilot eye level**, centred on the seat.
  The sphere should enclose the camera with comfortable clearance on all sides.
- In the editor the sphere shows as semi-transparent blue. You can toggle its visibility to see
  through it while positioning.
- The `PanoramicScreen` node itself has no material in the editor — only its `$ScreenMesh` child
  has the shader applied at runtime.
- At runtime `_mesh_instance.layers` is set to `COCKPIT | VEHICLE_EXT`. In the editor the mesh
  has no layer restriction, so it appears in all viewport shading modes.
