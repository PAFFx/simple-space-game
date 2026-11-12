# Flight Control — Thrusters, FBW and Allocation

## Pipeline

Every physics tick the `FlightComputer` runs one pass:

```
PilotInputSource ──PilotCommand──▶ ControlLaw ──Wrench──▶ AmbacController ──τ_ambac──▶ apply_torque
 (keyboard/HOTAS/AI)  intent        (FBW logic,   F, τ     (limb balancing)
                                    pilot frame,      │
                                    AttitudeOffsetSolver)  └── F, τ − τ_ambac ──▶ ThrustAllocator ──u[i]──▶ Thruster × N ──▶ RigidBody3D
```

| Stage | Base class | Implementations | How to swap |
|-------|-----------|-----------------|-------------|
| Input | `PilotInputSource` (Node) | `KeyboardPilotInput`, `HotasPilotInput` | Replace the `PilotInput` child of `FlightComputer` |
| Control law | `ControlLaw` (Resource) | `RateCommandControlLaw` (FBW), `DirectControlLaw` | Inspector dropdown on `FlightComputer.control_law`, or `set_control_law()` |
| Allocator | `ThrustAllocator` (Resource) | `ConeProjectedAllocator`, `GreedyAllocator` | Inspector dropdown on `FlightComputer.allocator`, or `set_allocator()` |
| Auto-rotation | `AttitudeOffsetSolver` (Resource) | `ThrustVectoringAttitudeSolver` | `RateCommandControlLaw.attitude_solver` (empty = body stays aligned) |
| Limb balancing | `AmbacController` (Node) | — | Add/remove the node; `FlightComputer.ambac` (auto-discovered) |
| Actuator | `Thruster` (Node3D scene) | — | Add/remove/move `thruster.tscn` instances anywhere under the body |

Control laws and allocators are duplicated by the `FlightComputer`, so vehicles sharing a `.tres`
never share hold or warm-start state.

---

## Files

```
Common/Controls/PilotInput/
  pilot_command.gd          Device-independent intent (translation, rotation, boost, toggles)
  pilot_input_source.gd     Abstract input node
  keyboard_pilot_input.gd   Keyboard actions, slewed so keys "travel" like a stick
  hotas_pilot_input.gd      Keyboard + raw joystick axes (JoyAxisBinding list)
  joy_axis_binding.gd       One axis → one channel, with deadzone / expo / invert
  pilot_input_actions.gd    Action names + keyboard defaults (registered only if missing)

Entities/Vehicles/Components/FlightControl/
  flight_computer.gd        Orchestrator, propellant, telemetry for the HUD
  flight_state.gd           Per-tick snapshot + thruster geometry + authority estimate
  wrench.gd                 Force + torque pair (body frame, about COM)
  Thruster/                 Gimballed thruster component + scene
  ControlLaws/              ControlLaw base + implementations
  Allocators/               ThrustAllocator base + implementations
  AttitudeSolvers/          AttitudeOffsetSolver base + ThrustVectoringAttitudeSolver

Entities/Vehicles/Components/Ambac/
  ambac_joint.gd            One limb DOF: bone, axis, inertia, limits, priority, group
  ambac_controller.gd       Weighted allocation + centering spring, returns achieved torque
  ambac_modifier.gd         SkeletonModifier3D: applies the limb offsets after animation
```

---

## Thruster

- **Orientation:** the node's `-Z` is the thrust direction; the blue `+Z` gizmo arrow shows where the
  plume goes.
