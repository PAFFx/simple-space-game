# Damage and destruction: plan

Design in `summary.md`, numbers in `physics.md`, beam look in `beam_effects.md`, parts coming off
in `dismemberment.md`, screen and cockpit in `cockpit_and_cameras.md`. The beam comes first
because it is the main weapon and everything else hangs off its traversal. Each phase ends with
a probe or a snapshot.

## Phase 0: foundations

- [ ] `DamageLayout` / `DamageComponent` resources; `DamageModel` replacing the `SuitDamage` mock
      (keep the F4 panel and rearm working on the new model).
- [ ] Part hulls posed with the skeleton (convex hull per part mesh in bone space, generated in
      `build_rx93_scene.gd`), replacing the 12 root boxes for hit resolution.
- [ ] Part mass and volume from the mass model (`LimbReaction`) on each layout part.
- [ ] First ν layout: parts, joints, propellant tanks split into cells (none in front of the cockpit), thrusters and cameras from
      the scene, the reactor (waist, below the cockpit) and its power plant, cockpit and pilot
      capsule, weapon stores. Components hand-placed.
- [ ] Piece ids (the model's 133 loose pieces) written into a vertex attribute by the generator.
- [ ] `Tools/Damage/xray_snapshot.gd`: the layout and the loose pieces drawn over the suit, to
      check placement and name the pieces.

## Phase 1: the beam drills (the priority)

- [ ] `beam_contact`: `ProjectileManager` hands each tick's energy to the target; the front holds
      at the drill face until burn-through, then continues from the exit with what's left.
- [ ] Traversal: the cylinder through every part hull and component on the line, column mass
      from density (propellant cells at their liquid's density), existing hole channels free.
- [ ] Front-loaded energy profile in `ProjectileSpec` (τ), integrated per tick.
- [ ] `HoleSet` + `beam_hole.gdshaderinc`: wall / crater / through, lip, heat, scorch, blackbody,
      cooling; material swap on first hole; swept gouges.
- [ ] FX: contact spot, blow-back jet, droplets, blow-out cone, vapour, hole lights.
- [ ] `penetration_probe.gd` (the `physics.md` §1 table measured, and the slide-speed table
      against the drone's held barrel), `beam_hole_lab.sh` (filmstrips).
- [ ] The drone gets a layout early (shell, core, sensor, gun arm, thrusters, tank), so phase 1
      can be shot at in the range.

## Phase 2: systems react

- [ ] `SuitSystems` graph and `CapabilitySnapshot`.
- [ ] Thrusters: dead / derated / stuck gimbal / stuck valve; uncommanded forces into the FBW
      demand; coalesced capability rebuilds; FBW torque budgets refreshed.
      Probe: capability and torque after losing each thruster group (`capability_probe.gd` style).
- [ ] AMBAC joints: weak / jammed / limp; power-line cuts propagating down a limb.
- [ ] Sensors: cameras from the layout; head loss.
- [ ] Weapons: broken, a severed hand dropping its weapon.
- [ ] Damage-control MFD page (from diagnostics: NO DATA behind cut lines).
- [ ] Later: fault detection from residuals (commanded vs measured motion) when a component's
      own sensor is gone.

## Phase 3: shield and I-field

- [ ] Shield layout (plate, coating, camera, missile cells, 3 I-field charges).
- [ ] Detector, predictive trigger, field hold, leak heat, coating vapour; partial catches.
- [ ] Stores page shows charges. Probe: turret beams at the shield from several angles and
      ranges, with and without charges.

## Phase 4: cameras and the panoramic screen

- [ ] One camera list (layout) for `SensorSuite` and the screen, with the added cameras (rear
      skirts, pod tops, forearms, feet).
- [ ] Coverage mask in the screen shader (live cones, quality, no-signal pattern).
- [ ] See-through lists, `Layers.SENSOR_OPAQUE`, outlines dropped for opaque parts.
- [ ] Lens greens lit by camera state.
- [ ] `coverage_snapshot.gd`.

## Phase 5: cockpit

- [ ] Pilot capsule following the seated pilot; pilot hit → game over.
- [ ] Hull holes on cockpit and first-person chest meshes (real outside view, light shaft).
- [ ] 2D screen-health texture replacing `segment_mask`; dead / damaged / cracked rings; shock
      glitch; display controller fallback; decompression.
- [ ] `cockpit_hit_probe.gd`.

## Phase 6: kinetic and blast

- [ ] Kinetic hits: penetration (de Marre form, RHA factor, obliquity, ricochet), impulse at the
      point; vulcan spec gets projectile mass.
- [ ] Fragments for missiles and bazooka shells (sampled per part), contact products impulse,
      replacing the 90 m damage sphere.
- [ ] Limb kicks on hits to free / limp limbs.
- [ ] Probe: vulcan bursts on the rifle arm (aim error), bazooka contact (Δv, spin, recovery).

## Phase 7: secondary effects

- [ ] Propellant cells: steam burst (water) or pressure burst, venting pop, ice crystal cloud.
- [ ] Electronics arcs and bursts; weapon stores per weapon (`physics.md` §6).
- [ ] Reactor breach (fluence and blow-off on everything around, sensor blinding, the 200 m
      flash); power plant losses.

## Phase 8: parts coming off (`dismemberment.md`)

- [ ] Inner frame: struts, joint housings, actuators, cables per bone, generated; skinned.
- [ ] Loose pieces off whole: bond graph, piece-id collapse in the shader, baked flying copies.
- [ ] Shell fracture: bake, tessellate, seeds, thickness, breach records, flying plates carrying
      their holes.
- [ ] Severing at joints: baked limb, stump (frame housing, verlet cables, sparks, torn edge),
      momentum and mass model checks (like `mass_model_probe.gd free`).
- [ ] Cut faces through a part (noise surface, marched in the shader, melt near the hole).
- [ ] Structural check: sections along long parts, break below ~35%; loose pieces losing their
      attachment.
- [ ] Shards, budgets (pieces in flight, lifetime), cleanup.
- [ ] Snapshot: `dismember_lab.sh` (a beam + burst on a part at exact times, several parts).
- [ ] Limp limbs as damped passive joints.

## Phase 9: the drone, polish, sound

- [ ] Drone layout tuned: losing thrusters limits its jinks, sensor loss stops its tracking, core
      hit is a small flash.
- [ ] Sounds (`Docs/Audio`), IR signature of hot holes (sensors todo), world objects taking holes.
- [ ] Later: a weakened limb torn off by the suit's own manoeuvre.

## Decided (2026-11-25)

Pilot hit = game over. Beam energy front-loaded (τ 0.02 s): it pierces targets sliding under it
at 10–40 m/s; an even spread didn't. Reactor below the cockpit around the waist, any hit
breaches; moved in the mass model (chest density 1.6 → 1.0, pelvis 1.2 → 2.5, centre of mass
0.1 m lower, flight measured unchanged but forward 7.66 → 7.57 G). Vacuum-realistic vapour.
Water propellant (`physics.md` §5). Warheads as assumed in `physics.md` §4. The proposed cameras go in. Secondary explosions per
weapon (`physics.md` §6). The loose pieces get listed by the x-ray snapshot (phase 0).

## Open

1. **Beam profile**: front-loaded 4 GJ (current: holes, tanks stop beams, the shield buys a
   little) or even 16 GJ (cuts sliding targets apart, over-penetrates still ones, tanks and a bare
   shield don't stop it). `physics.md` §1, *Even spread with more energy*.
