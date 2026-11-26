# Mass model

`LimbReaction` (`Entities/Vehicles/Components/LimbReaction/`) holds the suit's mass model:
every part of the model with its own mass, propellant tanks inside some of them, and the
equipment the parts carry. From the final pose each physics tick it gives:

- **Reaction torque** of every moving part (Newton's third law), now including the waist
  and legs, measured in the body frame. AMBAC joints on those bones are "measured": AMBAC
  plans with the inertia the mass model gives them (refreshed as the tanks drain), and the
  torque the body feels comes from the measured motion.
- **Centre of mass and inertia** of the whole suit in its current pose and fill, sent to
  the physics body when they change (`drive_body_mass`). The hull is moved by the opposite of
  the centre's shift, and its spin rescaled for the new inertia, so momentum is conserved:
  swinging the legs forward pushes the torso back.

## Where the masses come from

`Tools/Godot/measure_part_volumes.gd` measures each skinned part's solid volume: the mesh
is rasterised into 0.2 m voxels, and a voxel counts as inside when there is surface on both
sides of it along at least two of the three axes (a flood fill from outside leaked through
the open cockpit tunnel and seams). The ν comes to 487 m³.

`Tools/Godot/build_rx93_scene.gd` (`PARTS`) splits the official dry weight (27.9 t) by
volume × a density factor for what's inside each part, and the propellant (25.2 t, filling
the official 63.0 t max weight together with the equipment) by volume × a tank share:

| Part | Volume m³ | Density | Tank share | Dry kg | Propellant kg |
|---|---|---|---|---|---|
| Chest (cockpit, frame) | 59.4 | 1.0 | 0.2 | 3,330 | 4,520 |
| Waist (spine) | 5.5 | 1.4 | — | 430 | — |
| Pelvis (the reactor, ~2 t) | 27.9 | 2.5 | 0.4 | 3,910 | 4,240 |
| Head | 10.2 | 1.0 | — | 570 | — |
| Backpack | 20.8 | 1.3 | 0.6 | 1,520 | 4,740 |
| Main pods (engines) | 12.2 / 11.5 | 1.6 | — | 1,100 / 1,030 | — |
| Main nozzle cups (4) | 0.7 each | 1.6 | — | 63–65 each | — |
| Shoulder armour | 17.3 / 17.5 | 0.8 | — | 780 / 790 | — |
| Upper arms | 6.3 | 1.2 | — | 430 | — |
| Forearms | 12.7 / 15.1 | 1.0 | — | 710 / 850 | — |
| Hands | 2.8 | 1.3 | — | 200 | — |
| Front skirts | 5.7 / 6.0 | 0.5 | 0.4 | 160 / 170 | 860 / 910 |
| Side skirts | 3.3 | 0.5 | 0.3 | 90 | 370–380 |
| Rear skirts | 8.0 | 0.5 | 0.5 | 220 | 1,500–1,520 |
| Thighs | 22.9 | 1.0 | 0.15 | 1,280 | 1,300 |
| Shins | 46.5 | 0.9 | 0.1 | 2,350 | 1,770 |
| Feet (big, mostly hollow) | 32.9 | 0.7 | — | 1,290 | — |
| Calf plates | 8.3 | 0.6 | — | 280 | — |

Right / left where they differ; pairs are per side. Equipment adds its own mass on the bone
that carries it: beam rifle 2.6 t (right hand), shield 3.8 t (left forearm), hyper bazooka
3.2 t, beam saber 0.3 t and fin funnels 6.0 t (backpack). Tanks drain together, in
proportion to their size.

## The ν, full and empty

From `Tools/Flight/mass_model_probe.gd -- report` (rest pose):

| | Mass | Centre of mass (x, y, z) m | Inertia (xx, yy, zz) 10⁶ kg·m² |
|---|---|---|---|
| Before (fixed) | 69.0 t | (0, 14.26, 0.80) | 3.68, 0.73, 3.70 (from the collision boxes) |
| Full | 69.0 t | (−0.60, 13.10, 0.74) | 2.62, 1.42, 2.98 |
| Empty | 43.8 t | (−0.97, 13.16, 0.86) | 2.01, 1.18, 2.32 |
| Full, reactor in the pelvis (2026-11-25, current) | 69.0 t | (−0.46, 12.98, 1.12) | 2.42, 1.11, 2.67 |
| Empty, reactor in the pelvis | 43.8 t | (−0.75, 12.95, 1.48) | 1.78, 0.86, 2.03 |

- **The reactor moved** (2026-11-25, `Docs/Damage/`): it sits below the cockpit around the
  waist, so ~2 t of dry mass went from the chest (density 1.6 → 1.0) to the pelvis (1.2 → 2.5).
  The centre of mass is 0.10 m lower full, 0.17 m empty (measured against the rows before it,
  which had already drifted from the first table with later loadout changes). Flight barely
  changes: forward capability 7.66 → 7.57 G, `fbw_probe full_fwd` t90 0.67 → 0.73 s and
  31.9 → 31.3 m in 1 s; boost forward, back, up and the clean torque the same.
- The centre of mass is ~1.2 m lower than the old guess: the legs are 45% of the model's
  volume (big shins and feet), ~8.8 t per leg full. It sits 0.6 m left of the centreline
  (shield on the left forearm, fin funnels on the left of the backpack), 1.0 m empty.
- The tanks are mostly around the torso, so the centre barely climbs as they drain (13.10 →
  13.16 m). A first layout with 0.3 of the thighs and shins as tanks (14.4 t of propellant in
  the legs) put it at 12.07 m, ~2 m under the backpack mains' line of thrust: every forward
  push pitched the suit hard nose-down.
- Yaw inertia is about twice what the collision boxes gave (1.42 vs 0.73 × 10⁶ kg·m²), pitch
  and roll ~20–30% lower.

AMBAC joint inertias (full) now come from the parts they swing: hip ~3.8e5 kg·m² (was a
guessed 1.6e5), knee ~1.4e5 (4.5e4), waist yaw / pitch ~1.05e6 / 1.59e6 (1.2e5 / 1.5e5),
right shoulder with the rifle ~2.0e5.

### Joint torque ratings

AMBAC joints were limited by angular acceleration only. With the waist's inertia ten times the
old guess, the same acceleration meant torques no actuator gives, and AMBAC's measured reaction
kicked the body around (braking while yawing: 1.0 G of off-demand force, from 0.2). Legs and
waist now have a torque rating (`AmbacJoint.max_torque`) equal to the peak torque they were
tuned with (fallback inertia × acceleration limit), and acceleration is torque / inertia: heavy
limbs swing slower on the same actuator. The arms keep their acceleration limit.

## Checks

`Tools/Flight/mass_model_probe.gd`:

- `report`: the table above.
- `free`: FCS off, legs swing through the climb and strafe stances while the rifle aims.
  World centre of mass drift 0.0000 m (the hull moves instead), angular momentum drift
  ~0.04% of a 10°/s roll.
- `drain`: tanks drained from full to empty over 4 s with no thrust: no jump of the
  centre of mass (0.0000 m).

The force capability map (torque arms about the centre of mass) is rebuilt once the mass
model first places the centre, and again whenever it moves more than 0.1 m from where the map
was built.
