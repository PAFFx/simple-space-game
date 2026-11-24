# Beam hits: dynamic melt holes and effects

The beam is the game's main weapon, and its hit has to look frightening. Nothing here is
pre-placed: **a hole is created where the beam lands, on any part, at any angle, while the beam
is drilling**, and it looks the same on a suit, the shield, the drone, a rifle or a station wall.
Only a few material numbers change how it looks (metal, composite, glass).

## The idea: holes are analytic, not geometry

A beam hole is a **cylinder**: an axis (the beam's line), a radius, and how far along that line it
has been drilled. The physics already produces that (`physics.md` §1): the traversal knows the
entry point, the direction, the drill depth each tick and where it came out. The same record
drives the shader:

```
HoleRecord (bone space of the part it's in)
  origin, axis          the beam's line
  radius_in, radius_out entry radius, exit flare (blow-out)
  s_in, s_out           where the line enters / leaves this part's hull
  s_drill               how far the drill face has got (grows each tick; = s_out when through)
  t_hit, energy         when it formed and how hot it got (for cooling and glow)
  material              metal / composite / glass (tint, melt lip, char)
```

Swept beams (the barrel swinging, a crossing target) make a gouge: a short chain of capsules
along the slot, one per tick of contact, merged when they overlap.

Every material that can be hit includes one shader include, `beam_hole.gdshaderinc`, that reads
the mesh's hole records (uniform arrays, ~16 per mesh) and does three things per fragment.

### 1. Inside the mouth: look into the hole, don't just cut it

A plain `discard` makes a hole look like a paper cutout: you see straight through a hollow
shell. Instead, for a fragment whose point lies inside a hole's mouth, the shader **casts the
view ray into the cylinder** (closed-form ray / cylinder intersection, the trick interior
mapping and parallax bullet holes use):

- The ray meets the **cylinder wall** at axial depth `s` with `s_in < s < s_drill`: shade the
  wall there as melted metal, its temperature by depth and age (hottest at the drill face),
  and write `DEPTH` so the wall sits at its true depth in the scene.
- The ray reaches the **drill face** (a crater, not through yet): shade the rounded floor at
  `s_drill`, white-hot while the beam is on it.
- The hole is **through** and the ray leaves past `s_out`: `discard`. Behind it is whatever is
  really there: the inside of the part (back faces, shaded as dark internal structure), the
  other side's exit hole, the stars, the enemy.

Seen from an angle you see the glowing bore of the hole going into the armour; seen head-on you
see through it. The far side's exit is the same record crossing that side's surface, so the
exit hole appears on its own with no second record.

### 2. Around the mouth: heat, melt lip, scorch

For fragments outside the radius, by the distance from the axis `d` and the age `t`:

| Zone | Distance | Look |
|---|---|---|
| Melt lip | r … 1.3 r | raised, rippled rim (normal perturbed by animated noise while molten, frozen when cold); emissive by temperature |
| Heat-affected zone | 1.3 r … ~3 r | glowing by temperature, then heat-tint bands as it cools (straw, bronze, blue on metals) |
| Scorch | ~3 r … ~5 r | albedo darkened, roughness up, soot streaks along the outflow direction |

Temperature comes from one function of distance, depth and age; **colour is blackbody**: a
1D gradient, ~800 K dull red → 1,100 K cherry → 1,400 K orange → 1,700 K yellow → 2,000 K+
near white, intensity ∝ T⁴ in HDR so the glow blooms. That's the part that makes it the same on
everything: hot matter glows this way whatever it is.

### 3. Back faces, breaches and cut faces

Materials with holes render both faces (`cull_disabled`): back faces seen through a hole are the
inside of the shell, shaded dark and lit only by the hole's own glow; mostly what shows through is
the inner frame (`dismemberment.md`). The same include handles the other records:

- **Breaches** (panels blown off): discard the blown region, a torn and scorched edge band
  around it.
- **Cut surfaces** (a part broken through a hole): discard past a noise-displaced surface; where
  the view ray goes through the opening it is marched a few steps against that surface and the
  hit is drawn as cut metal with `DEPTH` written: melted and dripping near the beam's hole, torn
  farther out, cooling to dark uneven metal. Not a flat cap.
- **Removed loose pieces**: collapsed in the vertex shader by piece id.

## Cooling (vacuum makes it last)

In vacuum nothing carries heat away except radiation and conduction into the rest of the part.
A 1 cm armour edge at 1,800 K radiating from both faces takes **~3 minutes** to fall to a dull
900 K by radiation alone; conduction into the surrounding plate makes it faster. So:

- Holes stay visibly red for **tens of seconds** [tune: 20–60 s to dark], edges first, the bore
  last. A damaged suit carries its wounds glowing through the fight, which is a strong visual and
  later an IR signature for sensors.
- Temperature `T(t)` follows the radiative law (`dT/dt ∝ −T⁴`) with a conduction term, evaluated in
  the shader from `t_hit` and `energy`: no per-frame CPU work.

## The sequence on screen

| Time from contact | What happens |
|---|---|
| 0 | the beam front touches: a blinding white contact spot, the beam's own impact flash; a **vapour jet blows back along the beam** toward the shooter; molten droplets spray out sideways across the surface |
| 0 – burn-through (a few ms on a limb, 10–30 ms on the body: a frame or two) | the beam's bright head drills; the front holds at the plate only that long (front-loaded energy, `physics.md` §1); the rim boils yellow-white; light pours out of the bore |
| internal components reached | each one on the line fires its secondary after a short delay: arcs crawling out of the hole and seams (electronics), a white burst and panels blown off (tank cell), a sharp flash (E-pac) |
| burn-through → end of the pour (0.15 s) | **blow-out on the far side**: a cone of molten spray and vapour, bright chunks, the exit flared wider than the entry; the beam continues from the exit, dimmer for the energy it spent. The tail keeps pouring through the fresh hole for the rest of the pour, the hole widening and the exit spray lasting as long: this is what reads as the beam forcing its way through |
| after the pour | droplets fly off on their own paths; vapour thins within a second; the hole cools through yellow, orange, red to dark over tens of seconds |

**Droplets need no fake gravity**: emitted in world space with the suit's velocity plus their
ejection speed, they're left behind when the suit boosts, so a hole on a manoeuvring suit
streams molten metal opposite to its thrust, on its own.

## Effects inventory

| Effect | Implementation |
|---|---|
| Hole, lip, heat, scorch | `beam_hole.gdshaderinc` on the hit mesh's material |
| Contact spot, blow-back jet, blow-out cone | pooled `GPUParticles3D` (world space), HDR emissive, short life |
| Molten droplets | pooled `GPUParticles3D`, stretched by velocity, colour over life from the blackbody gradient (they cool too) |
| Vapour | soft billboards, fast expansion and fade (vacuum) |
| Arcs | short-lived emissive line strips jittered between points around the hole and nearby seams |
| Hole light | a small pool (~4) of `OmniLight3D`s on the hottest holes, energy from their temperature, so a fresh hole lights the armour around it and the inside of the part |
| Cockpit | beam glow already lights the cockpit (`CockpitBeamGlow`); a hull hole also lets a shaft of real light in (`cockpit_and_cameras.md`) |
| Sound | later: the drilling roar through the hull (own suit), crackle of arcs, the blow-out thump (`Docs/Audio`) |

## Godot implementation notes

- **Only damaged meshes pay.** A mesh keeps its imported material until its first hole; then it
  switches to a copy that adds the include. The copy has to reproduce the original
  `StandardMaterial3D`: generate it offline in the scene generator (`build_rx93_scene.gd`),
  the same way the editor's "Convert to ShaderMaterial" does, and add the include (check the
  API in the Godot version used; a hand-written uber shader with the few features the suit uses
  is the fallback).
