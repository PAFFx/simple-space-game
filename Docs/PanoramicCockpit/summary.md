# Panoramic Cockpit Display — System Summary

## The Problem

The RX-0 cockpit needs a 360° panoramic display screen that shows the world as seen from the
mech's head sensor. Two hard constraints make this unusual:

1. **Visible from both sides.** The screen must be visible from inside the cockpit (first-person
   pilot view) AND from outside when the cockpit hatch is open (third-person camera looking in).
   This rules out render-through / stencil tricks, which only work from one side.

2. **Single renderer.** A full cubemap (6 cameras) is too expensive. We want one render pass.

---

## The Core Illusion

The solution is a **projection reprojection trick**:

```
Sensor camera (head pivot)
  │  renders a single viewport looking in the viewer's direction
  │
  ▼
SubViewport texture
  │  passed as a uniform to the panoramic screen shader
  │
  ▼
Spherical screen mesh (inside cockpit)
  each fragment: UV2 → panoramic direction → project through sensor camera → sample viewport
```

A spherical mesh surrounds the pilot. Each vertex has UV2 coordinates that encode a **world
direction** (azimuth + elevation). The fragment shader takes that direction, projects it through
the sensor camera's view-projection matrix to find where in the sensor's viewport that direction
appears, and samples the colour there.

From the pilot's perspective the screen fills the cockpit interior with a live world view.
From outside, the same mesh face is visible (inward normals, `cull_back`) and shows the same
reprojected image.

---

## Why Not Just Use the Camera's Rendered Image Directly?

The sensor camera renders a **perspective** image: objects close to the camera appear large, the
image distorts at the edges, and the FOV covers only a cone. The panoramic screen displays a
**spherical** image: each point on the sphere maps to a fixed world direction regardless of
perspective.

The shader bridges this by inverting the sensor camera's perspective: for each screen fragment, it
asks "given this panoramic direction, where does the sensor camera see that direction?" and samples
there. This works as long as the sensor camera's FOV is wide enough to contain every direction the
viewer can currently see on the screen.

---

## System Components

| Component | File | Role |
|-----------|------|------|
| `SensorHead` | `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/sensor_head.gd` | Owns SubViewport + Camera3D. Tracks viewer direction, computes dynamic FOV, exposes texture + matrices. Auto-discovers dependencies via `VehicleBase`. |
| `PanoramicScreen` | `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/panoramic_screen.gd` | Builds the spherical mesh with UV2 panoramic encoding. Pushes shader uniforms every frame. Exposes segment mask API. Auto-discovers `SensorHead` via `VehicleBase`. |
| `panoramic_screen.gdshader` | `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/Shader/panoramic_screen.gdshader` | Per-fragment: UV2 → world direction → project → sample. |
| `SensorFovSolver` | `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/Helper/sensor_fov_solver.gd` | Pure-math helper: `solve_required_fov()` and `compute_viewport_size()`, extracted from `SensorHead`. |
| `PanoramicMeshBuilder` | `Entities/Vehicles/Cockpits/Components/PanoramicDisplay/Mesh/panoramic_mesh_builder.gd` | Pure-math helper: `build()` sphere mesh, extracted from `PanoramicScreen`. |
| `SpatialMath` | `Common/Calculations/spatial_math.gd` | General 3D math: `ray_sphere_intersect()`. |
| `VehicleBase` | `Core/Base/vehicle_base.gd` | Abstract vehicle root. Provides `find_vehicle()` static walk-up and `get_cockpit()` / `get_sensor_head()` accessors. |
| `CockpitBase` | `Core/Base/cockpit_base.gd` | Abstract cockpit root. Provides `get_player_camera()` / `get_panoramic_screen()` accessors. |
| `CockpitRX0` | `Entities/Vehicles/Cockpits/CockpitRX0/cockpit_rx_0.gd` | Extends `CockpitBase`. Implements mount getters pointing to `$CameraMount` and `$PanoramicDisplayMount`. |
| `MobileSuitRX0` | `Entities/Vehicles/MobileSuits/RX0/mobile_suit_rx_0.gd` | Extends `VehicleBase`. Implements mount getters pointing to `$CockpitMount` and `$SensorHeadMount`. |

---

## Scene Tree Structure

