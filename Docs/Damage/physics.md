# Damage physics: the numbers

What each weapon does to a suit, worked from physics with stated assumptions. Masses and volumes
are the ν's from `Docs/PhysicsAndSensors/mass_model.md` (69 t full, centre of mass 13.1 m up,
inertia 2.62 / 1.42 / 2.98 × 10⁶ kg·m²); thrust and torque from `Docs/FlightControl/summary.md`
(clean torque 24 / 10 / 24 MN·m, 11 G up, 7.7 G forward). Every tunable is marked **[tune]**.

Decided (2026-11-25): beam energy **front-loaded** (pierces targets sliding under it at 10–40 m/s;
an even spread didn't); propellant: liquid hydrogen was chosen but doesn't fit the suit, water
proposed (§5, pending); the reactor sits below the cockpit around the waist (moved in the mass
model) and a hit on it always breaches; secondary explosions sized per weapon; vacuum-realistic
vapour; pilot hit = game over.

## 1. Beams: energy, drilling, burn-through

### The shot

| Quantity | Value | Why |
|---|---|---|
| Shot energy `E` | **4 GJ** [tune] (~1 t TNT) | the smallest round number that gives the outcomes wanted below |
| Pour time | 0.15 s (`nu_beam_rifle.emit_time`) | already in the spec |
| Energy profile | **front-loaded**: power ∝ e^(−t/τ), τ = **0.02 s** [tune]: 78% of the energy in the first 30 ms | the bright head drills; the tail keeps pouring through the hole |
| Power | ~200 GW at the head, ~27 GW averaged over the pour | for scale: one ν main thruster's jet power is ~93 GW (`thrust_sizing.md`) |
| Coupling `η` | **0.6** [tune] | share of the arriving energy that removes material; the rest leaves as reflected light, plasma and heat spread into the part |
| Specific removal energy `e` | **3 MJ/kg** [tune] | between melting and blowing out (steel / titanium ~1–1.5 MJ/kg) and vaporising (iron ~8 MJ/kg): about a third vaporised, the rest blown out molten |
| Hole radius `r` | **0.6 m** [tune] (A = 1.13 m²) | a little wider than the beam's core; the exit flares wider (blow-out) |

One shot can remove `η·E / e` = **800 kg** along its line; by time t after contact it has removed
`800 · (1 − e^(−t/τ))` kg, so a column of m kg is through after `t = −τ · ln(1 − m/800)`.

### Column mass from the mass model

A suit is mostly hollow: armour shell, frame, machinery, tanks. The mass model gives each part's
mean dry density (dry mass ÷ volume; chest and pelvis after the reactor moved); the path length
comes from the traversal. Column mass = density × path × A. A line through a tank cell adds its
propellant (§5): with anything denser than hydrogen, a full cell stops the beam.

| On the beam's line | Density | Path | Column | Burn-through | Shot left after |
|---|---|---|---|---|---|
| Head | 56 kg/m³ | 2.5 m | 158 kg | 4 ms | 80% |
| Forearm | 56 | 2 m | 127 kg | 4 ms | 84% |
| Shin | 51 | 3 m | 152 kg | 4 ms | 81% |
| Chest, front to back (the cockpit) | 56 | 5 m | 316 kg | 10 ms | 60% |
| Backpack | 73 | 3 m | 247 kg | 7 ms | 69% |
| Pelvis / waist (the reactor: breaches) | 140 | 4 m | 633 kg | 31 ms | 21% |
| Shield, no I-field (150 kg/m², coating ×3) | | | 510 kg-eq | 20 ms | 36% |
| + a full tank cell, 1 m of water | 1,000 | | +1,130 kg | stopped | 0%: the cell bursts (§5) |

What that gives, with nothing tuned to force it:

- **Everything is punched through** except full tank cells: limbs and the head keep ~80% and can
  take a second part in line; the chest keeps 60% after the cockpit.
- **Where you aim on the centre line decides the ending**: the chest is the cockpit (a kill and a
  wreck), the waist is the reactor (a 200 m flash, §7).
- A **shield without its I-field** is punched in ~20 ms with a third left: enough to hole the
  forearm behind it (127 kg needed, ~290 kg left). The I-field is what stops beams.
- **Tank cells are where beams stop**, and they burst when they do. As they drain, the suit is
  more beam-transparent.

**The price of front-loading**: burn-through is a few milliseconds on limbs and 10–30 ms on the
body, less than one or two frames. The front doesn't visibly stall. What the eye reads as the
beam fighting its way through is the contact flash, the tail still pouring through the fresh
hole for the rest of the 0.15 s, and the exit spray lasting as long (`beam_effects.md`).

### Targets sliding under the beam

Our rifle keeps following the lead while the beam pours (`MsWeapon.update`) and the line swings
with the barrel, so on our shots the spot only slides by the aim's tracking error. The turret
drone holds its barrel (`TargetDrone.beam_slew_deg` 0; HUNTER 20°/s), so a target crossing its
line slides under it. The spot is 1.2 m wide: a point gets energy for `1.2 m / v⊥`, and the point
the head lands on first gets the head. What the head can remove in that time:

| Slide speed v⊥ | Dwell | Front-loaded (τ 0.02 s) removes | Even spread removed | Front-loaded pierces |
|---|---|---|---|---|
| 10 m/s | 0.12 s | 798 kg | 640 kg | everything but full tanks |
| 40 m/s | 0.03 s | 621 kg | 160 kg | everything but full tanks (the reactor's 633 kg just about) |
| 100 m/s | 0.012 s | 361 kg | 64 kg | limbs, head, backpack, chest; the shield and the waist gouged |
| 200 m/s | 0.006 s | 207 kg | 32 kg | limbs and head; the body deeply gouged |

Behind the first point the slot gets only the tail: a hole with a shallower scar trailing from it.

### Drilling in the sim

Per physics tick (16.7 ms) the arriving energy is the profile's integral over the tick. The
traversal spends it on the column in order along the line; the drill face advances; the hole
record's depth grows. When the column is spent, the exit point is returned and the beam continues
from there with what's left this tick; if the pour ends first, the hole stops as a crater of
that depth. A component is hit when the drilled cylinder reaches its volume; an existing hole's
channel along the line costs nothing.

### Beam recoil

Material blown off the drill face carries momentum back toward the shooter. With an ablation
momentum coupling of ~2 × 10⁻⁵ N·s/J [tune] (the order measured for lasers on metals), 2.4 GJ
absorbed gives ~**48,000 N·s**: 0.7 m/s on the whole suit, or a spin if off-centre (a head hit
6 m above the centre of mass: 0.11 rad/s ≈ 6°/s). The FBW cancels it in tens of milliseconds;
on a severed or limp limb it is a visible kick.

## 2. The I-field window

| Quantity | Value |
|---|---|
| Detector shell | ~20 m in front of the shield [tune] |
| Warning at 3000 m/s | ~6.7 ms (the drone's 1500 m/s beam: ~13 ms) |
| Field needs | detector latency 2 ms + rise 3 ms [tune] = 5 ms |
| Field holds | 0.2 s per charge [tune] (a whole 0.15 s pour) |
| Leak onto the shield | 5–10% of the beam's energy [tune], spread over ~3 m radius: boils coating, no hole |

The sim can't see a 50 m-per-tick beam cross a 20 m shell between ticks, so the trigger is solved
for the arrival time inside the tick. Faster beams (a future mega-particle cannon) beat the window:
a design lever, not a bug. Charges: 3 [tune].

## 3. Vulcans: impact and balance

60 mm, assumed **2.5 kg** projectile (real 57–60 mm rounds are 2.4–2.9 kg) at 1100 m/s plus the
closing speed. Twin guns, 2 × 640 rpm = 21.3 rounds/s.

| | Value |
|---|---|
| Momentum per round | 2,750 N·s (up to ~2× if it rebounds) |
| Kinetic energy per round | 1.5 MJ (a beam shot is ~2,700× that) |
| Whole burst on target (all hit) | 58.7 kN mean |
| On the whole suit (69 t) | 0.85 m/s² = **0.087 G** |
| Torque, all into the head (6 m above the centre of mass) | 0.35 MN·m = **1.5%** of the clean pitch torque; free body 7.7°/s² |

Reference: a 120 mm tank dart (~4.6 kg at ~1,650 m/s, ~7,600 N·s) moves a 62 t tank by ~0.12 m/s.
Bullets don't knock heavy vehicles around, and a 69 t suit with 11 G of thrust corrects 0.09 G
without effort. **Vulcans don't unbalance the suit.** Where the momentum does show:

- **On a limb.** A round into the rifle hand: the shoulder actuator takes a torque impulse of
  2,750 × ~7 m ≈ 19,000 N·m·s on ~2.0 × 10⁵ kg·m² (arm with rifle): a 5.5°/s kick, worked off by
  the servo with an aim error of ~0.03° (~0.4 m at 1 km). A burst into the rifle arm shakes the
  aim: real suppression value.
- **On a limp limb** (actuator dead): each round swings it freely.

**Penetration** (de Marre form): `t ∝ v^1.43 · m^0.71 / d^1.07`, calibrated so this round defeats
~120 mm RHA at 1100 m/s at normal impact [tune] (WWII-era 57 mm AP did ~100 mm at ~830 m/s). Armour:
thickness × RHA-equivalent factor, effective thickness `t / cos θ`, ricochet beyond ~70° obliquity.

| Target | RHA-equivalent | Vulcan result |
|---|---|---|
| Main armour (~60 mm Gundarium-class plate, ×3 factor [tune]) | ~180 mm | stops it; scorch and dent decals |
| Joint covers, skirts' thin edges | 20–40 mm | through: actuator and line damage behind |
| Thruster nozzles and bells | 10–20 mm | through: derated or dead nozzle, stuck gimbal |
| Cameras, sensors, lenses | < 10 mm | destroyed |

That gives exactly the vulcans' role: thrusters, sensors, cameras, joints, light drones.

## 4. Bazookas, missiles, explosions in vacuum

No air means no blast wave. What reaches a target is:

1. **Fragments** (the casing): speed from the Gurney equation, `v ≈ 2.4 km/s / √(M/C + ½)`
   (TNT-class fill; M case mass, C charge mass). Number per m² falls as 1/R².
2. **Detonation products**: total radial momentum ~`√(2·M·E)`; a target intercepts the share
   `A / 4πR²`. Strong only within a few metres.
3. **Flash** (light): blinds sensors, doesn't hurt armour at these yields.

### Hyper bazooka (assumed: 380 mm-class, 250 kg shell, 40 kg HE, ~400 m/s relative) [tune]

| Case | Impulse into the suit | Effect |
|---|---|---|
| Contact on the chest | ~100,000 (shell) + ~70,000 (products / fragments into the half-space) ≈ **170,000 N·s** | 2.5 m/s and, 6 m off the centre of mass, ~22°/s of spin; the part hit is shattered |
| Contact on a forearm (~1 t with its armour) | most of it into that part | the forearm torn off (it would have to absorb ~100 m/s) |
| Proximity burst at 10 m | ~16,000 N·s (products) + fragments | 0.23 m/s; fragments (Gurney ~1 km/s) pepper the facing side: sensors, cameras, nozzles |

The ν's authority makes even the contact push short: 2.5 m/s at 7.7 G is ~0.03 s of thrust;
22°/s against 24 MN·m of pitch torque is stopped in ~0.04 s. **A close blast costs balance
through what it breaks (thrusters, a limb's mass gone, actuators), and through the shock:** the
impulse arrives in ~1 ms, a jolt of hundreds of G on the hull for that instant. The cockpit
shakes, the screen glitches (`cockpit_and_cameras.md`), the seat damps the pilot.

### Shield missile (assumed: 30 kg, 5 kg HE, 10 kg pre-formed fragments of 10 g) [tune]

Gurney (M/C = 2): ~1,500 m/s fragments, 1,000 of them. A suit's ~70 m² facing side:

| Burst at | Fragment hits | Products impulse |
|---|---|---|
| 5 m | ~220 | ~8,000 N·s (0.12 m/s) |
| 20 m | ~14 | negligible |
| 50 m | ~2 | negligible |

Each fragment (11 kJ) goes through ~10–15 mm: cameras, sensors, nozzles, cables. Today's
`blast_radius` 90 m full-damage sphere is replaced by this. Fragments are sampled per part
(expected hits from the part's solid angle, Poisson), never spawned as 1,000 shots.

## 5. Propellant and tank hits

### Which propellant (pending: water proposed)

The mass model carries **25.2 t** of propellant in **~66 m³** of tanks (~380 kg/m³ on average).
Liquid hydrogen (71 kg/m³) would need ~355 m³, 73% of the whole suit's 487 m³: real hydrogen
vehicles are mostly tank for this reason.

Hydrogen is the right choice for a **thermal** rocket (nuclear thermal, ~900 s), where nozzle
temperature caps the exhaust speed (`v ∝ √(T/M)`) and light molecules win. The ν runs at
**Isp 12,000 s** (118 km/s, `thrust_sizing.md`): that is a plasma held off the walls by a magnetic
nozzle, and the exhaust speed is set by the heating power, not by the molecule. There, every
kilogram must first be broken into atoms and ionised, and that energy leaves unused in the
exhaust (frozen-flow loss). Hydrogen, all protons, is the most expensive per kilogram. That is
why real electric thrusters fly xenon, krypton or argon.

| Propellant | Liquid density | 25.2 t needs | Storage | Lost to dissociate + ionise, vs ½v² at 118 km/s | Hit by a beam |
|---|---|---|---|---|---|
| Hydrogen | 71 kg/m³ | 355 m³ (73% of the suit) | cryogenic, 20 K, boils off | ~22% | light: the beam passes; the cell bursts by pressure |
| Methane | 422 | 60 m³ (today's tanks, almost exactly) | cryogenic, 111 K | ~7% | flammable if it meets the cockpit's air |
| Ammonia | 682 | 37 m³ | pressurised (~10 bar) at room temperature | ~5.5% | toxic |
| **Water** | 1,000 | **25 m³** | **room temperature**, kept above 0 °C by the reactor's heat | **~4%** | stops the beam; flashes to steam: a violent burst |
| Argon | 1,395 | 18 m³ | cryogenic, 87 K | ~0.5% | inert, boils off invisibly |
| Xenon | ~2,900 | 9 m³ | cryogenic or supercritical; rare and costly | ~0.1% | inert |

**Proposed: water.** It fits with room to spare (25 m³, the freed volume goes to the reactor in
the pelvis and to structure), needs no cryogenics (no boil-off sitting in a hangar or on patrol,
no 20 K plumbing to shoot through), loses ~4% to plasma chemistry instead of ~22%, is in every
colony and ice asteroid, isn't flammable or toxic, and doubles as radiation shielding. The mass
model's masses don't change (tank shares only split the mass), only the volume the tanks claim.

### What a beam does to a water cell

- **It stops there.** 1 m of water is 1,130 kg on the beam's line, more than a shot can remove.
  Lines that miss the tanks still punch through (§1); lines through a full cell end in it. Tank
  placement is part of the armour design: cells around the backpack and pelvis, none in front of
  the cockpit.
- **Steam burst.** Whatever energy the beam still had goes into the water: up to ~2.4 GJ, enough
  to flash ~900 kg to superheated steam (×1,600 in volume) in a closed cell. The cell and the
  panels over it are blown off (`dismemberment.md`, a ~2–3 m blow-off radius). This is the
  "pierced, then an explosion" from physics, and **no fire** (no oxygen in vacuum).
- **Draining changes it**: a nearly empty suit has little water left to stop beams.

**Venting** from a hole in a pressurised cell pushes like a nozzle: `F ≈ 2·Cd·P·A` (Cd ≈ 0.6),
at 0.3 MPa [tune] through the 1.13 m² hole: **~0.4 MN** (a quarter of one main) at ~25 m/s exit
speed. A ~700 kg cell [tune: 4–8 cells per tank] empties in ~0.04 s, ~17,000 N·s (0.25 m/s): a
sharp pop. A cut feed line leaks longer, weakly.

**The look** (vacuum): water in vacuum boils and freezes at once into a cloud of ice crystals
that glitters in sunlight and spreads and thins within a few seconds (the Space Shuttle's water
dumps looked like this). No smoke, no flame.

If hydrogen stays: beams pass tanks (only their energy share boils the liquid and bursts the
cell), and the suit would carry ~4.7 t of propellant, a fifth of today's Δv.

## 6. Secondary explosions, per weapon

Sized per store [tune], not from a formula. A full release of a rifle E-pac (32 × 4 GJ = 128 GJ,
~30 t TNT) would vaporise the suit, so the E-pacs' yields are design choices: the stored charge
still needs the weapon's acceleration to become beams; a breach releases a little of it.

| Store | Hit | Breach |
|---|---|---|
| Rifle E-pac | the pack | **0.5 GJ** (~120 kg TNT): the rifle gone, the hand and forearm torn, the chest scorched |
| Shield I-field charges (3) | each | 0.3 GJ each, on the shield |
| Hyper bazooka magazine (assumed 5 shells) | any shell | the HE goes: 5 × 40 kg = 0.84 GJ, casing fragments (Gurney ~1 km/s) |
| Shield missiles (4) | any | 4 × 5 kg HE = 84 MJ, their fragments |
| Vulcan magazines | the drum | cook-off: rounds popping over 1–3 s, small fragments, not one blast |
| Fin funnels | each | its own small generator and E-cap: 0.1 GJ |
| Beam saber | the hilt | 0.05 GJ |
| Electronics, capacitor banks | any | 1–10 MJ: arcs, a small flash |

## 7. The reactor: a hit is a breach

Below the cockpit, around the waist. **Any drilled cylinder or fragment that reaches the reactor
component breaches it** (decided). Damage to what feeds it (power lines, coolant, conditioning)
without touching the core only cuts power (`summary.md`, SuitSystems).

A fusion core with its field collapsing releases its plasma and magnetic energy mostly as
radiation. Assume **2.5 TJ** (~0.6 kt) [tune], about 2 s of the suit's full thruster power.
Radiant fluence at distance R: `F = E / 4πR²`.

| R | Fluence | Effect on another suit |
|---|---|---|
| 50 m | 80 MJ/m² | lethal: facing armour ablated deep, components cooked, pilot killed |
| 100 m | 20 MJ/m² | facing cameras, sensors, nozzles dead; coatings and thin plates ablated |
| 200 m | 5 MJ/m² | facing cameras blinded or dead, surfaces scorched; the visible ball's edge |
| 400 m | 1.25 MJ/m² | sensors saturated for seconds (flash blindness) |

**The push** comes from the near side of the target boiling off (X-ray blow-off), coupling
~2–5 × 10⁻⁵ N·s/J [tune] over ~70 m²: at 100 m ~0.4–1 m/s, at 50 m ~1.6–4 m/s with a tumble.
The breaching suit's own debris (69 t of fragments at hundreds of m/s) adds a shower at 100–300 m.

**Aiming follows from it**: a beam through the chest kills the pilot and leaves a wreck; a beam
through the waist sets off a 200 m flash. At close range, aim high.

## Tunables at a glance

| Constant | Start | Shapes |
|---|---|---|
| Beam shot energy, profile | 4 GJ, front-loaded τ 0.02 s over 0.15 s | what a shot gets through, holes on sliding targets |
| Coupling η, removal energy e | 0.6, 3 MJ/kg | drilling rate |
| Hole radius | 0.6 m | look, column mass |
| Coating factor (shield) | ×3 | the shield's burn-through time |
| I-field: shell, latency + rise, hold, leak, charges | 20 m, 5 ms, 0.2 s, 5–10%, 3 | when it catches the beam |
| Vulcan round mass, RHA calibration | 2.5 kg, 120 mm @ 1100 m/s | what vulcans can break |
| Armour RHA factor | ×3 | the same |
| Warheads (bazooka, missile) | above | fragments and contact impulse |
| Propellant, tank pressure, cells | water (proposed), 0.3 MPa, 4–8 | what stops beams, burst size, venting pop |
| Secondary yields | per weapon, §6 | secondary explosion size |
| Reactor yield | 2.5 TJ | the big flash |