- **Gimbal:** the `Gimbal` child slews toward the commanded direction at `gimbal_rate_deg`, limited
  to a cone of `gimbal_limit_deg`. `gimbal_pitch_limit_deg` can tighten the fore/aft swing (about the
  node's local X) below the cone, as two planes through the nozzle axis that the allocator's
  projection respects too.
- **Throttle:** first-order lag (`spool_up_time` / `spool_down_time`).
- The force applied to the body uses the **actual** gimbal angle and throttle, not the command, so
  actuator lag is simulated and the control laws must cope with it.
- Propellant flow is `thrust / (Isp · g0)`; body mass is updated as propellant burns.
- Thrusters on the prototype ride on `BoneAttachment3D`s, so they follow limb animation. The
  `FlightComputer` re-reads every thruster's position and axis each tick, so moving limbs (AMBAC)
  automatically changes the allocation.

---

## Control laws

### `RateCommandControlLaw` (default FBW)

Everything is commanded in the **pilot frame**: the orientation the linear seat cockpit holds.
The body is driven to `pilot · offset`, where the offset comes from the attitude solver.

| Axis | Mode | Stick means | Stick released |
|------|------|-------------|----------------|
| Rotation | `ATTITUDE_HOLD` (default) | Turn rate about the pilot's axes (`max_rate_deg`); cockpit locked rigidly to the suit on the steered axes only | Turn brakes at full torque (axis still locked), then the attitude is held |
| Rotation | `RATE_DAMP` | Angular rate demand | Rate → 0, no hold, no auto-rotation |
| Translation | `VELOCITY_HOLD` (default) | Accelerate along the stick, no top speed (drift across it cancelled; `max_command_speed` > 0 makes it a velocity command) | Brought to rest relative to the reference frame |
| Translation | `NEWTONIAN` | Thrust demand (cruise fraction, or 100% with boost) | Coast |

Torque = `I·α + ω × Iω` where `α = rate_gain · (ω_cmd − ω)`.

**Design goals**

- Press a direction and the suit goes that way at the same acceleration whichever way you
  press: velocity command in the pilot frame with one acceleration cap (`cruise_accel_g`
  0.8 G, `boost_accel_g` 4 G), so the path is a straight line to the command.
- Release the rotation controls and the turn stops at once (full torque, `stop_gain_multiplier`),
  then the attitude is held.
- The cockpit only turns when the pilot turns it, and then rigidly with the suit (no lead or
  lag on the steered axis). Any body rotation for thrust happens underneath on the other axes.
  The only seat damping is linear (`SeatDampener`).
- Locking is **per pilot axis** (pitch, yaw, roll). A steered axis, and a released one that is
  still braking, turns suit and cockpit as one unit; its offset component is frozen. The other
  axes keep their attitude hold and auto-rotation, so e.g. yawing during a boosted dive keeps the
  mains vectored while the view stays level. Steering all three axes = fully rigid.
  - An axis stays locked `axis_release_time` (0.12 s) after its input drops into the deadzone,
    so a noisy stick doesn't flicker the lock.
  - Released axes unlock together once none is still turning the way it was steered (rate below
    `hold_capture_rate_deg` or reversed). Any overshoot is then removed by the hold, not the view.
  - An axis that locks mid-swing takes the body's lag on it into the offset, so the view never
    jumps. Locked axes still get the offset swing fed forward (rotating about two axes at once
    turns the body slightly about the third).
  - Locked and free axes get separate torque budgets: a boosted turn or a stop may use all of
    it, auto-rotation stays at `auto_rotate_torque_fraction`. Any locked axis keeps the
    allocator's default torque priority.

**Movement modes.** How far auto-rotation may commit to a move:

| Mode | Input | Accel cap | Speed | Auto-rotation |
|------|-------|-----------|-------|---------------|
| Normal | — | `cruise_accel_g` 0.8 G | no limit | ≤ `cruise_max_offset_deg` 20° |
| Precision | C (toggle) | `precision_accel_g` 0.15 G | `precision_speed` 20 m/s | off; turn rates × 0.5 |
| Boost | Shift | 4 G | no limit | ≤ `boost_max_offset_deg` 30° |
| Full boost | Shift double-tap + hold | 4 G | no limit | solver's `max_offset_deg` 60° |

Capped modes keep the suit quick to change direction but give less acceleration in weak
directions (descending: 0.7 G normal, 0.8 G boost, 1.3 G full). Shift overrides precision.
While boosting, the swing itself is torque-limited (the body lags the target by ~14°, so swings
run at ~20°/s), because auto-rotation yields to force (`auto_rotate_torque_priority`).

**Horizon lock** (L, toggle; `horizon_lock`, on by default). Body-axis pitch + yaw bank the view relative to
the world: a diagonal turn tilts the horizon, and a closed loop of stick motion leaves a roll
(pitch up 90°, yaw 90°, pitch down 90° = rolled 90°). With the lock, yaw turns about a stored
up (set when the lock is switched on) and roll levels any bank (`horizon_level_gain` 3 /s, ≤
`horizon_level_rate_deg` 30°/s), while steering, while a released turn brakes, and when idle.
Roll is driven with pitch/yaw, so it locks with them. Rolling by hand sets a new horizon. The lock
fades toward plain body-axis yaw within `horizon_fade` (|cos pitch| 0.25, ≈ 75°) of straight up or
down, and upside down it holds the inverted horizon, so pitching over the top doesn't flip the view.
Results: a diagonal turn ends level instead of 66° banked; mouse-style circles stay within
0.7° (17° without); near vertical a released turn may bank up to ~9° before levelling.

**Boost** (Shift): 4 G acceleration cap, velocity loop 2.5 /s (`boost_velocity_gain`, snappy
starts, stops and dodges), 100% torque for pilot steering, rates × 1.7. A 10 s full boost forward
reaches ~355 m/s. Auto-rotation swings at 120°/s with the target's rate fed forward into the hold.

**Clean force while auto-rotating.** Fast swings need big turning moments, and the allocator would
borrow the off-centre mains for them, spilling force (e.g. a boosted dive first shooting upward).
Auto-rotation therefore requests at most `auto_rotate_torque_fraction` (0.4) of torque authority and
hands the allocator a lower torque priority (`auto_rotate_torque_priority` 0.5, carried on the
`Wrench`). Lower than ~0.3 loses attitude control; pilot steering and stops keep the default.

### Auto-rotation (`ThrustVectoringAttitudeSolver`)

Thrusters are not equal: the backpack mains (firing down and back) dwarf the verniers, so the suit
is strong upward and weak in other directions. Clean authority measured on MSP-02: up 5.75 G,
forward 2.6, back 1.3, sideways 1.7, down 0.7 (level attitude). The mains' 60° vectoring
means a boosted descent pitches the suit nose-down (~1 G down at 70°) instead of nose-up.

The solver turns the body **only when needed**: while a translation is commanded (or Shift is
held), and only if the capped acceleration exceeds what the current attitude can deliver cleanly.
Cruise (0.8 G) only exceeds the weak down direction, so normal flying leans the suit (≤ 20°)
mostly when descending. Boost (4 G) rolls it for side moves, leans it forward for forward and
pitches it for climbs or brakes, within the movement mode's cap.
Releasing the controls brakes without rotating.

It minimises over offsets `r` (pitch and roll up to 60°, yaw at most 3° via `axis_limit_deg`, so
the suit never swings sideways under the pilot):

```
J(r) = shortfall_weight · max(0, |F| / capability(R⁻¹F) − 0.9)²
     + angle_weight · (|r| / 60°)²  +  smooth_weight · |r − r_prev|²
```

Demands the current attitude can meet cost only the angle, so the result is "rotate as little as
possible to make it achievable".

### Capability map

`capability()` comes from a `ForceCapabilityMap` (blended with a harmonic mean, so strong
directions never inflate weak neighbours): at load the `FlightComputer` asks the allocator,
in 48 directions, for the largest force it can make with less than 6% leaking sideways or into
torque (bisection, warm-started probes, about 0.5 s once). An estimate from per-axis limits is far
too optimistic: e.g. gimballed downward mains *can* push sideways, but only by also pushing up,
which used to show up as vertical drift during strafes. Call `rebuild_capability_map()` after
changing thrusters. It's a pattern search warm-started from {current, zero, each body axis aimed at
F}, about a dozen cost evaluations per tick. The offset is hard-limited to `max_offset_deg` (70°)
and slewed at `slew_rate_deg` after a short low-pass (`smoothing_time`).