```
MobileSuitRX0  (mobile_suit_rx_0.tscn)   ← extends VehicleBase
├── Sketchfab_model                        ← mech GLB
├── SensorHeadMount  (Marker3D)            ← marks the head sensor position
│   └── SensorHead                         ← auto-discovers cockpit via VehicleBase
└── CockpitMount  (Marker3D)              ← marks where cockpit is placed
    └── CockpitRX0  (cockpit_rx_0.tscn)   ← extends CockpitBase
        ├── Light_Unicorn_Cockpit          ← cockpit GLB (layers = COCKPIT)
        ├── PanoramicDisplayMount (Marker3D) ← positions the display sphere
        │   └── PanoramicScreen            ← auto-discovers SensorHead via VehicleBase
        └── CameraMount  (Marker3D)        ← positions the player camera
            └── PlayerCamera3D
                └── MouseLookController
```

**Key placement rules:**
- `SensorHead` goes under `SensorHeadMount` (at the mech's head bone/pivot) so its `global_position`
  matches the real-world sensor location.
- `PanoramicScreen` goes under `PanoramicDisplayMount` inside the cockpit at pilot eye level,
  centred in the sphere the pilot sits inside.
- `PlayerCamera3D` goes under `CameraMount` so the camera position is owned by the cockpit scene.

**No manual wiring required.** `SensorHead` and `PanoramicScreen` both call `_auto_discover()` in
`_ready()`, which walks up to `MobileSuitRX0` (a `VehicleBase`) and uses the standard accessors to
find each other.

---

## Auto-Discovery

Both components locate their dependencies automatically using the `VehicleBase` tree walk:

```
SensorHead._ready()
  └── _auto_discover()
        ├── VehicleBase.find_vehicle(self)     ← walks up to MobileSuitRX0
        ├── vehicle.get_cockpit()               ← finds CockpitRX0 under CockpitMount
        ├── cockpit.get_player_camera()         ← finds Camera3D under CameraMount
        └── cockpit.get_panoramic_screen()      ← finds PanoramicScreen under PanoramicDisplayMount

PanoramicScreen._ready()
  └── _auto_discover()
        ├── VehicleBase.find_vehicle(self)     ← walks up to MobileSuitRX0
        └── vehicle.get_sensor_head()          ← finds SensorHead under SensorHeadMount
```

The `@export var viewer_camera` and `@export var panoramic_screen` on `SensorHead`, and
`@export var sensor_head` on `PanoramicScreen`, remain as optional overrides for testing
outside a full vehicle hierarchy (e.g. a standalone sensor test scene).

**Important:** Mount getters use `get_node()` directly (not `@onready`) so they work when called
from a child's `_ready()`, which fires before the parent's own `_ready()`.

---

## Data Flow Each Frame

```
_process() on SensorHead
  │
  ├── viewer_camera.project_ray_normal(9 sample pixels)
  │     → SensorFovSolver.solve_required_fov(...)
  │         → SpatialMath.ray_sphere_intersect() per sample
  │         → max_h_half_angle, max_v_half_angle
  │
  ├── _camera.transform  = Transform3D(looking_at(world_look), sensor_pos)
  ├── _camera.fov        = 2 × max_v_half_angle + safety_margin  (vertical FOV)
  │
  └── SensorFovSolver.compute_viewport_size(...)
        → ppd = (display_height / viewer_vfov) × quality_scale
        → new_vpx = clamp(ppd × required_vfov, min, max)
        → new_hpx = new_vpx × tan(hfov/2) / tan(vfov/2)   (perspective aspect)
        → _viewport.size = Vector2i(new_hpx, new_vpx)      [if >10% change]

_process() on PanoramicScreen
  │
  └── push shader uniforms:
        sensor_viewport   ← SubViewport texture
        sensor_view_proj  ← Camera3D projection × view matrix
        sensor_world_pos  ← Camera3D.transform.origin
        sensor_basis      ← SensorHead.global_transform.basis  ← FIXED orientation
```

---

## The `sensor_basis` Critical Detail

`sensor_basis` is **SensorHead's own fixed orientation** (`global_transform.basis`), **not** the
sensor camera's tracking rotation.

If the camera's rotating basis were used instead:
- Shader computes `world_dir = camera_rotation * local_dir`
- View matrix inverts camera rotation: `clip = (camera_rotation⁻¹) * (camera_rotation * local_dir)`
- The rotations cancel → `clip` is always the same regardless of look direction
- Screen content never moves

The panoramic coordinate system is fixed to the mech body. Azimuth = 0 always maps to the mech's
forward direction (`-SensorHead.global_basis.z`). The camera rotates to track the viewer while the
panoramic directions stay anchored to the world.

---

## The SubViewport Position Trick

`SubViewport` is a `Node`, not a `Node3D`. It has no spatial transform. When the renderer uses the
`Camera3D` inside the SubViewport, it uses the camera's **local** transform as its world-space
transform, effectively skipping the SubViewport in the spatial hierarchy.

This means:
```gdscript
# WRONG: routes through SensorHead's spatial transform → camera ends up at local (0,0,0)
_camera.global_transform = some_world_transform

# CORRECT: sets camera position directly in world space
_camera.transform = Transform3D(world_basis, world_position)
```

Similarly, `get_world_pos()` returns `_camera.transform.origin` (not `global_position`), and
`get_view_proj()` uses `_camera.transform.affine_inverse()` (not `_camera.get_camera_transform()`).

---

## Render Layer Setup

Defined in `Core/AutoLoad/layers.gd`:

| Layer | Bit | Who sees it |
|-------|-----|-------------|
| `WORLD` | 1 | All cameras |
| `VEHICLE_EXT` | 2 | Third-person + sensor |
| `COCKPIT` | 8 | First-person only — **sensor excluded** |
| `SENSOR_BODY_PARTS` | 128 | Sensor only (toggleable) |
| `SENSOR_WEAPONS` | 256 | Sensor only (toggleable) |
| `SENSOR_SHIELDS` | 512 | Sensor only (toggleable) |

`COCKPIT` is intentionally excluded from `MASK_SENSOR` so the panoramic screen mesh never
appears inside its own sensor feed — preventing an infinite recursion / echo.

The sensor camera defaults to `WORLD | FX` (no mech body). Once individual mesh nodes are
assigned their `SENSOR_BODY_PARTS / SENSOR_WEAPONS / SENSOR_SHIELDS` layers, call
`sensor_head.set_group_visible(Layers.SENSOR_BODY_PARTS, true)` to make them appear on screen.

---

## Quality vs. Performance Knobs

| Export | Default | Effect |
|--------|---------|--------|
| `quality_scale` | 1.0 | `1.0` = matches display resolution. `2.0` = super-sampled. `0.5` = half-res. Automatically correct across 1080p / 2K / 4K — no manual pixel math needed. |
| `fov_safety_margin_degrees` | 2.0 | Degrees added to computed H and V FOV. Prevents 1-frame seams during fast rotation. |
| `min_viewport_size` | 256 | Minimum for either viewport dimension. |
| `max_viewport_size` | 4096 | Cap for either viewport dimension. |

---

## Performance Analysis

### Render passes

This system uses **2 render passes** per frame:

1. **Sensor pass** — SubViewport Camera3D renders the world from the mech head into a texture
2. **Main pass** — player camera renders normally; the sphere shader samples that texture

The sensor pass is the expensive one. The reprojection shader in the main pass is cheap —
roughly 20 ALU ops plus one texture fetch per screen pixel covered by the sphere.

### Why the sensor pass is justified

| Approach | Passes | Works for RX-0 |
|----------|--------|---------------|
| Move cockpit to mech head (Armored Core style) | 1 | ✗ — cockpit must be at sensor location |
| Render texture on flat screen | 2 | Partial — not spherical, not visible from outside |
| **This system (spherical reprojection)** | **2** | **✓** |
| 6-camera cubemap | 7 | ✓ but 3.5× more expensive |

### Sensor pass cost mitigations built in

- **Rectangular viewport** matches required H/V coverage — no square-viewport pixel waste
- **`cull_mask = WORLD | FX`** excludes cockpit interior (most overdraw-heavy geometry)
- **10% resize hysteresis** prevents per-frame GPU texture reallocation
- **`quality_scale`** lets you trade sharpness for performance without understanding internals

### Further optional optimisations

- **Disable sensor post-processing** (SSAO, glow, SSIL) — saves 30–50% sensor pass cost
- **`UPDATE_ONCE` when stationary** — no movement = no new image needed
- **`max_viewport_size = 2048`** — still 4× 1080p density, indistinguishable at screen distance
- **`quality_scale = 0.75`** — ~44% fewer pixels than 1.0, still visually sharp

---

## Known Limitations

- **Maximum sensor FOV is 160°.** If the viewer's frustum requires a wider sensor FOV (e.g. very
  wide player FOV + very close to screen), fragments near the extreme edges will show `no_signal_color`.
  Mitigation: keep `screen_radius` larger relative to the cockpit footprint.
- **Near objects show parallax error.** The shader projects from `sensor_world_pos + dir * 500`,
  assuming all world content is at infinity. Objects closer than ~10 m to the sensor will appear
  slightly shifted vs. real perspective. This is invisible for space environments.
- **Viewport resize hysteresis.** Resize only triggers when size changes > 10% to avoid per-frame
  GPU memory reallocation. Sharp changes in visible screen area cause a one-frame resolution step.
