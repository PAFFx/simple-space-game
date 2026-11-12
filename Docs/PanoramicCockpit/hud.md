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

**Colours by role** (PanoramicHud style): green = flight symbology (horizon, ladder, flight path,
speed), pale blue-white = the suit against the cockpit (boresight, suit attitude), violet = the
suit's equipment (shield and weapon outlines), amber = contacts; caution amber, warning red.
`PanoramicHud.dimmed(c)` tones a role colour down for scales and labels. Every line and label gets
a dark halo (`halo_color`, `halo_width`) so it reads against a sunlit planet without being brighter.

**Modes** list only what differs from the defaults (attitude hold, horizon lock, normal movement):
ROT RATE, HORIZON FREE, PRECISION / BOOST / BOOST FULL, BRAKE / BRAKE HARD, FCS OFF.

**Attitude frame.** The horizon ring, pitch ladder and HDG/PIT/RLL readout all use
`hud.get_attitude_basis()`: up = the horizon the flight computer holds level to (horizon lock's
up; the reference frame's up when it's off), north = the reference frame's −Z flattened onto it.
Before, the ladder used the reference frame, the readout world axes and the lock its own up, so
the ladder sat ~10° off from what the suit held level.

**Near the poles.** The equirectangular canvas stretches horizontally by 1/cos(elevation), so
flat text thins toward the zenith: use `text_at()` for labels at canvas positions (it widens them
back). Long marks run along great circles (ladder rungs keep their angular length up to 80°
instead of shrinking with the latitude circle).

World-anchored symbols (silhouettes, contact brackets) take their direction from the **sensor
head** (`hud.get_view_origin()`), where the image is rendered from, not from the pilot's seat.
Distant things look the same either way; the suit's own shield, a few metres from the head, would
otherwise sit visibly off its place in the image.

The canvas is laid out in the **display frame**, the screen's own orientation
(`hud.get_display_basis()`, `hud.world_to_display()`). It differs from the suit's body when the
cockpit gimbal turns the seat for thrust vectoring. That's why the boresight (body axis) can move
away from the canvas centre (cockpit forward).

### Writing a widget

1. Extend `HudWidget` (a `Node2D`) and implement `draw_widget()`.
2. Lay out in **degrees**: `begin_local(az_deg, el_deg)` gives you a local frame where 1 unit = 1
   canvas pixel (`px(deg)` converts), with equirectangular stretch compensated.
3. For world-anchored symbols, take `point − hud.get_view_origin()` and place it with
   `hud.world_dir_to_canvas(dir)` (or `hud.world_to_display(dir)` →
   `HudProjector.direction_to_angles()` → `begin_local_at()`).
4. Add the node under `HudViewport` in `panoramic_hud.tscn`.

Data sources: `hud.flight_computer` (state, thrusters, modes, propellant), `hud.hatch`,
`hud.sensor_head`.

Contacts: add any `Node3D` to group `hud_contacts`; optional metadata `hud_label` and `hud_radius`.