**Returning to rest.** When nothing needs the offset (no translation and no boost), the target
jumps straight back to "aligned with the cockpit". The cockpit doesn't move, because it always holds
the pilot frame, and the hold brings the body home **time-optimally**: it commands the fastest
rate from which it can still brake exactly on target, `ω = √(2·α·θ)` (`_braking_rate`, α from the
torque limit and inertia, `braking_margin` 0.5), tracked by a stiffer rate loop
(`hold_rate_gain_multiplier` 5). Allocation uses `realign_torque_priority` 0.5 so the return doesn't
borrow the mains while the suit is braking its velocity. Measured after boosted moves: back within
2° in 1.1–1.9 s, overshoot ≤ 3.7° (previously 3–5 s with several corrections and up to 36°).

**Steering mid-swing.** When the pilot starts steering during auto-rotation, the offset is re-based
on the body's *actual* attitude (`pilot⁻¹ · body`), not its target, so the cockpit can't jump by the
tracking lag. While holding (not steering), the gimbal compares the pilot frame with the body's
predicted end-of-tick attitude, so the cockpit doesn't trail a turning body by one tick.

**Keeping the pilot oriented.** The swing waits for the body: once the body lags the target by
6° the slew slows, and at 15° it pauses (`tracking_lag_deg`). The solver's 60° limit sits below the
seat gimbal's soft knee (62°, limit 75°), and past the knee the gimbal eases toward its limit
(tanh) instead of clamping, so an overshoot can't snap the view. All rotation clamps take the
shortest way round: clamping the "long way" quaternion once flipped the cockpit by ~220° in a
single tick. Verified on boosted dodge zigzags: cockpit motion in the world ≤ 8°/s.

