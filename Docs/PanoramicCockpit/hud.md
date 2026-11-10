# Panoramic HUD and Hatch Aperture

## HUD

The HUD is painted **onto the panoramic screen**, not onto the player's camera. It's part of the
display, visible from any seat position and from outside through the open hatch.

```
PanoramicHud (Node)
└── HudViewport (SubViewport, 4096×2048, transparent)   ← equirectangular canvas
    ├── Silhouettes     outlines of nearby HudSilhouette nodes (e.g. the shield)
    ├── Attitude        horizon ring (360°, heading marks) + pitch ladder, in the cockpit frame
    ├── Boresight       body-axis reticle (rolls with the body)
    ├── SuitAttitude    suit vs cockpit: big PITCH gauges 90° left/right (side view), small ROLL
                        gauge below the reticle (rear view); circle = cockpit, line = suit
    ├── FlightPath      prograde / retrograde markers + speed
    ├── FlightData      SPD / G MS / G PLT / ROT / AMBAC, PROP / THR bars, FCS modes, cautions
    ├── ThrusterStatus  mains row + vernier rows, bar height ∝ rated thrust, gimbal dot
    └── Contacts        brackets for nodes in group `hud_contacts`
```

`PanoramicScreen.set_hud_texture()` hands the viewport texture to the screen shader, which samples
it with the same azimuth/elevation it uses for the sensor image:

```
hud_uv = (fract(UV2.x + 0.5), 1 − UV2.y)     forward = canvas centre, wraps at the back
```

So anything drawn at a direction lines up with the sensor image of that direction, with no
extra projection.

The canvas is laid out in the **display frame**, the screen's own orientation
(`hud.get_display_basis()`, `hud.world_to_display()`). It differs from the suit's body when the
cockpit gimbal turns the seat for thrust vectoring. That's why the boresight (body axis) can move
away from the canvas centre (cockpit forward).

### Writing a widget

1. Extend `HudWidget` (a `Node2D`) and implement `draw_widget()`.
2. Lay out in **degrees**: `begin_local(az_deg, el_deg)` gives you a local frame where 1 unit = 1
   canvas pixel (`px(deg)` converts), with equirectangular stretch compensated.
3. For world-anchored symbols, convert with `hud.world_to_sensor(dir)` →
   `HudProjector.direction_to_angles()` → `begin_local_at()`.
4. Add the node under `HudViewport` in `panoramic_hud.tscn`.

Data sources: `hud.flight_computer` (state, thrusters, modes, propellant), `hud.hatch`,
`hud.sensor_head`.

Contacts: add any `Node3D` to group `hud_contacts`; optional metadata `hud_label` and `hud_radius`.

Silhouettes: add a `HudSilhouette` (outline points in its local space) to anything the pilot should
see "through". The sensor never renders the suit or its equipment, so the shield appears only as its
outline, like an integrated shield camera.

## Physics interpolation

The project runs physics at 60 Hz with interpolation on, so the suit moves smoothly on high-refresh
displays. Anything placed per frame must use interpolated transforms:
`PilotCamera` and `OrbitCamera` follow `get_global_transform_interpolated()`, and the screen
shader, sensor and HUD read `PanoramicScreen.get_display_transform()`. Gameplay transforms
(gimbal, station rotation, grips) change in `_physics_process`.

## Linear seat: gimbal and G dampening

- `CockpitGimbal` rotates the whole cockpit by the measured `body⁻¹ · pilot` (clamped to 70°),
  so the cockpit holds still in the world while the body turns, even mid-swing. Commanded rotations move the pilot frame, so the cockpit
  turns with the suit for those.
- `SeatDampener` models the seat suspension (spring-damper, 14 rad/s, ζ 0.8, ±0.15 m travel) plus
  an active inertial compensator that cancels 55% of what's left. `G MS` is the suit, `G PLT` is
  what the pilot feels; a boosted 3 G burn reads about 1.4 G at the seat. The camera sways with the
  seat travel. `HIGH G` caution above 6 G at the seat.

Canvas resolution is ~11.4 px/degree. Raise `canvas_size` for sharper text, at the cost of memory.

## Hatch aperture

The screen shader can cut a rectangle (in azimuth/elevation) out of the sphere:

- `PanoramicScreen.aperture_center_deg`, `aperture_half_size_deg`: geometry, set to match the hatch.
- `PanoramicScreen.set_aperture_amount(0..1)`: opens from the centre line outward.

`CockpitHatch` drives this on a single timeline together with the hatch bones:

```
amount  0.0 ──── 0.3 ──────────── 0.85 ── 1.0
        screen splits open
                 upper flap swings up ───┘
                       lower flap folds down ──┘
```

Closing plays the same timeline backwards: flaps seal first, then the screen closes.
