# Damage and destruction: design

Status: **first pass built** (2026-11-25, branch `feat/damage-design`; see *As built* at the end).
The old `SuitDamage` mock (hit points per box) is gone. Numbers and their derivations are in
`physics.md`, the beam's look in `beam_effects.md`, parts and limbs coming off in
`dismemberment.md`, the panoramic screen and cockpit in `cockpit_and_cameras.md`, the build order
in `todo.md`; the play-test fix list is `fixes.md`.

Decided with the user (2026-11-25): pilot hit = game over; beam energy front-loaded so it
pierces targets sliding under it at 10–40 m/s (`physics.md` §1); the reactor sits below the
cockpit around the waist (moved in the mass model) and any hit on it breaches; vacuum-realistic
vapour (no billowing smoke); warheads as assumed; the proposed extra cameras go in; secondary
explosions sized per weapon; propellant water (`physics.md` §5; hydrogen didn't fit).

## Goal

Damage that follows from what physically happens, not from scripted part swaps:

- A beam **drills**: it delivers energy over time, melts and vaporises whatever is on its line, and
  comes out the other side if it has energy left. Where it lands is computed, not pre-modelled: a
  hole can appear anywhere on any part, at any angle, and it glows, drips and cools.
- What it passes through **matters**: a cockpit on the line kills the pilot, a reactor on the line
  breaches, a propellant cell on the line stops the beam and bursts, a camera on the line goes dark, an actuator
  on the line leaves the limb limp, a joint on the line severs it.
- The suit **knows what it has lost** and every system adapts: the thrust allocator and capability
  map drop or derate thrusters, AMBAC stops using dead joints, the sensors lose their cameras, the
  panoramic screen goes dark where no live camera sees, weapons with a dead camera stop being
  see-through.
- Bullets and blasts push and shake the suit by their real momentum, which turns out to be small
  for bullets and moderate for close blasts (`physics.md`); their damage is to what they can
  actually penetrate: sensors, nozzles, joints, cameras.

## Principles

1. **One damage pipeline for everything.** Suits, the target drone, equipment (shield, rifle,
   funnels) and later world objects share one `DamageModel` with a per-vehicle layout. The drone is
   just a small layout (`todo.md` phase 9).
2. **Space, not geometry.** Damage is resolved against volumes in bone space: part hulls (posed
   with the skeleton) and components inside them (boxes / capsules). The render meshes are never
   cut; holes are drawn by a shader from the same hole records the physics uses.
3. **Energy and momentum are conserved.** Beam energy is spent per kilogram removed; bullets and
   blasts hand over their momentum at the hit point (`RigidBody3D.apply_impulse`); severed parts
   leave with the momentum they had.
4. **Damage changes capabilities, systems read capabilities.** The damage model never reaches into
   the flight computer's internals. It publishes a capability snapshot (which thrusters, joints,
   cameras, weapons, power) and the systems rebuild from it.
