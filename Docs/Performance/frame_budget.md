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
- ~~**FlightComputer, 2.9 ms per physics step.**~~ Broken down and cut, see the CPU pass
  below; what is left there is under "Open decisions".
- **ControlCentre, 0.29 ms for 3 chevrons.** Now drawn by the screen shader (no canvas
  drawing left, not re-measured); what remains is the per-frame
  `control_law.get_pilot_orientation()` call.
- ~~**Silhouettes, 0.37 ms.**~~ Done in the CPU pass (label-only outlines project only what
  places the label).

## CPU pass (2026-11-24): combat scene

`Tools/Profiling/combat_bench.gd` (windowed, vsync off, RX93 test range, the ν in DGFT with
the rifle drawn, master arm on, flying a gentle scripted weave, six jinking drones in view,
one locked; the suit's input is scripted, so the real sticks don't count). `silence=<path>`
turns a subtree's processing off to price it; `viewports=1` lists each viewport's render
time. Combat costs far more than the idle coast measured above (process 4.5 against 2.9 ms).

| | Before | After |
|---|---|---|
| Frame | 10.9 ms (90 fps) | 6.7 ms (150 fps) |
| Physics, per step | 5.55 ms | 4.25 ms |
| Process, per frame | 4.5 ms | 2.33 ms |
| Draw, per frame | 2.5 ms | 2.34 ms |

What was done, biggest first. Everything marked *identical* was checked bit for bit against
the old code on the live ν (harness: old script loaded beside the new, same inputs):

| Change | Saved | |
|---|---|---|
| `SensorTrack` predict / update on flat typed arrays, block sum unrolled (4.5× faster) | ~1.1 ms/step, ~0.8 ms/frame | identical |
| `ConeProjectedAllocator._solve`: gimbal projection inlined, cone trig once per solve | 1.3 ms/step (2.6 → 1.4 ms) | identical |
| Flight path marker grows and stretches in the shader (no layer redraw) | ~1 ms/frame for ~0.5 s at every speed / boost change | look kept |
| Gun circle drawn by the screen shader (`hud_gun`) | ~0.45 ms/frame while locked | look kept |
| Overhead horizon line drawn by the screen shader (`hud_aux`) | ~0.35 ms/frame | look kept |
| Label-only silhouettes (the ν's shield) project only what places the label | ~0.5 ms/frame | look kept |
| `SensorTrack.get_estimate` memoized per time and state version | ~0.15 ms/frame | identical |
| Thrust cue removed (the user's call) | ~0.6 ms/frame while boosting | — |
| Thrusters cache their swing-limit planes, the body is inverted once a tick | ~0.1 ms/step | identical |
| `FlightState.compute_authority` with its helper inlined | ~0.06 ms/step | identical |
| Thrusters set their gimbal node only when the aim moves | small | identical |
| Capability map keeps its lookup floor | ~0.05 ms/step | identical |
| Sensor line of sight reuses one ray query | small | identical |

### Where it goes now (combat bench, silenced one at a time)

- Physics 4.25 ms/step: FlightComputer 2.7 (allocator 1.45, attitude offset solver
  0.2–0.37, trim 0.21, state build ~0.2, thruster step 0.14, limb reaction 0.14, AMBAC 0.1),
  FireControl 0.6 (sensor suite 0.44), the space station 0.4 (test map, left alone).
- Process 2.33 ms/frame: HUD ~1.0 (contacts 0.44: per-contact getters and label widths
  measured every frame; FlightData 0.12), cockpit screens ~0.3 on average but ~1 ms on the
  frame a page redraws (engine page 1.1 ms per draw at 20 Hz, SA page 0.85 ms at 30 Hz).
- Draw 2.34 ms/frame: main view 0.4 ms CPU / 0.95 ms GPU, sensor camera 0.52 / 0.54,
  outline overlay 0.11 / 0.34; the rest is the renderer's own frame work on the main thread.

The per-suit cost (what every further mobile suit adds) is the physics part: ~3.3 ms a step
for the ν's flight computer and fire control. At that rate ten suits would not fit a 60 Hz
tick on one thread.

### Open decisions

- ~~**Separate render thread.**~~ On since 2026-11-24 (`rendering/driver/threads/thread_model
  = 2`), after a play test: the combat bench ran at 3.4 ms a frame (290 fps) against 6.8 ms.
  Godot calls the mode experimental ("can lead to project crashes or instability") and logs
  five errors at startup (`_texture_2d_update` on an empty image, `finalize` off the render
  thread). A crash, garbled text, or a HUD symbol trailing what it marks: try `Safe` (1)
  first. With it on, the phase split above (process / draw) no longer adds up to the frame:
  draw runs beside the main thread.
- ~~**Allocator step size.**~~ Done 2026-11-24: `ConeProjectedAllocator.tight_step`, the ν at 40
  iterations, the old accuracy (Docs/FlightControl/summary.md; tried at 30 first: physics
  4.25 → 3.84 ms a step in GDScript, but a little soft in the hard directions).
- ~~**Native code for the flight computer.**~~ Done 2026-11-24: `Native/` (C++ GDExtension,
  bit-identical to the GDScript, which stays as the fallback): the allocator solve and trim,
  the sensor track's predict / update, the capability map lookup. Physics 3.84 → 2.5 ms a
  step; one ν's flight computer and fire control 3.3 → ~1.55 ms. What is left there is spread
  thin (state build 0.26, control law 0.23 of which the attitude solver ~0.2, thruster step
  0.15, limb reaction 0.14, AMBAC 0.1; fire control 0.45), mostly engine calls.
- **Cockpit screen rates.** The engine page (1.1 ms a draw) at 10 Hz and the SA page at
  20 Hz would halve their cost and their per-frame spikes.

## Pitfalls when measuring

- Disabling a subtree makes frames faster, which lowers physics steps per frame, so
  whole-frame savings overstate every subtree and add up to more than the frame. Split
  per step and per frame (as `phase_groups.gd` does).
- `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` are the worst frame of the last
  second, not an average.
- Headless runs skip all render submission and sleep `low_processor_usage_mode_sleep_usec`
  per frame (set it to 0). They show script cost only.
- Jolt's `get_process_info()` always returns 0. Time the physics phase from signals instead.
- The real sticks reach a windowed test run: the suit's own input reads them, and so does
  the mouse-look controller's mini-stick pan. Make the input inert (`set_script` to the
  base `PilotInputSource`, or swap in a scripted one) and stop the MouseLookController's
  processing, or a hand on the stick skews the numbers and the views.
- `fbw_probe` is not repeatable to the last digit (frame-rate dependent parts feed the
  physics): two runs of the same code differ by about as much as small real changes. Use it
  for "within noise", and a direct old/new harness for "identical".

## Zoom window (2026-11-17)

`Tools/Profiling/zoom_cost.gd` (windowed, vsync off, main scene, a drone locked ahead, ×16):
the zoom camera itself is cheap (0.2 ms CPU, 0.2 ms GPU, 640×480). Drawing its frame and
level cells on the HUD canvas cost ~1.3 ms of script a frame plus the canvas render, +3.9 ms
in all (115 → 79 fps). Drawn by the screen shader instead (`composite_zoom_frame`), opening
the zoom costs +0.5 ms (116 → 110 fps). Lesson as for the contact triangles: symbols that
only move or scale belong in the shader, not on the per-frame canvas.
