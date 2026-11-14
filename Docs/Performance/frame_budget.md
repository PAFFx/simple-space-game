# Frame Budget

Where a frame's time goes: by phase, by script subtree and by GPU pass. A snapshot to work
from, not a live number. Re-measure before acting on it.

## Measured at

| | |
|---|---|
| Date | 2026-11-14 |
| Commit | `7bf9883` (perf: draw the flight path markers once into a shader-turned layer) |
| Engine | Godot 4.7.2-stable, `precision=double`, editor build (`godot-double`) |
| Machine | Ryzen 5 3600 (6c/12t), RTX 4070 SUPER, Linux |
| Scene | Main scene (MobileSuitTestRange), RX-93 in the linear seat cockpit, panoramic HUD on |
| State | Coasting at 300 m/s (FPM showing), no thrust input, windowed, vsync off |
| Result | ~6.9–7.9 ms per frame (126–145 fps); CPU-bound, GPU busy ~2.9 ms of it |

Tools: `Tools/Profiling/frame_phases.gd` (phases, per-viewport times; add `--gpu-profile` for
GPU passes) and `Tools/Profiling/phase_groups.gd` (cost per subtree). Both are run with
`godot-double --path . -s <script>`.

## Frame phases (main thread)

| Phase | ms/frame | Share | What |
|---|---|---|---|
| Physics | ~1.7 | ~22% | 3.6 ms per 60 Hz step × ~0.45 steps per frame at this fps |
| Process | ~4.2 | ~53% | every `_process`, mostly HUD and cockpit-screen drawing |
| Draw | ~1.8 | ~22% | render submission to the GPU (culling, command buffers, sync) |
| Rest | ~0.2 | ~3% | swap, input |

Physics runs per **step** (fixed 60/s); process and draw run per **frame**. Uncapped, the
per-frame work dominates; at 60 fps each frame carries one full physics step.

## CPU by subtree

Measured by disabling one subtree at a time against a fresh baseline. Values within
±0.05 ms are noise.

| Subtree | Cost | Share of frame |
|---|---|---|
| **suit/FlightComputer** (control laws, allocator, AMBAC solver) | **2.94 ms per physics step** | ~18% |
| **cockpit/CockpitDisplays** (3 cockpit screens) | **2.18 ms/frame** process + 0.50 draw | ~33% |
| **cockpit/PanoramicHud** | 1.64 ms/frame process + 0.23 draw | ~23% |
| ↳ hud/Attitude (numbers, overhead horizon line) | 0.48 | 6% |
| ↳ hud/Silhouettes (shield outline) | 0.37 | 5% |
| ↳ hud/Contacts (brackets + 3 text lines each) | 0.31 | 4% |
| ↳ hud/ControlCentre (3 chevrons, suspiciously high) | 0.29 | 4% |
| ↳ hud/FlightData / FlightPath / ThrustCue | 0.10 / 0.08 / 0.04 | ~3% |
| Physics server (Jolt step + moving-body upkeep) | 0.20 ms/step + ~0.9 ms/frame | ~12% |
| stage/ScifiSpaceStation | 0.30 ms/step + 0.23 ms/frame | ~5% |
| suit/SensorHeadMount (sensor camera submission) | ~0.2 ms/frame | ~2% |
| Thrusters, Ambac node, stance, pose animation, limbs, debris, buoys, lights | each ≤ 0.05 | < 3% |

## GPU by pass

From `--gpu-profile`, main view and sensor camera together: ≈ 2.9 ms total.

| Pass | ms |
|---|---|
| Opaque pass | 0.57 |
| SSAO (incl. depth prep) | 0.47 |
| Glow | 0.38 |
| Tonemap | 0.29 |
| Sky | 0.25 |
| Depth pre-pass | 0.23 |
| Canvas items (all 2D: HUD, screens, layers) | 0.11 |
| Shadows (setup + directional) | 0.09 |

Per viewport: main view ~1.2 ms GPU, sensor camera (1927×1063) ~0.85 ms; the HUD viewport,
its layers and the three screens ~0.03 ms each.

## At 60 fps with vsync

Physics 3.6 + process 4.2 + draw 1.8 ≈ **9.6 ms CPU of the 16.7 ms budget (~58%)**; GPU
≈ 2.9 ms (~17%). The test map is light on the GPU, so heavier maps will spend the GPU's
headroom first.

## Leads (not done yet)

- ~~**CockpitDisplays, 2.2 ms/frame.**~~ Done 2026-11-15: each page redraws at its own rate
  (`MfdPage.refresh_hz`: SA 30, ENG 20, TGT 2), one page per frame, and its viewport renders
  only then. Measured 2.18 + 0.36 ms (process + draw) before, ~0.4 + 0.1 ms after at
  ~170 fps. The cost now scales with the pages' rates, not the frame rate.
- **FlightComputer, 2.9 ms per physics step.** The largest fixed cost. It needs a
  per-function breakdown (allocator vs AMBAC solver vs control law).
- **ControlCentre, 0.29 ms for 3 chevrons.** Now drawn by the screen shader (no canvas
  drawing left, not re-measured); what remains is the per-frame
  `control_law.get_pilot_orientation()` call.
- **Silhouettes, 0.37 ms.** 12 projected points per outline edge every frame. Fewer
  subdivisions, or skipping when the shield hasn't moved, would cut it.

## Pitfalls when measuring

- Disabling a subtree makes frames faster, which lowers physics steps per frame, so
  whole-frame savings overstate every subtree and add up to more than the frame. Split
  per step and per frame (as `phase_groups.gd` does).
- `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are the worst frame of the last
  second, not an average.
- Headless runs skip all render submission and sleep `low_processor_usage_mode_sleep_usec`
  per frame (set it to 0). They show script cost only.
- Jolt's `get_process_info()` always returns 0. Time the physics phase from signals instead.