- Commanded rotations move the pilot frame itself, so they never produce an offset.
- The cockpit holds the pilot frame (`CockpitGimbal`): its rotation in the hull is the
  *measured* `body⁻¹ · pilot`, so it stays still in the world even while the body is still
  swinging. The HUD body reticle slides off the cockpit centre to show the difference.
- While the hatch is unsealed the offset is forced to zero (`FlightState.allow_attitude_offset`), so
  the cockpit lines up with the hull opening.

---

## Stopping without wobble

- **Braking curve with reaction delay.** The time-optimal approach is ω = √((α·τ)² + 2αθ) − α·τ
  (`braking_delay` τ 0.15 s, for thruster spool-up and nozzle slew), so the body no longer arrives
  still turning and swings past. `braking_margin` 0.8.
- **Brake hard, accelerate gently.** Once the hold has to slow down to arrive (closing rate above
  ~60% of the braking curve), it gets the full torque budget and the top allocator priority; while
  speeding up it stays gentle so the push stays clean.
- **Feasible swing.** The auto-rotation offset is moved like a body: its swing speed changes no faster
  than the torque budget allows and it eases into its end point, so the body can follow exactly
  (no overshoot when the target stops or turns back). If the body still lags (`tracking_lag_deg`),
  its torque budget and priority rise toward `recover_torque_priority`.
- **Committed attitude.** The solver remembers which side it turned to and charges `commit_weight` for
  turning back through to the other side until the demand swings `commit_release_deg` (45°) away.
  Its shortfall term is the share of the demand left unmet (0..1), so a full-boost demand can't
  swamp it. Descents no longer flip between nose-up and nose-down.
- **Hard stops.** In V-HOLD, releasing the stick brakes at `stop_accel_g` (6 G) with the boost gain,
  limited by what the attitude can deliver (not in precision mode).
- **Upright when it's enough.** The solver only turns away from the pilot frame if that raises the
  capability along the demand by `min_tilt_gain` (×1.6); a full-boost climb stays head-up (~9 G on
  the ν) instead of leaning back for a bit more thrust.
- **Boost.** Shift is capped at `boost_accel_g` 7 G; a double-tapped full boost has no cap (all the
  thrust the suit has). ν: full boost up peaks at ~11 G.

Measured on the ν (stick released after 3 s): normal flight returns to rest in ≤ 0.32 s and stops
22 m/s in ~1.3–2.2 s; after Shift ~1.0–1.2 s, after full boost ~1.0–1.6 s, at most one small swing.

## AMBAC

Limbs act as reaction wheels: accelerating a limb by `α` about axis `a` pushes the body with
`−J·α·a`.

**Torque on top of the thrusters.** The FBW's torque budgets (steering, stops, auto-rotation and
the time-optimal return to rest) include what the limbs can add right now
(`AmbacController.get_capacity()` → `FlightState.ambac_torque`): each free joint's peak reaction
torque, scaled by its remaining travel and `capacity_fraction` (0.25, since limbs lose authority
near their stops and while recentring). Each tick AMBAC gets everything beyond the thrusters'
authority plus `share` (40%) of the rest; the thrusters get what's left, clamped to their own
limit (`Wrench.thruster_torque_limit`). Before, AMBAC only took a slice of a thruster-sized demand,
so it saved propellant but never made the suit turn faster.

