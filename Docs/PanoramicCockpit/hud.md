# Panoramic HUD and Hatch Aperture

## HUD

The HUD is painted **onto the panoramic screen**, not onto the player's camera. It's part of the
display, visible from any seat position and from outside through the open hatch.

```
PanoramicHud (Node)
└── HudViewport (SubViewport, 4096×2048, transparent)   ← equirectangular canvas
    ├── Attitude        horizon ring (360°, heading marks) + pitch ladder
    ├── Boresight       fixed reticle on the body axis
    ├── FlightPath      prograde / retrograde markers + speed
    ├── FlightData      SPD / ACC / ROT, PROP / THR bars, FCS modes, cautions
    ├── ThrusterStatus  per-thruster throttle bar + gimbal dot
    └── Contacts        brackets for nodes in group `hud_contacts`
```

`PanoramicScreen.set_hud_texture()` hands the viewport texture to the screen shader, which samples
it with the same azimuth/elevation it uses for the sensor image:

```
hud_uv = (fract(UV2.x + 0.5), 1 − UV2.y)     forward = canvas centre, wraps at the back
```

So anything drawn at a direction lines up with the sensor image of that direction, with no
extra projection.

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
