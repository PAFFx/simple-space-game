# Cameras, the panoramic screen and the cockpit under damage

The panoramic image is the suit's cameras put together. Losing cameras loses parts of the view;
losing a weapon's or the shield's camera makes that equipment stop being see-through; a beam
through the cockpit kills screen sections and opens real holes to the outside; a beam through
the pilot ends the game.

## How the screen works today

`SensorHead` renders **one** virtual camera at the head pivot, aimed where the viewer looks, with
the suit's own body and equipment left out of its cull mask (the body and the shield are
"see-through"; DGFT shows arm and rifle outlines, the shield is a `HudSilhouette` outline).
`SensorSuite` separately models the cameras for tracking: the head's main camera (narrow + wide)
and six body cameras as positions and facings.

That stays: rendering one camera per physical camera would multiply the sensor cost. What
changes is that the image is **masked by which physical cameras could see each direction**, and
parts are **put back into the image** when nothing can see past them.

## Camera list

One list, in the damage layout, used by both the sensors (tracking) and the screen (coverage).
Each camera rides a bone (a marker under a `BoneAttachment3D`), has a facing, a field (cone
half-angle), a quality class, and is a damage component.

| Camera | Where | Covers | Notes |
|---|---|---|---|
| Main eyes (2) | head | front, ±100° with the head's turn | main view, stereo ranging; the head's green parts |
| Forehead telescope | head | the zoom window only | never fills the normal view; dead = no zoom window ("ZOOM FAIL") |
| Rear head | back of the head | rear | **partly blocked by the hyper bazooka** when it's carried on the back |
| Left chest | the small green part | front-left, low | |
| Shoulders (2) | shoulder armour | sides, 45° forward | today's body cameras 3 and 4 |
| Legs (2) | shins / knees | below and front-below | |
| **Proposed**: rear skirts (2) | rear skirts | rear-low, past the bazooka | covers what the bazooka hides from the rear head camera |
| **Proposed**: main pod tops (2) | top of each backpack pod | rear-high | rear coverage that doesn't depend on the head |
| **Proposed**: forearms (2) | outer forearm | the arm's side and the hand | sees what the hand holds; a cheap way to cover below the arms |
| **Proposed**: feet (2) | top of the foot / ankle | straight down | closes the hole below the suit |
| Shield camera | outer face of the shield | the shield's footprint | **its see-through** |
| Rifle camera | barrel | along the barrel | see-through for the rifle; also a sight |
| Bazooka, funnels | each | their own footprint | see-through for each; funnel views later |

Each lens gets a small **green emissive** (the head's and chest's green parts are already there,
unlit): lit when the camera is live, flickering when degraded, dark when dead. The enemy sees
your blind spots too.

## Coverage: which directions are still seen

The screen shader gets the live cameras as uniform arrays (≤ 24): axis in the screen's frame,
cone half-angle, quality. For each fragment's direction, **coverage = the best live camera whose
cone contains it** (soft-edged over a couple of degrees):

