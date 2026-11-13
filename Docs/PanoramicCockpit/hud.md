# Panoramic HUD and Hatch Aperture

## HUD

The HUD is painted **onto the panoramic screen**, not onto the player's camera. It's part of the
display, visible from any seat position and from outside through the open hatch.

```
PanoramicHud (Node)
└── HudViewport (SubViewport, 4096×2048, transparent)   ← equirectangular canvas
    ├── Silhouettes     outlines of nearby HudSilhouette nodes (e.g. the shield)
    ├── Attitude        pitch ladder (two unnumbered tick columns ±30° off the heading, with
                        a pointer carrying the current pitch, and a highlight running up the
                        ticks while climbing, down while descending); small attitude indicator at
                        the zenith inside a numbered course ring at 28° elevation (translucent), with the
                        HDG box on its pointer (horizon ring off, reserved)
    ├── SuitAttitude    suit vs cockpit: the suit's horizontal plane as one double-rail line
                        all the way round, open ahead between two accent arrowheads (the suit's
                        nose is midway); rings 90° left/right with cockpit-level marks
    ├── ControlCentre   V above and ^^ below the direction fly-by-wire "forward" pushes (the
                        control law's pilot frame), empty in the middle
    ├── FlightPath      prograde ○ / retrograde × inside a wide reticle (radial dashes 17° out,
                        left and right quarters only), each with two wide bars of slanted stripes
                        (out to the ladder, packed toward the middle); a highlight runs across
                        them, outward ahead and inward behind; grows in above show_speed,
                        shrinks away below hide_speed holding its last direction
                        BOOST: faster, wider highlight, bars stretch; FULL: second highlight,
                        accent tint, a kick flash outward on engaging. BRAKE: highlight turns
                        inward, bars squeeze; HARD: stripes' lean flips, bars pulse
    ├── ThrustCue       chevron columns inside both ladder columns while boosting (^ lit upward)
                        or braking (v lit downward); doubled, faster, accent at FULL / HARD
    ├── FlightData      left column: G MS / G PLT / ROT / AMBAC over boxed SPD and Mach (dim);
                        non-default modes just inside the right ladder column; cautions
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

**Fixed layers.** Most of the HUD only *turns* with the attitude, so it isn't redrawn every frame.
`PanoramicHud.add_layer_drawer(layer, draw_fn)` draws it once into an extra equirectangular
SubViewport, in the layer's own frame, and the screen shader (`PanoramicHud/Shader/hud_layers.gdshaderinc`)
turns it into place per pixel with a `hud_<layer>_frame` uniform (display direction → layer direction):

| Layer | Frame | Content |
|---|---|---|
| `static` | display (fixed) | side rings, course ring line and pointer, HDG box frame, overhead indicator ring and wings, pitch pointers |
| `heading` | `Basis(UP, heading − 15°)⁻¹` | course marks and numbers, drawn for heading 15° so none sits on the layer's back seam |
| `ladder` | `Basis(RIGHT, pitch)` | the pitch ladder drawn level, as coverage (R stroke, G halo, B stroke × tick strength); the shader applies fade and climb highlight from `hud_pitch_deg` / `hud_climb`, blending as the 2D canvas would |
| `suit` | `(display⁻¹ · body)⁻¹` | suit line and arrowheads, drawn with the body level |
| `fpm` | layer −X onto the velocity, up as `patch()` makes it | flight path markers as coverage (R stripe, G halo, B the rest × its fade), prograde at −X and retrograde at +X, off the back seam; the shader finds each stripe from its position and runs the highlight, tint, fade-in and pulse. Redrawn only while the shape changes (growing in/out, boost stretch, brake squeeze, hard-brake lean) |

Layers composite under the per-frame canvas, which keeps only what changes: numbers, the overhead
horizon line, data blocks, contacts. Before this, the ladder alone projected ~1,400
points a frame in GDScript and the HUD cost ~14 ms of CPU; now ~1.5 ms. `PanoramicHud.redraw_layers()`
draws them again after changing what they show (layers don't follow export edits at runtime).
Colour uniforms the shader blends as canvas colours need `source_color, color_conversion_disabled`:
Godot otherwise linearizes every `Color` passed to a `vec4` of a 3D material.

**Colours by role** (PanoramicHud style, a mostly white-grey panoramic HUD with colour reserved for
what needs attention): off-white = flight symbology (flight path, speed, modes, control centre),
pale steel blue = the pitch ladder, grey = scales and labels, translucent grey-white = the suit
against the cockpit (suit line, side rings), pink-violet = accents (the suit line's arrowheads,
the control centre's lower chevron), muted lavender = the suit's equipment (shield and weapon
outlines), orange = contacts; caution yellow, warning red.
`PanoramicHud.dimmed(c)` tones a role colour down for scales and labels. Every line and label gets
a dark halo (`halo_color`, `halo_width`) so it reads against a sunlit planet without being brighter.

**Modes** list only what differs from the defaults (attitude hold, horizon lock, normal movement):
ROT RATE, HORIZON FREE, PRECISION / BOOST / BOOST FULL, BRAKE / BRAKE HARD, FCS OFF.

**Course ring.** A latitude circle of the display frame (`course_elevation_deg`), so it's drawn
straight from (azimuth, elevation) rather than as a patch: patch offsets use tan(), which would
square off a ring 62° from its centre. Mark azimuth = bearing from the current heading.

**Attitude frame.** The pitch ladder, course ring and HDG readout all use
`hud.get_attitude_basis()`: up = the horizon the flight computer holds level to (horizon lock's
up; the reference frame's up when it's off), north = the reference frame's −Z flattened onto it.
Before, the ladder used the reference frame, the readout world axes and the lock its own up, so
the ladder sat ~10° off from what the suit held level.

**Near the poles.** The equirectangular canvas stretches horizontally by 1/cos(elevation), so
flat text thins toward the zenith: use `text_at()` for labels at canvas positions (it widens them
back). Ladder columns run along meridians of the attitude frame (bearing ±`ladder_column_az_deg` from
the heading), so they lean together toward the zenith; each tick runs along a great circle, so it
keeps its angular length up to 85° instead of shrinking with the latitude circle.

At the poles themselves (the zenith attitude indicator, centred on +90°) a whole canvas row
is one point, so a line's canvas width no longer matches its width on the sphere: a radial tick
would vanish. `patch(centre, up, true)` makes an **exact** patch: strokes are built as quads in
degrees and every corner projected, text gets a transform from the projection's derivative
(upright in the patch), and both are drawn on either side of the back seam. Use it only there; it
has no antialiasing.

World-anchored symbols (silhouettes, contact brackets) take their direction from the **sensor
head** (`hud.get_view_origin()`), where the image is rendered from, not from the pilot's seat.
Distant things look the same either way; the suit's own shield, a few metres from the head, would
otherwise sit visibly off its place in the image.

The canvas is laid out in the **display frame**, the screen's own orientation
(`hud.get_display_basis()`, `hud.world_to_display()`). It differs from the suit's body when the
cockpit gimbal turns the seat for thrust vectoring. That's why the suit line's opening (body axis) can move
away from the canvas centre (cockpit forward).

### Writing a widget

1. Extend `HudWidget` (a `Node2D`) and implement `draw_widget()`.
2. Lay out in **degrees**: `begin_local(az_deg, el_deg)` gives you a local frame where 1 unit = 1
   canvas pixel (`px(deg)` converts), with equirectangular stretch compensated.
3. For world-anchored symbols, take `point − hud.get_view_origin()` and place it with
   `hud.world_dir_to_canvas(dir)` (or `hud.world_to_display(dir)` →
   `HudProjector.direction_to_angles()` → `begin_local_at()`).
4. Add the node under `HudViewport` in `panoramic_hud.tscn`.
5. Parts that only turn with the attitude belong in a fixed layer: override `setup_layers()` and
   register `hud.add_layer_drawer(layer, func(w): ...)`, drawing through `w` (a `HudLayerCanvas`)
   in the layer's frame. Per frame, set the layer's frame uniform with `hud.set_hud_parameter()`.

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

## Linear seat: gimbal

- `CockpitGimbal` rotates the whole cockpit by the measured `body⁻¹ · pilot`, so the cockpit holds
  still in the world while the body turns, even mid-swing. Range 75°, eased (not clamped) past
  62° so an overshooting body never snaps the view. Commanded rotations move the pilot frame, so the cockpit
  turns with the suit for those.
- No seat G dampening: a travel-limited seat can't reduce sustained G, so the pilot feels the
  suit's G. `HIGH G` caution above 6 G (`G MS`).

Canvas resolution is ~11.4 px/degree. Raise `canvas_size` for sharper text, at the cost of memory.

## Hatch

The ν's hatch is an airlock: the outer door (the red panel at the bottom of the chest), a
corridor, and the cockpit's own inner door. `CockpitHatch` runs one timeline (0 = sealed, 1 = open)
that `HatchCockpitParts` follows:

| Timeline | What moves |
|---|---|
| 0–0.25 | the seat turns 40° (with the pedals, footrest, right armrest and the main and right monitors; the left armrest and monitor stay) to clear the way |
| 0.2–0.45 | the screen cuts a door-shaped opening (flat as seen from the seat) down the airlock, framed by `HatchWidget`'s orange segmented brackets hugging all four edges and HATCH / UNLOCK tabs over the top corners |
| 0.35–0.6 | the inner door's two halves slide apart |
| 0.6–1 | the outer door slides up along its own tilt, behind the chest front (`HatchPanel.slide`) |

While unsealed, the linear seat holds still: the cockpit gimbal eases to centre (so the capsule
lines up with its doorway and can't turn into the hull) and the seat dampener stops responding.

Control: the yellow/black hatch lever on the right console, under a striped guard. Click the guard
to lift (left) or lower (right) it; with it up, the lever pulls (left: open) or pushes (right:
close). The lever sits pulled while the hatch is open.

**ν model** (`build_mobile_suit_nu.py`): the belly is stretched taller (the chest below 15.9 m ×1.8,
the lower body 0.76 m lower; the scene builder lowers its lower-body positions to match), and the
navy column around the door stretches further, along its own slope so the door stays flat, until it
meets the crotch armour. The door is 0.95 × 1.76 m. The corridor (seams, hazard stripes at both
ends, grab handles, light strips) runs 37° down from the cockpit sphere to it; the cockpit sits at
(0, 16.6, −0.2), where a fit test keeps the sphere inside the hull. The corridor and door are
`first_person_parts`, so the pilot sees them once the hatch is unsealed. The cockpit is drawn for
outside cameras only while unsealed (sealed, the gimballed capsule's frame could poke through the
hull). Its variant (`cockpit_linear_seat_nu.tscn`, model built with `--aperture -37.3,20.5,25.3`)
has the shell opening and screen aperture on the corridor.

## Cockpit switches

`CockpitClickMode` (middle mouse) frees the cursor; the nearest `CockpitClickable` under it lights
up with a tooltip, left click throws it one way, right click the other. `CockpitSwitchPanel`
builds the left console's toggle switches (`CockpitSwitch`: base, lever, labels) on the model's
`SwitchPanelMount` (the console's front face): FCS, ROT, HRZN, MOVE, AMBAC, each lever kept on the
state it controls.

**ν:** the door is the red panel at the bottom of the chest (split from the chest mesh by
`build_mobile_suit_nu.py`, bone `hatch`, hinged on its bottom edge, swings out 100°). The sphere
can't sit lower than y 17.2 without poking out under the chest, so a white tunnel runs from the
shell down to the door, 40.7° below straight ahead; the ν's cockpit variant
(`cockpit_linear_seat_nu.tscn`, model built with `--aperture -40.7,12.5,11.5`) has its shell
opening and screen aperture there. A fit test (shell points inside the hull) finds the whole
sphere inside the chest at its current place.