- **Per-mesh records.** Each damaged `MeshInstance3D` gets its own material instance, so hole
  arrays are per mesh (`instance uniform` can't hold arrays). `HoleSet` keeps records in bone
  space and, for meshes that have any, uploads them in the mesh's space once per frame
  (the parts are near-rigid on one bone: one transform per mesh).
- **Skinning.** `VERTEX` arrives already skinned in model space, so the fragment works in the
  mesh's space; nothing per vertex.
- **Depth.** Writing `DEPTH` turns off early depth tests for that material: acceptable on the
  few damaged meshes.
- **Cost.** A loop over ≤16 records, each a distance test and, inside a mouth, one ray / cylinder
  solve. Measure with `Tools/Profiling/frame_phases.gd` against a suit with 16 holes.
- **Other meshes.** The drone (built from code), the shield and the rifle use the same include;
  world objects (station, debris) can later.

## Probes and snapshots (planned, `Tools/Damage/`)

- `beam_hole_lab.sh <out_dir>`: like `beam_fx_lab.sh`, one beam onto a test plate / part at exact
  sim times (contact, mid-drill, through, 1 s, 10 s, 60 s) and angles (0°, 45°, 70°), tiled.
- `xray_snapshot.gd`: the suit with its layout's parts and components drawn as boxes, a beam's
  path and what it hit, War Thunder-style.
- `penetration_probe.gd`: fire the rifle at each part from several directions; print column mass,
  burn-through time, energy left, components hit (the table in `physics.md` §1, measured).