1. Weighted least squares: `α_i = −w_i J_i a_i·λ`, `M λ = τ_request`, `M = Σ w_i J_i² a_i a_iᵀ + εI`.
   `w_i` = joint priority, zero for groups occupied by active equipment (rifle raised → right arm,
   shield guard → left arm).
2. Each joint backs off as it nears its stop, and a centering spring pulls it back to neutral.
3. The **achieved** reaction torque is applied to the body; the thrusters get `τ − τ_ambac`.

**Joints** (offsets from the animated pose, human-like ranges):

| Joint | Axes and range | Inertia (kg·m²) |
|---|---|---|
| Hip | flex −20…+35°, side −3…+6° (outward), twist ±15° | 1.6e5 (leg), 2e4 twist |
| Knee | bend back up to 45°, straighten 5° | 4.5e4 |
| Shoulder | flex −35…+45°, out −8…+35°, twist ±25° | 6e4, 1e4 twist |
| Elbow | bend up to 50°, straighten 5° | 2.5e4 |
| Waist | twist ±12°, bend −10…+6° | 1.2e5 / 1.5e5 |

The side hip swing is kept small. Twists move little mass; they mostly add natural motion.

**Rate loop.** Steering and stops were limited by a gentle rate loop (2.5 /s), not by torque, so
`rate_gain` is now 5 /s and `stop_gain_multiplier` 2.5. Auto-rotation keeps its own gentler gain
(`auto_rotate_rate_gain` 2.5) so swings don't spill force.

Measured on MSP-02 (pitch 1.5 s at full stick, release; yaw likewise; return to rest after a 3 s
boosted dive):

| | Before | Now | Now, AMBAC off |
|---|---|---|---|
| Pitch: 90% of rate / stop | 0.90 / 0.73 s | 0.50 / 0.40 s | 0.50 / 0.42 s |
| Yaw: 90% of rate / stop | 1.05 / 0.65 s | 0.53 / 0.32 s | 0.50 / 0.32 s |
| Return to rest: within 2° / settled | 0.87 / 1.48 s | 0.90 / 1.15 s | 0.88 / 2.58 s |
| Propellant: pitch / return | 29 / 99 kg | 31 / 100 kg | 43 / 141 kg |

Typical swing: hips up to 26° in a return to rest, 18° in a pitch; waist 7–8°; knees 5–7°; arms
5–9°; side hips ≤ 3°. Yaw uses mostly the waist twist.

### `DirectControlLaw`

No assists — stick maps straight to force/torque authority. Baseline / "manual reversion".

---

## Allocators

### `ConeProjectedAllocator` (default)

Each thruster gets a free 3D vector `uᵢ` (throttle-normalised) constrained to its gimbal cone, and
we solve

```
min  |Wf (Σ Tᵢuᵢ − F)|² + |Wt (Σ rᵢ × Tᵢuᵢ − τ)|² + λ Σ |Tᵢuᵢ|²
```

with accelerated projected gradient descent (FISTA). Projection onto "cone ∩ unit ball" is closed
form (`ThrustAllocator.project_to_cone`). It's warm-started from the previous tick with a leak
(`warm_start_decay`), which bleeds off pairs of thrusters cancelling each other out — residual
minimisation alone never removes those. Around 0.2 ms per tick for 10 thrusters in GDScript.

**Propellant.** Least squares alone fires every thruster that helps even a little (e.g. the
down-firing shoulder tops while climbing). A price proportional to thrust, `μ Σ|Tᵢuᵢ|` (what fuel
really costs), makes only the best-aimed thrusters fire. `μ` scales with the force demand
(`fuel_cost` 0.1). The price leaves the demand short, so each tick solves in `fuel_passes` (3) passes
and adds the shortfall back onto the target (Bregman iteration), which converges on the cheapest
allocation that still meets the demand. The price fades out between 75% of the capability in that
direction and full capability (`fuel_fade_start`), so a full-power push is never held back. Pure
rotations have no force demand and aren't priced.