- **Covered by the head**: the full-quality image (today's).
- **Covered only by body cameras**: the same image, blocky (sampled through a block quantise at
  the body cameras' resolution) and slightly delayed-looking (no extra render, a cue only).
- **Not covered**: no signal: dark with the blue block noise the overlay already uses for
  "resolving in", and a thin sector border so the pilot sees the edge of the blind area.

No extra render passes: it is a mask over the one image. Cones ignore the suit's own body
blocking a camera (a left shoulder camera can't see through the chest to the right); first pass
hand-tunes each cone to stop where the body would block it; later a per-camera visibility map
(low-res, cast against the part hulls once per stance) can replace the cone.

The forehead telescope never contributes coverage; the zoom window checks it separately.

## See-through and opaque parts

Each own part or piece of equipment that blocks the virtual camera's view lists the cameras that
see past it (the shield: its own camera; the rifle: its camera; the legs: the leg, skirt and foot
cameras; the backpack and bazooka: rear head, skirt and pod cameras). **When all of them are
dead, the part stops being see-through**: its mesh is put on a new sensor layer
(`Layers.SENSOR_OPAQUE`, enabled on the sensor camera) and drawn in the image as it is, from
the head's viewpoint, holes and glow included. Its outline / silhouette is dropped.

- Shield camera dead: the shield appears on the screen, a real blind sector wherever you hold it.
- Rifle camera dead: the rifle appears; in the low ready it sits in the lower right of the view.
- Leg and foot cameras dead: looking down, you see your own legs.

The equipment cameras ride the equipment, so severing the arm takes the shield and its camera
with it (and the shield no longer blocks anything).

## Cockpit penetration

The cockpit is a damage part inside the chest, with three components: **hull** (the shell
around the screen), **screen** (the panoramic display, a 2D health map), and **pilot** (a capsule
at the seat, following the seated pilot's pose).

A beam whose drilled cylinder passes through the cockpit:

1. **Pilot**: if the cylinder, plus a lethal margin for heat and molten spray (~0.3 m [tune]),
   touches the pilot capsule: **killed, game over**. No injured state in the first pass
   (`todo.md`, open questions).
2. **Hull holes**: the same hole records as anywhere (`beam_effects.md`), on the cockpit's own
   meshes and on the chest meshes the pilot sees from inside (`VEHICLE_FP` parts). The
   first-person camera already draws the world, so **through a hull hole the pilot sees the real
   outside**, not the sensor image, and a shaft of sunlight comes in if the sun is on that side.
3. **Screen**: the cylinder crosses the screen sphere at two directions (entry and exit). There
   the screen has a real hole (discarded, see-through to the hull hole behind). Around each, a
   wider ring of dead panels (black), then a ring of damaged ones (flicker, colour shift, scan
   noise), then cracked overlay lines. A **2D screen-health texture** (equirectangular, ~256 ×
   128, R8) replaces the existing 1D azimuth `segment_mask`; the shader reads it per fragment.
4. **Decompression**: the cockpit air vents through the holes (a short white burst out of them,
   the cabin sound cut to the suit's contact sound). The pilot is in a normal suit.

Other ways the screen degrades:

- **Shock**: a close blast or a heavy hit jolts the hull (`physics.md` §4): the image tears and
  rolls for a moment (a screen-space glitch on the panoramic shader, strength from the impulse).
- **Power**: on a reactor scram the screen runs on batteries: dimmer, the HUD reduced.
- **Display controller** (a component in the chest): when it dies, the screen falls back to a
  reduced mode (front sector only, or monochrome) rather than going black.

## Repair and testing

The range's rearm (F4) restores cameras, screen, holes and the pilot. Probes (`todo.md`):
`coverage_snapshot.gd` renders the panoramic screen with chosen cameras dead
(`cockpit_snapshot.gd` style, on desktop 7); `cockpit_hit_probe.gd` fires through the chest along
a grid of lines and reports which ones kill the pilot, which hole the screen, which miss the
cockpit.

## As built (2026-11-25)

- **Cameras** (`DamageModel.get_camera_cones`): the head's main camera (105° half field, the head
  turns), a rear head camera (75°), the six SensorSuite body cameras (65–70°), and new ones on
  the rear skirts (65°), feet (70°) and forearms (60°). All alive they cover the whole sphere;
  without the head's eyes 99.4% (the rest no signal), without the eyes and the rear head
  camera 94.4%. Each is a damage component on its part; a severed part takes its camera.
- **Screen**: per pixel, the best live camera covering its direction. Main camera: the full
  picture. Body cameras only: sampled in 320×180 blocks, a little desaturated. None: dark with
  shifting block static and a thin blue edge. Checked from the seat (`damage_snapshot.gd screen`).
- **Opaque parts**: `Layers.SENSOR_OPAQUE` is in the sensor camera's mask; a part whose camera is
  gone gets the bit and is drawn on the screen (`DamageModel.set_opaque`). The shield's camera
  dies with a through-hole (60%); broken equipment turns opaque. Rearm clears it.
- **Screen holes**: where a beam's line crosses the cockpit sphere (1.6 m), up to 8 holes in the
  screen's frame: burned open (ragged, molten rim). The screen is tiled from flat panels
  (`panel_deg`, 15° × 15°): the panel a hole is in dies whole (dark glass with a faint sheen),
  the glass cracks from the hole across it and into the 8 panels around (hairline radial breaks
  and broken rings, glints where they catch the light), and those neighbours keep their picture
  with a few dead blocks. The cockpit shell and the chest are holed on the same line, so the
  pilot sees space through it (2026-11-26).
- **Pilot**: killed when the drilled cylinder reaches the capsule: GAME OVER (range panel).
