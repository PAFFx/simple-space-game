# Thrust Sizing — How Strong Should a Mobile Suit's Thrusters Be?

Background for the thruster ratings in `Tools/Godot/build_rx93_scene.gd` (`THRUSTERS`,
`THRUST_SCALE`). Real numbers are rounded, from public SpaceX figures as of 2026.

## Reference: Raptor

| Engine | Exit Ø | Thrust | Isp | Thrust per m² of exit |
|---|---|---|---|---|
| Raptor Vacuum (RVac) | ~2.3 m | ~2.7 MN | ~380 s (vac) | ~0.65 MN/m² |
| Raptor 3 (sea level) | ~1.3 m | ~2.75 MN | ~350 s (SL) | ~2.1 MN/m² |

RVac and sea-level Raptor make about the same thrust, yet RVac's bell is much bigger. The
bell doesn't make thrust, it makes efficiency.

## Thrust comes from the throat, not the bell

    F ≈ C_F · p_c · A_t

- `p_c`: chamber pressure (Raptor ~350 bar, the highest of any engine flying).
- `A_t`: throat area.
- `C_F`: thrust coefficient, ~1.6–1.9. A bigger exit (higher expansion ratio) only raises
  it a little. That buys Isp in vacuum, not much thrust.

So comparing a suit nozzle with RVac by size is misleading. The fair comparison is thrust
per exit area against the dense sea-level engine:

- ν main nozzle cup: 0.88 m (0.61 m² of exit).
- At Raptor 3's density (~2.1 MN/m²), that cup gives **~1.26 MN**. That's today's tech.
- With future materials at ~2× Raptor's chamber pressure (~700 bar), the same cup gives
  **~2.5 MN**.

A ~2 MN main in a 0.88 m cup is a believable "future Raptor".

## Same technology everywhere: scale all ports together

A higher rating at the same nozzle size means a higher chamber pressure: a technology level.
The small ports would use the same technology as the mains, so every thruster scales by the
same factor. The ratings in `THRUSTERS` already follow the port sizes, so one factor keeps
their ratios. The allocator and auto-rotation tuning (which depend on those ratios) stay
roughly where they were, and torque authority scales with the force.

Ports keep their rating in `THRUSTERS` (design ratios, sized by nozzle). The factor lives in
`THRUST_SCALE`, so `MAIN_RATING_KN` still picks out the vernier-sized ports (spool and slew
dynamics).

## The real limit is power, not thrust

The exhaust jet carries power `P = ½ · F · v_e`, with `v_e = Isp · g0`.

- Raptor: ~2.75 MN at ~3.4 km/s ≈ **4.7 GW**, and the propellant supplies that energy
  itself (it burns).
- A UC fusion-thermal thruster heats inert propellant with the reactor, so the reactor
  must supply that power. The ν runs at Isp 12,000 s (`v_e` ≈ 118 km/s):
  - one 1.06 MN main ≈ 62 GW
  - one 1.59 MN main (current) ≈ 93 GW
  - every thruster at once (19.2 MN) ≈ 1.1 TW

That's far beyond any plausible suit reactor. The game keeps it anyway (anime-strong), but if a
reactor power budget is ever added, this is the trade:

    F = 2P / v_e

At fixed power, halving the Isp doubles the thrust, and the propellant flow
(`ṁ = F / v_e`) goes up 4×. A **variable-Isp boost** follows from it (like VASIMR, run on
fusion): cruise at high Isp, and boost by injecting extra reaction mass. For example,
Isp 12,000 → 3,000 gives 4× the thrust for 16× the propellant flow, so boosting visibly
drains the tank.

Implemented for short kicks (dodges) as **pintle throats** (`FlightComputer` burst,
`Docs/FlightControl/summary.md`): just pushing harder through the same throat would need 4× the
chamber pressure, so instead a pintle pulls back and opens the throat 4× in area (2× in diameter),
at the same chamber pressure and the same reactor power (F·v_e/2 is unchanged). The gas comes out
cooler (the same power heats 16× the mass), so heat is not the limit; feeding the flow is. The
pumps are rated for the normal flow, and the rest comes from a small pressurised kick tank that
they refill; its size sets how long a kick lasts and the refill sets how often one is possible.

## G-loads

At 1.5× thrust, the ν's clean climb is about 13.5 G (2× would be 18 G), well past what a seated human can take
(~9 G for seconds, with a G-suit). Accepted on purpose: a fictional linear-seat cockpit
mechanic will let the pilot take it (planned). Until then, there is no FBW G-limiter.

## Changes

- **Nov 2026:** all ν thrusters ×1.5 (`THRUST_SCALE` 63.0 / 59.5 → 1.5 × 63.0 / 59.5). Mains
  1,059 → 1,588 kN each; 12.8 → 19.2 MN in all. That's still under the ~2.5 MN this section
  allows a 0.88 m cup, so there's room to go to 2× later (tried: climb 18 G, torque 40 / 17 /
  40 MN·m).

| At full weight (69 t, level, limbs at rest) | up | down | forward | back | sideways | torque p / y / r |
|---|---|---|---|---|---|---|
| Before (×1) | 9.0 G | 1.6 G | 6.5 G | 4.3 G | 3.6–3.7 G | 20 / 8 / 20 MN·m |
| ×1.5 | 13.5 G | 2.4 G | 9.7 G | 6.5 G | 5.4–5.6 G | 30 / 12 / 30 MN·m |

FBW unchanged and still stable (`run_fbw_probe.sh`, ×1 → ×1.5): no new overshoot or
oscillation, and stray force stays ≤ 0.24 G.

| Scenario | Before | ×1.5 |
|---|---|---|
| boost forward, distance in 1 s | 23.2 m | 27.7 m (t90 0.37 → 0.27 s) |
| full-boost strafe | 5.1 G, 15.5 m | 8.0 G, 23.3 m |
| full-boost reversal | 7.9 m in 1 s | 12.5 m |
| break right | 14.4 m in 1 s | 21.5 m |
| full yaw turn | 72° in 1 s, still 0.45 s after release | 95°, still after 0.40 s |

Movement limits on the ν ×1.5 too (`build_rx93_scene.gd`; MSP-02 keeps the script defaults):
cruise 0.8 → 1.2 G, Shift boost 7 → 10.5 G, braking 6 → 9 G. Each keeps its share of the
thrust, so auto-rotation (which leans by load = demand / capability) leans as it did before
the thrust change. Its angle limits are unchanged, so the 30° roll cap holds a Shift strafe
to ~8.6 G (reaching 90% of the target in 1.0 s instead of 0.7 s).

| Scenario (Shift) | 7 G limit | 10.5 G limit |
|---|---|---|
| forward | 7.0 G, 27.7 m in 1 s | 10.5 G, 35.5 m |
| diagonal | 6.9 G, 26.1 m | 10.4 G, 32.5 m |
| strafe right | 6.8 G, 23.2 m | 8.6 G, 23.6 m |
| down | 3.2 G | 3.2 G (thrust-limited) |