Silhouettes: add a `HudSilhouette` (outline points in its local space) to anything the pilot should
see "through". The sensor never renders the suit or its equipment, so the shield appears only as its
outline, like an integrated shield camera. With `from_meshes` the outline is built at load from the models under its parent:
the rim seen face-on (convex hull across the model's thinnest axis), each corner at its real depth,
so a curved shield's outline sits on its actual edge (both shields use it). Outlines and contact
brackets use the rendered (interpolated) transforms: with the raw physics transform the shield's
outline jumped ~20° per frame at 250 m/s on a 144 Hz display.

## Physics interpolation

The project runs physics at 60 Hz with interpolation on, so the suit moves smoothly on high-refresh
displays. Anything placed per frame must use interpolated transforms:
`PilotCamera` and `OrbitCamera` follow `get_global_transform_interpolated()`, and the screen
shader, sensor and HUD read `PanoramicScreen.get_display_transform()`. Gameplay transforms
(gimbal, station rotation, grips) change in `_physics_process`.

## External camera

`OrbitCamera` orbits the suit in the **pilot frame** (`follow_pilot_frame`, the vehicle cockpit's
orientation) rather than the body's, so the outside view stays as steady as the cockpit view and
the suit visibly leans and rolls inside it during auto-rotation. `orientation_source` overrides it.

## Linear seat: gimbal and G dampening

- `CockpitGimbal` rotates the whole cockpit by the measured `body⁻¹ · pilot`, so the cockpit holds
  still in the world while the body turns, even mid-swing. Range 75°, eased (not clamped) past
  62° so an overshooting body never snaps the view. Commanded rotations move the pilot frame, so the cockpit
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

## Cockpit displays

Three flat screens in front of the seat (after the Xi Gundam's cockpit), painted by
`CockpitDisplays`: each screen mesh in the cockpit model (`ScreenCentre`, `ScreenLeft`,
`ScreenRight`, built by `Tools/Blender/build_cockpit_linear_seat.py`) gets an `MfdPage` in its
own SubViewport. Pages follow modern fighter large-area displays: dark field, thin outlines,
boxed values.

- **Centre: SA** (`SaPage`), the biggest: plan view centred on the suit, heading up, over the
  HUD's attitude plane (`FlightComputer.get_attitude_basis()`). Range rings step to fit the
  farthest contact (500 m … 200 km), compass rose, contacts as diamonds with range and height
  above (+) / below (−) the plane, the suit's velocity as a leader line, data strip on top.
- **Left: ENG / FUEL** (`EnginePage`): thrusters in three tiers by rating, biggest on top and
  drawn biggest: MAIN (≥ 50% of the largest: the four backpack mains, with gimbal dots), BIG
  (≥ 20%: soles, calves, shoulders, chest), SMALL (the verniers, for troubleshooting). Fuel
  window: mass, %, flow (thrust ÷ Isp·g₀), time left at the current flow, Isp, BINGO under 20%.
  Header: total thrust (% and MN) and max thrust-to-weight.
- **Right: TGT** (`TargetPage`): placeholder until targeting exists.

The panoramic HUD keeps only what's needed outside: flight symbology, non-default modes and
cautions. The thruster rows and propellant / thrust bars moved to the left display.

## Hatch

`CockpitHatch` runs one timeline (0 = sealed, 1 = open): the screen cuts its aperture, then the
suit's door bones swing. Around the open aperture the HUD draws orange segmented brackets and
HATCH / UNLOCK tabs (`HatchWidget`; SEALING while closing), outside the cockpit's portal frame.
`HatchCockpitParts` owns the hatch switch on the right console: click the yellow guard to lift
(left) or lower (right) it; with it up, the red button opens or closes the hatch (and dips). The
centre display folds onto the pilot's lap on the hatch timeline so it doesn't block the way out.
The shell's portal frame sits between the screen and the shell, so it shows only through the open
hatch (it used to float inside the screen, in the pilot's view).

## Cockpit switches

`CockpitClickMode` (middle mouse) frees the cursor; the nearest `CockpitClickable` under it lights
up with a tooltip, left click throws it one way, right click the other. `CockpitSwitchPanel`
builds the left console's toggle switches (`CockpitSwitch`: base, lever, labels) in two groups
and keeps each lever on the state it controls.

**ν:** the door is the red panel at the bottom of the chest (split from the chest mesh by
`build_mobile_suit_nu.py`, bone `hatch`, hinged on its bottom edge, swings out 100°). The sphere
can't sit lower than y 17.2 without poking out under the chest, so a white tunnel runs from the
shell down to the door, 40.7° below straight ahead; the ν's cockpit variant
(`cockpit_linear_seat_nu.tscn`, model built with `--aperture -40.7,12.5,11.5`) has its shell
opening and screen aperture there. A fit test (shell points inside the hull) finds the whole
sphere inside the chest at its current place.

