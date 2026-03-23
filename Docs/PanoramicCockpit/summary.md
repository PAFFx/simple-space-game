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
| `SensorHead` | `Common/PanoramicDisplay/sensor_head.gd` | Owns SubViewport + Camera3D. Tracks viewer direction, computes dynamic FOV, exposes texture + matrices. |
| `PanoramicScreen` | `Common/PanoramicDisplay/panoramic_screen.gd` | Builds the spherical mesh with UV2 panoramic encoding. Pushes shader uniforms every frame. Exposes segment mask API. |
| `panoramic_screen.gdshader` | `Common/PanoramicDisplay/panoramic_screen.gdshader` | Per-fragment: UV2 → world direction → project → sample. |
| `CockpitRX0` | `Entities/Vehicles/Cockpits/CockpitRX0/cockpit_rx_0.gd` | Simple root script. Exposes `panoramic_screen` as a typed export for the controller to reach it from the vehicle scene. |
| `CockpitDisplayController` | `Entities/Vehicles/MobileSuits/RX0/Components/cockpit_display_controller/cockpit_display_controller.gd` | Assembled-scene wiring: connects SensorHead ↔ PanoramicScreen at `_ready()`. |

---

## Scene Tree Structure

```
MobileSuitRX0  (mobile_suit_rx_0.tscn)
├── Sketchfab_model          ← mech GLB
├── MainSensorMarker         ← Marker3D at head pivot
│   └── SensorHead           ← placed here; global_position = sensor world pos
├── CockpitRX0               ← cockpit_rx_0.tscn instance
│   ├── Light_Unicorn_Cockpit ← cockpit GLB contents
│   ├── MeshInstance3D        ← placeholder sphere mesh (editor only)
│   │   └── PanoramicScreen   ← the display; positioned at pilot eye level
│   └── PlayerCamera3D        ← first-person camera
│       └── MouseLookController
└── CockpitDisplayController  ← wires the two trees together at runtime
```

**Key placement rules:**
- `SensorHead` goes under `MainSensorMarker` (the mech's head bone/pivot) so its `global_position`
  matches the real-world sensor location.
- `PanoramicScreen` goes inside the cockpit at pilot eye level, centred in the sphere the pilot
  sits inside.

---

## Data Flow Each Frame

```
_process() on SensorHead
  │
  ├── viewer_camera.project_ray_normal(corner pixels)
  │     → cast 5 rays through screen sphere
  │     → find panoramic direction of each hit
  │     → compute max angular half-span from viewer's look direction
  │
  ├── _camera.transform = Transform3D(looking_at(world_look), sensor_pos)
  ├── _camera.fov       = 2 × max_half_angle + safety_margin_deg
  └── _viewport.size    = clamp(pixels_per_degree × fov, min, max)  [if >10% change]

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
| `pixels_per_degree` | 32 | Viewport pixels per degree of sensor FOV. Directly controls sharpness. |
| `fov_safety_margin_degrees` | 8 | Degrees added to computed FOV. Prevents 1-frame seams during fast rotation. |
| `min_viewport_size` | 256 | Minimum SubViewport dimension (px). Prevents zero-size on edge-case angles. |
| `max_viewport_size` | 4096 | Cap to avoid out-of-memory at extreme FOVs. |

Typical in-cockpit FOV computes to ~120–130° (due to sensor being outside and above the sphere).
At 32 px/deg that allocates ~3840–4160px, capped at 4096.

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