The FBW also never asks for more force in a direction than the thrusters that can aim within ~45°
of it deliver (`FlightComputer.min_thrust_alignment` 0.7, applied in `ForceCapabilityMap`). Past
that, extra force only comes from thruster pairs fighting each other. This mostly limits the weak
directions: straight down 0.71 → 0.30 G, back 1.2 → 1.0 G.

Measured on MSP-02 (normal flight, 4 s push + V-HOLD stop): climbing 98 → 66 kg of propellant at the
same speed, with the climb itself 98% efficient (net force ÷ total thrust); boosted climb −10%.
Boosted forward and sideways keep their speeds (200 / 74 m/s). Boosted descents are slower
(24 → 17 m/s in 4 s); a full boost tilts the suit for more.

`torque_priority > 1` makes rotation win when demand exceeds authority.

### `GreedyAllocator`

Each thruster independently aims where it helps most and sizes its throttle as if acting alone.
Intentionally crude (it undershoots and cross-couples), kept for comparison and experiments.

---

## Controls (defaults)

| Action | Key |
|--------|-----|
| Translate fwd / back / left / right | W / S / A / D |
| Translate up / down | Space or R / Ctrl or F |
| Pitch down / up | ↑ / ↓ (stick-forward convention) |
| Yaw left / right | ← / → |
| Roll left / right | Q / E |
| Boost (full thrust, auto-rotation ≤ 30°) | Shift |
| Boost with full auto-rotation (60°) | Shift double-tap, hold |
| Precision mode on / off | C |
| Horizon lock on / off | L |
| Translation mode (V-HOLD ↔ NEWTON) | T |
| Rotation mode (ATT-HOLD ↔ RATE) | G |
| Hatch open / close | H |
| Cockpit / external view | V |
| Rifle ready / lower | 1 |
| Shield guard / lower | 2 |
| Look around | Mouse |
| Steer pitch / yaw with the mouse (look recentres) | Hold right mouse button |

Defaults are registered only for actions missing from the InputMap, so bindings set in
**Project Settings → Input Map** take precedence.

### HOTAS / joystick

`HotasPilotInput` reads raw axes through `JoyAxisBinding` resources (channel, device, axis,
invert, deadzone, expo). The prototype ships bindings for X→roll, Y→pitch, axis 5→yaw, but
`joystick_enabled` is **off by default**: on the dev machine one stick's X axis showed spikes
around 0.24 at rest, which a deadzone alone can't reject.

To set up: enable `log_axis_activity`, move each axis, read the indices in the Output panel, fix the
bindings, then enable `joystick_enabled`.

---

## Tuning reference (MSP-02)

- 30 t dry + 10 t propellant + 6.4 t equipment ≈ 46 t. Main thrust is anime-style: 2 × 900 kN
  backpack mains + 2 × 300 kN leg mains (~5.3 G), plus 18 verniers of 40–56 kN. The backpack mains sit at the bottom of the pods, below and behind the centre of
  mass. Their nozzles swing fore/aft from straight down to 60° back (never forward of down) and up
  to 60° sideways (`gimbal_pitch_limit_deg` 30° around a nominal 30° back, inside the 60° cone).
  Compared with a full 60° cone: 10 s full boost forward 350 → 288 m/s, boosted strafe 69 → 62 m/s,
  full-boost dodge 3.2 → 3.4 s; climbing, normal strafes and dodges unchanged.
- Authority is deliberately anisotropic: strong up, weak sideways, back and down. No backpack
  verniers fire upward; down thrust comes from the shoulder tops only.
- Verified headless:
  - up, no boost: 1.37 G with no rotation
  - strafe, no boost: no rotation, ~0.55 G; with boost: rolls up to 70°, yaw stays 0°, 45 m/s
  - forward with boost: leans forward up to 70° in pitch
  - holding Shift after a strafe rolls the other way and brakes 35 → 3 m/s in ~6 s
  - the cockpit stays within ~1° in the world through all of it
  - a commanded yaw turns cockpit and suit together and stops cleanly

## RX-93 ν Gundam (`Stages/RX93TestRange`, the main scene for now)

