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
  to a cone of `gimbal_limit_deg`.
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
| Rotation | `ATTITUDE_HOLD` (default) | Turn rate about the pilot's axes (`max_rate_deg`); cockpit locked rigidly to the suit | Turn brakes at full torque (cockpit still locked), then the attitude is held |
| Rotation | `RATE_DAMP` | Angular rate demand | Rate → 0, no hold, no auto-rotation |
| Translation | `VELOCITY_HOLD` (default) | Velocity in the pilot frame (`max_command_speed`) | Brought to rest relative to the reference frame |
| Translation | `NEWTONIAN` | Thrust demand (cruise fraction, or 100% with boost) | Coast |

Torque = `I·α + ω × Iω` where `α = rate_gain · (ω_cmd − ω)`.

**Design goals**

- Press a direction and the suit goes that way at the same acceleration whichever way you
  press: velocity command in the pilot frame with one acceleration cap (`cruise_accel_g`
  0.35 G, `boost_accel_g` 2 G), so the path is a straight line to the command.
- Release the rotation controls and the turn stops at once (full torque, `stop_gain_multiplier`),
  then the attitude is held.
- The cockpit only turns when the pilot turns it, and then rigidly with the suit (no lead or
  lag on any axis). Any body rotation for thrust happens underneath, and only while not steering.
  The only seat damping is linear (`SeatDampener`).
- While the pilot steers, auto-rotation is frozen: suit and cockpit turn as one rigid unit.

**Boost** (Shift): 4 G acceleration cap, velocity loop 2.5 /s (`boost_velocity_gain`, snappy
starts, stops and dodges), 100% torque for pilot steering, rates × 1.7, commanded speed × 2.5
(150 m/s). Auto-rotation swings at 120°/s with the target's rate fed forward into the hold.

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
Cruise (0.35 G) fits every direction, so normal flying never rotates the suit. Boost (2 G)
rolls it for side moves, leans it forward for forward and pitches it for climbs or brakes.
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

## AMBAC

Limbs act as reaction wheels: accelerating a limb by `α` about axis `a` pushes the body with
`−J·α·a`. Each tick the `AmbacController` is offered `share` (30%) of the FBW torque demand:

1. Weighted least squares: `α_i = −w_i J_i a_i·λ`, `M λ = τ_request`, `M = Σ w_i J_i² a_i a_iᵀ + εI`.
   `w_i` = joint priority (hips 1.0, knees 0.9, waist 0.8, shoulders 0.6, elbows 0.5), zero for
   groups occupied by active equipment (rifle raised → right arm, shield guard → left arm).
   Hinges have one-sided travel (`min_angle_deg`/`max_angle_deg`): knees bend back up to 35° but
   straighten only 8° past the pose, elbows bend up to 40° but straighten only 8°.
2. Each joint backs off as it nears its stop, and a centering spring pulls it back to neutral.
3. The **achieved** reaction torque is applied to the body; the thrusters get `τ − τ_ambac`.

Limbs can't make sustained torque, so AMBAC mostly trims and smooths. The thrusters do the heavy
lifting and also pay back the centering. Typical swing during a pitch command: hips ±16°,
shoulders ±9°, knees −9…+8°, elbows ±3°.

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
| Boost (full thrust) | Shift |
| Translation mode (V-HOLD ↔ NEWTON) | T |
| Rotation mode (ATT-HOLD ↔ RATE) | G |
| Hatch open / close | H |
| Cockpit / external view | V |
| Rifle ready / lower | 1 |
| Shield guard / lower | 2 |
| Look around | Mouse |

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

- 30 t dry + 10 t propellant + 6.4 t equipment ≈ 46 t. Main thrust is anime-style: 4 × 450 kN
  backpack mains + 2 × 300 kN leg mains (~5.3 G), plus 18 verniers of 40–56 kN. The backpack mains sit at the bottom of the pods, below and behind the centre of
  mass, firing down and 25° back, with 60° vectoring.
- Authority is deliberately anisotropic: strong up, weak sideways, back and down. No backpack
  verniers fire upward; down thrust comes from the shoulder tops only.
- Verified headless:
  - up, no boost: 1.37 G with no rotation
  - strafe, no boost: no rotation, ~0.55 G; with boost: rolls up to 70°, yaw stays 0°, 45 m/s
  - forward with boost: leans forward up to 70° in pitch
  - holding Shift after a strafe rolls the other way and brakes 35 → 3 m/s in ~6 s
  - the cockpit stays within ~1° in the world through all of it
  - a commanded yaw turns cockpit and suit together and stops cleanly

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
