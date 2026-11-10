# Flight Control — Thrusters, FBW and Allocation

## Pipeline

Every physics tick the `FlightComputer` runs one pass:

```
PilotInputSource ──PilotCommand──▶ ControlLaw ──Wrench──▶ ThrustAllocator ──u[i]──▶ Thruster × N ──apply_force──▶ RigidBody3D
 (keyboard/HOTAS/AI)  intent        (FBW logic)  F, τ      (pure math)       per-thruster  (gimbal + spool lag)
```

| Stage | Base class | Implementations | How to swap |
|-------|-----------|-----------------|-------------|
| Input | `PilotInputSource` (Node) | `KeyboardPilotInput`, `HotasPilotInput` | Replace the `PilotInput` child of `FlightComputer` |
| Control law | `ControlLaw` (Resource) | `RateCommandControlLaw` (FBW), `DirectControlLaw` | Inspector dropdown on `FlightComputer.control_law`, or `set_control_law()` |
| Allocator | `ThrustAllocator` (Resource) | `ConeProjectedAllocator`, `GreedyAllocator` | Inspector dropdown on `FlightComputer.allocator`, or `set_allocator()` |
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

| Axis | Mode | Stick means | Stick released |
|------|------|-------------|----------------|
| Rotation | `ATTITUDE_HOLD` (default) | Angular rate demand (`max_rate_deg`) | Rate → 0, then attitude captured and held |
| Rotation | `RATE_DAMP` | Angular rate demand | Rate → 0, no attitude hold |
| Translation | `NEWTONIAN` (default) | Thrust demand (cruise fraction, or 100% with boost) | Coast — Newtonian |
| Translation | `VELOCITY_HOLD` | Velocity demand in body frame (`max_command_speed`) | Brought to rest relative to the reference frame |

Torque = `I·α + ω × Iω` where `α = rate_gain · (ω_cmd − ω)`.

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
| Translate up / down | R or Space / F |
| Pitch down / up | ↑ / ↓ (stick-forward convention) |
| Yaw left / right | ← / → |
| Roll left / right | Q / E |
| Boost (full thrust) | Shift |
| Translation mode (NEWTON ↔ V-HOLD) | T |
| Rotation mode (ATT-HOLD ↔ RATE) | G |
| Hatch open / close | H |
| Cockpit / external view | V |
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

## Tuning reference (prototype suit)

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