Built from a downloaded model (`Tools/Blender/build_mobile_suit_nu.py`, `Tools/Godot/build_rx93_scene.gd`),
with MSP-02's bone names and components. Weapons are separate equipment (rifle on `hand.R`, shield
on `forearm.L`, hyper bazooka and beam saber on `backpack`; the fin funnels are built but left off
the loadout for now). Thrusters sit on the model's yellow thruster ports (found by sampling its
texture), and most can't aim far, so limbs have to move to point them:

| Thrusters | Where | Fires | Vectoring |
|---|---|---|---|
| 4 × 1 MN mains (the model's own nozzles, in two pods that pivot with them) | backpack, 2 per side, stacked | down, back | 2D fore/aft ±30° around 48° back (18°–78° back); pod swings at 90°/s. Kept modest so the suit pitches nose-down to drive forward |
| 2 × 500 kN | soles | down | 3D, 20° cone |
| 2 × 400 kN (the model's own nozzles; the plate over each opens while it's swung) | behind each calf | down, a little back | 3D, 18° cone centred 15° behind the modelled nozzle (never into the leg) |
| 4 × 250 kN | shoulder armor, 2 per side | up-and-out / out-and-down | 2D fore/aft ±25° |
| 2 × 250 kN | chest vents | forward (brakes) | 2D up/down ±20° |
| 6 × 80 kN | front of each shin, below the knee (centre, outer, inner) | forward-down | 2D left/right ±20° |
| 2 × 120 kN | rear skirts | back | fixed |
| 6 × 70 kN | side skirts, 3 each | forward-out, back-out, out | fixed |

No added nozzle meshes on the ν (`Thruster.show_nozzle` off): small ports show only a plume from
the armor, and the main and calf nozzles are the model's own, moved by `ThrusterGuards`:
- **Backpack pods** (`main_pod.*`) pivot fore/aft about their middle, following their two nozzles'
  throttle-weighted, low-passed aim. The nozzles swing around that pivot (`Thruster.swing_pivot`),
  so the push point and plume move with the pod and the allocator sees the moved position. The
  pod housings are 1 m deeper than on the source model (front still on the backpack) so they
  clear the body; the hyper bazooka between them moves back with them. White backpack panels are
  recoloured dark navy.
- **Plumes**: backpack 16 m (the biggest), calves 4.5, chest 3.5, shoulders and soles 3, small
  ports 1–1.6. Slot-shaped ports (chest, rear skirts, shins) get a flat plume along the slot
  (`Thruster.plume_slot`).
- **Calf nozzles** (`calf_nozzle.*`) turn fully with their thrusters.
- **Calf plates** (`calf_guard.*`) are covers: they open outward only (35°) once the nozzle swings
  more than 3°, hold, and close 0.6 s after it's back under 1.5°, at steady rates.

These bones are visual: the thrusters stay on the backpack/shin bones. Idle nozzles (under 1%
throttle, `Thruster.park_throttle`) park at centre, so covers can close. Thruster swing limits: `gimbal_pitch_limit_deg` (fore/aft) and `gimbal_yaw_limit_deg`
(sideways) tighten the cone per axis; 0 on one = 2D vectoring, `gimbal_limit_deg` 0 = fixed.

Clean force capability (level, limbs at rest): up 7.1 G, forward 4.3 G, sideways 2.4 G, back
1.8 G, down 1.4 G; pitch torque 15 MN·m. Limbs don't aim the fixed/2D thrusters yet.

## Tuning reference (MSP-01 prototype)

- Mass 36 t dry + 9 t propellant, Isp 3000 s, ~2.6 MN total thrust across 10 thrusters.
- Forward authority ≈ 1.58 MN (≈ 3.5 g full, ≈ 1.8 g cruise). Braking is much weaker (≈ 0.42 MN):
  flip and burn, as in UC.
- Verified headless: 0 → 29 m/s in 2 s forward; 37 °/s pitch with < 0.5 °/s residual after
  release; V-HOLD bleeds 34 m/s to rest; idle drift 0.00 m/s.

## Known limitations

- `FlightState.max_torque` is a per-thruster best case, not a net-force-free guarantee. That's why
  the FBW only requests `torque_fraction` of it.
- No minimum impulse bit / thruster deadband modelling yet.
- The reference frame's velocity is a finite difference on its position (low-passed), so frames
  moved in `_process` add a little noise.