5. **What the pilot learns comes through sensors** (as in the rest of the sim): the damage page
   and warnings show what the suit's diagnostics report. A component behind a cut data or power
   line reports "NO DATA", not "OK"; a derated thruster is first noticed by its chamber pressure
   (phase 2: from the motion that doesn't match the command).

## Architecture

```
ProjectileManager ── beam_contact(BeamContact) / apply_hit(HitEvent) ──▶ DamageModel (per vehicle)
     ▲  energy left, exit point                                    │ traverse the layout along the
     └──────────────────────────────────────────────────────────── │ hit (ray / cylinder / sphere)
                                                                    ▼
                                    DamageLayout (Resource): parts, components, links
                                                                    │ component states change
                                                                    ▼
                                    SuitSystems: graph evaluation (power, propellant, actuators,
                                    data, structure) → CapabilitySnapshot + events
          ┌──────────────┬──────────────┬─────────────┬─────────────┼──────────────┬──────────────┐
   FlightComputer   AmbacController  LimbReaction  SensorSuite   SensorHead /  FireControl /   Effects:
   allocator,       joint states     mass model,   cameras,      Panoramic     weapons,        HoleSet (shader),
   capability map,  (ok / weak /     severed       tracking      Screen        I-field         FX, lights,
   uncommanded      jammed / limp)   parts                       coverage,                     Detacher
   forces                                                        opaque parts,                 (severed parts)
                                                                 cockpit holes
```

### Hit interface (replaces `apply_hit(damage, at, direction, source)`)

| Kind | Sent by | Carries | Resolved as |
|---|---|---|---|
| Beam contact | `ProjectileManager._step_beam`, every tick the beam touches the target | entry point, direction, radius, energy arriving this tick (J), shot id | cylinder drilled along the ray through every part and component, energy spent per kg; returns energy left and the exit point |
| Kinetic | bullets, bazooka shells (contact) | point, velocity relative to the target, projectile mass and calibre | penetration against the armour there (`physics.md` de Marre form), impulse at the point, component hit if penetrated |
| Fragments | missile / shell bursts | burst point, fragment count, mass, speed | expected hits per part from its solid angle, sampled (Poisson), each one a small kinetic hit |
| Blast / flash | contact bursts, reactor breach, e-pack breach | point, energy, products mass | impulse from detonation products (falls as 1/R²) and radiant fluence (1/R²) per part |

The beam is the important change: today it stops on the first collider and "splashes". New
behaviour: the target answers each tick how much of that tick's energy it absorbed. The beam front
stays at the drill face (a few ms on a limb, 10–30 ms on the body) until the target says it is through,
then the line continues from the exit point with what is left, so it can hit the next thing
(the arm behind the shield, the suit behind the drone).

### DamageLayout (data)

Authored per vehicle, generated where possible:

- **Parts**: one per rigid section (head, chest, waist, pelvis, backpack, pods, shoulder armour,
  upper arms, forearms, hands, skirts, thighs, shins, feet, calf plates; equipment as their own
  parts). Each has a convex hull in bone space (generated from its mesh, like `MsShield` already
  does), its parent part and the joint between them, an armour shell (thickness, RHA-equivalent
  factor, anti-beam coating), and its **mass and volume from the mass model** (`LimbReaction`): a
  beam path's column mass is `mean density × path length × area`, so no separate armour HP table.
- **Components** inside parts: box or capsule in bone space, kind, mass, and what it links to.

| Kind | Examples | States |
|---|---|---|
| Structure | each part's frame | ok → weakened → broken (children severed) |
| Joint actuator | one per AMBAC joint / animated DOF | ok, weak (torque × k), jammed (locked where it is), limp (no drive) |
| Power line | reactor → torso bus → limb buses | ok, cut (everything downstream unpowered) |
| Propellant line / tank cell | tanks from the mass model, split into cells; feed lines to thruster groups | ok, leaking (venting force), empty, cut |
| Thruster | nozzle, gimbal actuator, valve per `Thruster` | ok, derated (max thrust × k), gimbal stuck (at its current angle), valve stuck open (uncommanded thrust), dead |
| Camera / sensor | eyes, forehead telescope, body cameras, rangefinder, equipment cameras | ok, degraded (noise ×k), dead |
| Weapon internals | rifle barrel / condenser, e-pack, vulcan magazine, missile cells, I-field charges | ok, dead, breached (secondary explosion) |
| Reactor and power plant | the core (waist, below the cockpit); lines, conditioning, coolant around it | core: ok or **breached** (any hit, `physics.md` §7); plant: ok, reduced (power ×k), lost (batteries only) |
| Cockpit | screen panels, hull, pilot capsule | screen damage map, holes, **pilot hit = game over** |

### SuitSystems (graph evaluation)

After every damage event (never per frame) the systems graph is evaluated by reachability:

- A **thruster works** if its nozzle and valve are intact, a propellant path reaches a non-empty
  tank cell, and its part is powered and still attached.
- A **joint is driven** if its actuator is intact and its limb bus is powered; a cut line upstream
  (a beam through the shoulder) leaves the elbow and wrist limp even though they weren't touched.
- A **camera is live** if it is intact, powered, and its data line reaches the cockpit.
- A **part is attached** if every structure link up to the chest holds. A broken link severs the
  part and everything beyond it (`Detacher`).
- The **reactor** feeds everything; with its power plant lost the suit is on batteries (minutes
  of actuators and cameras, no thrust worth having: the thrusters' jet power comes from the
  reactor, `Docs/FlightControl/thrust_sizing.md`).

It publishes a `CapabilitySnapshot` and per-change signals (`thruster_changed`, `joint_changed`,
`camera_changed`, `part_severed`, `weapon_changed`, `pilot_killed`, `reactor_breached`).

### Consumers

| System | What it does with the snapshot |
|---|---|
| `FlightComputer` / allocator | dead thrusters `enabled = false`; derated `max_thrust × k`; stuck gimbal: cone limit 0 around the stuck aim; stuck-open valve and tank venting: a **known uncommanded force** added to the demand so the allocator cancels it. Coalesced `rebuild_capability_map_async()` (one rebuild after a burst of changes, not one per hit). |
| FBW torque budgets | `FlightState.max_torque` / AMBAC capacity refreshed from the snapshot, so the FBW stops asking for authority the suit no longer has |
| `AmbacController` | weak: `max_torque × k`; jammed or limp: the joint leaves the allocation (weight 0); jammed joints become part of the rigid body; limp ones swing passively (phase 8: a damped 1-DOF pendulum driven by the hull's acceleration) |
| `LimbReaction` (mass model) | a severed part, its tanks and its equipment leave the mass model at once; centre of mass and inertia jump, the hull keeps its momentum (same conservation path as today's pose changes) |
| `SensorSuite` | the camera list comes from the layout; dead cameras drop out of tracking; head gone = no main camera, rangefinder or stereo: body-camera tracks only |
| Panoramic screen | coverage from live cameras, opaque parts whose see-through camera died, cockpit holes (`cockpit_and_cameras.md`) |
| `FireControl` / `MsWeapon` | broken weapons; a severed hand drops what it held (a free body); a dead weapon camera removes its see-through |
| HUD / MFD | a damage-control page: suit outline, part states, thrusters, cameras, power, propellant per cell, from diagnostics |

## Severing and blown-off parts

The look is in `dismemberment.md`: a generic inner frame under the armour, the model's own loose
pieces flying off whole, runtime shell fracture for big plates, severing at joints with stumps
and torn cables, shader-drawn cut faces through a part, and a structural check so nothing is left
floating on a sliver. On the systems side, a broken structure link or a destroyed joint detaches
the part and its children:

1. They become a rigid body with the pose frozen at that instant, mass and inertia from the mass
   model, velocity = the velocity of their centre of mass on the suit (`v + ω × r`), plus the
   separation push.
2. The suit's mass model drops them in the same tick (conserving momentum), thrusters and tanks
   on them are gone, capability is rebuilt.

## Shield and I-field

The shield is a part with its own layout: plate, anti-beam coating (consumed by ablation), its
camera, its missile cells, and three large E-pac **I-field charges**.

- **Trigger**, through a sensor (sim rule): a detector ring on the shield face sees the glowing
  beam front entering a short shell (~20 m). At 3000 m/s that is ~7 ms of warning. The field
  needs `latency + rise_time` (assumed 2 + 3 ms) to be up. In the sim (60 Hz, the front moves
  50 m a tick) the trigger is predictive: in the tick where the front will cross the shell, the
  arrival time at the shield is solved; if the field is up before arrival it catches the whole
  beam, if it comes up mid-pour it cuts the rest off (partial protection, a smaller hole).
- **Active**: one charge, ~0.2 s of field (covers a whole 0.15 s pour and a second beam arriving
  in that window). The beam disperses at the field boundary into a flash and scattered sparks;
  ~5–10% of its energy leaks onto the shield face as heat, spread over the field's footprint:
  the anti-beam coating boils off as the smoke cloud (the realistic smoke source here).
- **Without a charge** (or a beam from outside the detector's cone, at a grazing angle past the
  field bubble): the beam drills the shield like anything else, ~20 ms, and goes on with about a
  third of its energy, enough to hole the arm behind it (`physics.md`).
- Charges can be hit: a breached I-field E-pac is a small secondary explosion on the shield.
- The defending pilot sees the charges on the stores page; the field is automatic.

## Secondary effects (what a hit sets off)

| Hit | Physically | Look |
|---|---|---|
| Electronics, actuators, cables | capacitor and battery banks discharging, insulation vaporising | arcs crackling for 0.1–0.5 s, then a small flash and a puff of vapour that thins out fast (vacuum) |
| Propellant cell (water) | the beam stops in it and flashes it to steam; the closed cell bursts (no fire: no oxygen); a hole vents (`physics.md` §5) | a violent burst, armour panels blown off (`dismemberment.md`), a glittering cloud of ice crystals gone in a few seconds, a sharp push (~0.4 MN for a few hundredths of a second) |
| Weapon stores | breach, sized per weapon (`physics.md` §6) | E-pacs: a sharp small explosion; bazooka shells and missiles: their HE and fragments; vulcan drums: rounds cooking off over 1–3 s |
| Reactor (waist, below the cockpit) | any hit breaches: plasma and field energy released mostly as radiation | a bright clean sphere ~200 m, lethal inside ~60 m, sensors blinded to ~400 m |
| Power systems around the reactor | lines, conditioning, coolant hit, the core not | power lost or reduced: thrusters dead, cameras on batteries, the suit drifts |
| Cockpit | hull holes, screen sections dead, decompression | the pilot sees outside through the hole; pilot on the beam's line = game over |

Vapour, not smoke (decided): in vacuum a cloud expands and thins in a fraction of a second; it
doesn't billow or trail unless something keeps venting.

## Files (planned)

```
Entities/Vehicles/Components/Damage/
  damage_model.gd          hits in, traversal, component states, events
  damage_layout.gd         Resource: parts, hulls, components, links
  damage_component.gd      Resource: one component (kind, volume, mass, links, state rules)
  hit_traversal.gd         ray / cylinder / sphere against hulls and components, existing holes
  suit_systems.gd          graph evaluation → CapabilitySnapshot, signals
  capability_snapshot.gd
  hole_set.gd              hole and cut records per mesh, shader uniforms, cooling
  detacher.gd              severed parts → free bodies (baked pose), stumps, cables
  shell_fracture.gd        runtime fracture of a part's shell around a burst
  structural_check.gd      sections along long parts; breaks a part where too little is left
  damage_fx.gd             pooled particles, arcs, vapour, ice spray, shards, lights
  Shader/beam_hole.gdshaderinc   holes, breaches, cut faces, piece removal
Tools/Blender/build_inner_frame.py (or the scene generator): the generic inner frame
Entities/Equipment/Shield/i_field.gd
Entities/Vehicles/Cockpits/Components/PanoramicDisplay/camera_coverage.gd
Tools/Damage/              probes and snapshots (todo.md)
```

## Limitations

- **Render meshes are hollow shells.** Inside a hole the walls and crater floor are drawn
  analytically by the shader; past them is the generic inner frame (`dismemberment.md`), not
  modelled machinery.
- **Holes per mesh are capped.** The shader keeps each mesh's holes in a fixed-size array
  (~16, could be 32) and loops over it per pixel. That is per mesh: the ν has 35 (head, chest,
  each forearm, each shin…), so ~500 for the suit, and a part takes a few holes before it's
  gone. Past the cap, overlapping cold holes merge and the oldest drop.
- **Skinned parts near joints**: a hole is stored in one bone's space; at a bending joint the
  part of a hole on the other bone's vertices slides a little.
- **Collision shapes don't get holes.** The traversal subtracts existing hole channels, so a
  second shot through the same hole passes, but physics contacts (none today) would not.
- **Cut faces have no silhouette of their own**: drawn by the shader (uneven, melted, cooling
  dark), right from any angle, but a cut seen exactly edge-on shows the shell's edge.
- **Hit volumes must follow the pose.** Today's 12 root boxes don't; phase 0 replaces them.
- **Constants are estimates.** Ablation energy, coupling, the I-field's timing and the reactor
  yield are chosen to be physically plausible and to give the outcomes the game wants; each is
  one number to tune, listed in `physics.md`.
- **Cost**: traversal runs only on hits (GDScript is fine; C++ in `Native/` if a hit storm
  shows up in `Tools/Profiling`). The hole shader costs only on damaged meshes: undamaged ones
  keep their original material.

## As built (first pass, 2026-11-25)

| File | What it does |
|---|---|
| `Entities/Vehicles/Components/Damage/damage_model.gd` | `DamageModel`: parts (a convex hull per part mesh, an `Area3D` on `Layers.PHYS_DAMAGE` riding its bone), components, beam drilling, bursts, the reactor, severing, cameras, repair |
| `.../Damage/hole_set.gd` | `HoleSet`: hole records per mesh, the material swap on the first hole, per-frame upload |
| `.../Damage/Shader/beam_hole.gdshaderinc`, `damage_surface.gdshader` | the holes as drawn (`beam_effects.md`) |
| `.../Damage/damage_fx.gd` | `DamageFx`: spray, vapour, ice glints, arcs, hole lights, stumps, the I-field and reactor flashes |
| `Entities/Projectiles/projectile_manager.gd` | `BeamContact`, `_drill`: energy per tick to targets with `beam_contact`; `apply_impact` for bullets and bursts |
| `Entities/Equipment/Shield/shield.gd` | I-field charges, plate drilling, its camera, breaking off |
| `Entities/Environment/Space/TargetDrone/target_drone.gd` | the drone drills too: shell, interior, core (breach), gun arm, loss of control |
| `.../PanoramicDisplay/panoramic_screen.gd` + shader | camera coverage, screen holes |
| `Stages/Components/RangeControl/range_control.gd` | F4 panel: parts left, thrusters and cameras out, I-field charges, last event; 0 rearms (repairs and refuels everything) |
| `Tools/Damage/penetration_probe.gd` | headless checks: shots at each part (timings, holes, events), shield, drone, vulcan impulse, sever + repair |
| `Tools/Damage/damage_snapshot.gd` | windowed renders: `hole,cool,forearm,shin,chest,thigh,sever,shield,bareshield,drone,reactor,screen` |

Renders (`damage_snapshot.gd`): a through-hole in the shin, drilling then cooling (entry face
0.5 s, 3 s, 20 s, 45 s; exit face 3 s, 20 s):

![hole cooling](images/hole_cooling.png)

A forearm shot off: the beam, the piece tumbling away, the elbow's socket and frame stub, the piece:

![sever](images/sever.png)

The screen from the seat: head camera lost (body cameras' coarser picture); rear cameras lost
(no signal behind); shield camera lost (the shield shows); a beam through the cockpit's edge:

![screen damage](images/screen_damage.png)

Measured (`penetration_probe.gd`, rifle 4 GJ front-loaded, 300 m):

| Shot | Burn-through | What happened |
|---|---|---|
| Head | 33 ms, through | head 60% left, backpack holed behind it, main camera and vulcans out |
| Cockpit | stops in the chest's water cells behind the cockpit | pilot killed (GAME OVER), the cells' steam burst takes the chest vents and mains |
| Waist | 67 ms, through | reactor breached: 200 m flash, the suit comes apart |
| Right forearm | 17 ms, through | forearm severed (29% left), the stowed rifle behind it hit, its E-pac goes off |
| Thigh / shin | stopped in their water cells | steam burst, the leg severed at the thigh / knee with all its thrusters |
| Shield, charged | field up 2.5 m out | beam taken, a charge used, a dull scorch |
| Shield, no charge | through | plate 70% left, the beam goes on into what is behind |
| Drone core / off-centre | 33 / 17 ms | breach and gone / holed, 40% chance its control is cut |
| 1 s of both vulcans on the head | | 0.84 m/s, 10.8°/s on 69 t (FCS off) |
| Sever a thigh, repair | | 28 → 23 thrusters, 69.0 → 60.7 t; repair puts all back |

Differences from the design above:

- **Hulls are convex** (from each part's mesh): concave parts (the chest's cockpit tunnel)
  are filled. Section loss uses the hull's footprint across the bone (×0.785); limbs break below
  35% left, blocky parts (head, backpack, shoulders, skirts) only at 0%.
- **Tank cells** are boxes generated in each part (4 per tank): the chest's behind the cockpit,
  the pelvis's below the reactor. Water stops beams; a cell that takes a beam steam-bursts ~30 ms
  later with the energy it absorbed (blow-off radius 0.0025·E^⅓ m).
- **Severing**: a limb holed or torn away from its joint breaks **through the damage**: a cut
  plane across the bone at the last hole (or where a burst tore it), bumpy (±0.2 m noise), drawn
  by the hole shader (the stub discards beyond it, the piece before it; back faces seen through
  the opening draw the cut face at the plane, hot and cooling). The stub's hull is trimmed, the
  mass and propellant beyond the cut, thrusters and cameras there go with the piece. Near the
  joint (first 18% of the part) it breaks at the joint. Both ends get a generated frame stub
  (joint drum, snapped struts glowing at the ends, torn cables sparking ~20 s). No inner frame
  under intact armour yet (`dismemberment.md` layer 1), no loose pieces (layer 2).
- **Panels** (layer 3, built 2026-11-26): a burst (≥ 5 MJ) tears armour off the 3 nearest
  parts, one per physics tick: the real skin around the burst's outward line (outermost
  outward-facing triangles of the posed mesh, split to ~0.45 m, inside a ragged circle of
  r = 0.0025·E^⅓, ≤ 0.45 × the part's width) is grouped into 2–3 plates by nearest seed,
  given 0.14 m of thickness and a hot torn edge, and thrown off (8–120 m/s); the part gets a
  short through-hole there (the opening and the plate's torn edge). The hull's surface wasn't
  the mesh's (the backpack's skin sits 0.8 m inside its hull), so the cut follows the mesh.
- **Old holes are free**: a beam's column, step by step, leaves out the share of its disc
  inside a part's existing channels; a part crossed only through old channels gets no new hole
  and loses no more section (`penetration_probe twice`: the second shot down a head's channel
  goes straight through, the head stays at 59%).
- **Cockpit**: a beam through the cockpit sphere holes the screen (as before) and every plain
  cockpit mesh on its line (through-holes in their own frame, so they ride the gimbal); with the
  chest holed by the drill the pilot sees space through it (`damage_snapshot cockpit`: a beam
  1.2 m in front of the pilot, the station seen through the hole, the pilot alive).
- **Thruster hits**: 45% dead, 20% derated to 35–70%, 20% nozzle stuck at rest, 15% valve stuck
  open at 15–45% (it fires on its own, burning propellant; `enabled` off so the allocator works
  around it). A main stuck open at 40%: FCS on, the suit holds its attitude (0.3°) and drifts
  2.5 m/s in 2 s; FCS off it spins up to 112°/s. Parts torn off take their thrusters dead.
- **Venting**: a burst cell empties through the hole at 2·Cd·P·A ≈ 0.41 MN for cell mass ×
  25 m/s ÷ that (~0.07 s), pushing from where the line meets the hull, then the cut feed line
  leaks 4 kN for 15 s; both show as icy jets. A backpack cell: 0.8 m/s and 14°/s (FCS off).
- **Minovsky lines** (2026-11-26): the reactor's Minovsky particles run through the whole body
  as the high-power hydraulics, so every part a beam goes through (and a drill face that stops
  inside a part after taking > 30% of it) ruptures its lines 0.03–0.15 s later: a burst of
  20–60 MJ × the part's mass (fire, arcs, the plate torn off nearest the hole, 1 panel max),
  then smoke leaking from the exit hole for 5–9 s. Not after a reactor breach or once the part
  is severed.
- **Pilot**: a capsule (torso and legs) on the cockpit camera; any drilled cylinder that
  reaches it kills (no extra margin yet); the view goes outside (ViewSwitcher), no text.
- **Reactor breach**: flash and fluence on everything in the `damageable` group; the suit is
  baked into glowing pieces flung out at 40–160 m/s, its hull stops being a body until repair.
- **Probes that count hits** turn damage off (`DamageModel.enabled = false`): weapons, dodge,
  fair-fight. Drones with hit points ≥ 1e8 can't be destroyed (probes already used 1e9+).
- **Damage page** (`CockpitDisplays/damage_page.gd`): the left display flips to it for 10 s after
  each new damage, P holds it. The suit from the front, parts filled green / amber / red by the
  section left (gone: dashed), thrusters as dots (red dead, amber derated or stuck nozzle,
  flashing red valve stuck open), cameras as squares; reactor, pilot, I-field charges, counts,
  the last 7 events.
- **Camera lights** (2026-11-27): every camera sits on a `CameraMarker` in the suit scene
  (`Cameras/Attach_<bone>/<name>`): its position, its facing (−Z, turning with the bone) and its
  light. Move them in the editor; `build_rx93_scene.gd` keeps them when it regenerates. The
  painted sensors (eyes 8, left chest 8, forehead 3, back of the head 3) make their own green
  paint glow (`sensor_glow.gdshader`, an overlay on the Head / Chest mesh, by atlas UV rect);
  the other cameras show nothing in the game (a green dot marks them in the editor only).
  Dark once the camera is shot out.
  The dots were placed by hand from pictures with `Tools/Damage/camera_dot_tool.gd` (one view
  per camera with the thrusters marked; a picked pixel is cast onto the posed skin): on the
  armour, ≥ 1.4 m from any nozzle, clear of the stowed rifle, bazooka and shield.
- **Missile fragments**: the strikes that land show as spark splashes on the facing parts.
- **Not built yet**: limp joints swinging (a hit joint is taken out of AMBAC, held), fault
  detection from motion, vulcan pits, inner frame under intact armour, loose model pieces
  flying off whole.

### Frame cost (2026-11-26, `Tools/Profiling/combat_bench.gd`, windowed, 6 drones)

| | Frame |
|---|---|
| `main` (no damage system) | 2.48–2.66 ms |
| branch, suit intact | 2.64–2.70 ms |
| branch, 24 holes on 12 parts, head camera out, 2 screen holes (`damage=1`) | 2.78 ms |

The first measurement had the branch 0.5 ms slower even with the damage model removed: the range
panel's new `_process` called `find_component(DamageModel)` every frame, walking the whole suit
(and the screen did the same for suits without one). Both cache it now. Hole uniforms are
uploaded only when a mesh's holes change (or while one is drilled); rigid meshes skip their
pose. One hit on the CPU (`penetration_probe timing`): a drill start 0.5 ms, a panel 9 ms (one
per tick), a limb cut through 5 ms.

![cuts, panels, cockpit, vent](images/cuts_panels_cockpit_vent.png)

Thigh cut mid-way (the torn line, the stub's cut face from below), a plate flying off the
backpack, space through the cockpit's holes, a thigh cell venting (the mist burst, the leak).
