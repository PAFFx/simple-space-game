# Sensors and targeting (DGFT first)

Replacing the fire control's perfect knowledge of the target with what the suit's sensors
can actually measure. Built (first pass): `Entities/Vehicles/Components/Sensors/`
(`SensorSuite`, `SensorTrack`), read by `FireControl` and `MsWeapon`. What's left is in
`todo.md`.

## Why

`FireControl._track_target` reads the locked target's `linear_velocity` straight from its
`RigidBody3D`. The lead is therefore perfect, and against a perfect lead only acceleration
the shooter can't foresee makes a shot miss: `miss = ½·a·t²` for a time of flight `t`. With
a 1500 m/s beam:

| Range | Flight time | Acceleration needed to clear 4 m |
|---|---|---|
| 300 m | 0.20 s | 20 G |
| 500 m | 0.33 s | 7.3 G |
| 700 m | 0.47 s | 3.7 G |
| 1 km | 0.67 s | 1.8 G |
| 2 km | 1.33 s | 0.5 G |

The ν's clean authority (measured, `Tools/Flight/capability_probe.gd`, 69 t full):
up 8.95 G, forward 6.59, right 3.68, left 3.53, back 3.94, down 1.57. A human in a linear seat
won't take much more than ~9 G, so more thrust can't make close range survivable. What
decides close range has to be the shooter's ability to know where the target is going, as in
a real gun fight.

## Principles

- **Minovsky interference** kills radar and radio at combat densities, so DGFT targeting is
  optical: cameras for angles, a laser rangefinder for range. Radar and datalinks are BVR
  topics, left for later.
- **UC main cameras are very good.** The head's telescopic main camera gives angles to
  ~20 µrad: about 2 cm at 1 km. Noise in the measurement is not what makes shots miss.
- **What makes shots miss is time.** The camera measures direction now. The fire control has
  to estimate velocity and acceleration from a history of measurements, and every step in
  the chain adds delay. A target that changes its thrust after the solution is formed is
  missed by about `½·Δa·(L + t)²`, where `L` is the whole reaction chain (frame, image
  processing, filter response, arm slew, trigger and spool) and `t` the flight time.
- **The pilot only locks.** Designating and committing the lock is the pilot's job. From
  then on the sensors and the fire control do everything: the head turret keeps the target in
  the main camera, the rangefinder lases, the filter tracks, the arm aims at the lead. No
  manual ranging, no manual lead. The pilot flies the suit so the target is inside the
  weapon envelope, and pulls the trigger.

## Sensors on the suit

| Sensor | Where | Measures | Quality | Notes |
|---|---|---|---|---|
| Main camera, narrow (telescope) | head, behind the visor | azimuth / elevation | σ ≈ 20 µrad, 60 Hz, ~40 ms processing | ~2° field. Slews with the head (neck limits and rate). The only sensor that can hold a precise track. |
| Main camera, wide | head | azimuth / elevation | σ ≈ 0.3 mrad, 60 Hz | ~60° field. Reacquires a target that left the narrow field. |
| Stereo pair | head (twin eyes, ~0.4 m apart) | range | σR = R²·σθ / B: ±1 m at 150 m, ±50 m at 1 km | Free and silent, good only close in. |
| Body cameras | chest, shoulders, skirts, backpack, legs (some visible on the model, more placed where it shows none) | azimuth / elevation | σ ≈ 1 mrad, 30 Hz, ~60 ms | Fixed, wide, lower grade than the main camera. Together they see all around: awareness, contacts, and a degraded track when the head can't look. |
| Laser rangefinder | head, boresighted to the main camera | range | σ ≈ 0.5 m, 10 Hz, to ~15 km | **On in DGFT only.** Needs the target in the narrow track (beam ~0.5 mrad). The target's laser warning receiver sees it, with a bearing. |
| Known size (optional) | software | range from angular size | ~5% | Needs the target type identified; a fallback when nothing better is available. |

BVR (later): radar whose range scales with the local Minovsky density, IR for thruster
plumes at long range, laser datalink triangulation between wingmen.

### What each sensor tick does

1. **Can it see the target?** The target must be inside the sensor's field (for the main
   camera: where the head can point it), and a ray to it must be clear (debris, stations,
   the suit's own body for body cameras). Visibility can later depend on lighting: sun
   behind the target, planet shadow, beam flashes and plumes.
2. **Measure.** Direction to the target's *visible centroid* (not its centre of mass, which
   the camera can't see), plus noise. The centroid wanders slowly as the target's limbs
   move and its plumes flare (a correlated error of a few % of its size, τ ≈ 0.3 s).
3. **Delay.** The measurement is stamped with its capture time and delivered after the
   sensor's processing latency.

Range comes from the best source available that tick: rangefinder > stereo > known size.

## The track filter

One track per contact, a Kalman filter with a Singer motion model: position, velocity and
acceleration, the acceleration a random process that decays over τm ≈ 0.5–1 s (how long a
suit holds one thrust). Each measurement arrives with its covariance (angles × range plus
the range error), converted to a Cartesian point (converted-measurement KF, linear update).

- **Predict** to the measurement's capture time, **update**, predict on to now. Delivery
  latency becomes track lag with no special case.
- **Gate.** A measurement far outside the predicted uncertainty (Mahalanobis distance) is
  rejected. A hard jink can break the track: that's how real trackers are beaten.
- **States:** tentative (a few hits) → firm (lockable) → coast (no fresh measurement,
  uncertainty grows) → lost. Lock needs a firm track and drops after ~1 s of coasting.
- **Automatic reacquire.** In coast the head points at the prediction, the wide field and
  the body cameras search, and a measurement inside the grown gate brings the track back
  without the pilot doing anything.

### Head turret

The main camera is only as good as the head's ability to keep the target in its 2° field.
The head has the neck's limits and a slew rate and acceleration. Close in, the line of
sight swings fast (a target crossing at 100 m/s at 200 m moves 29°/s, more with the
shooter's own manoeuvres). When the line of sight moves faster than the head can follow,
the target drops to the wide field (worse angles), then to the body cameras, then coasts.
That's what makes very close fights messy without inventing inaccuracy.

## Fire control with a track

- `FireControl._track_target` → reads `track.position / velocity / acceleration` instead of
  the target body.
- `MsWeapon._solve` → intercept from the estimate, `p + v·t + ½·a·t²`.
- The estimate's covariance, carried forward to the time of flight, gives the expected
  impact spread. Drawn as a circle around the pipper: the pilot sees how good the
  solution is before pulling the trigger.
- With the acceleration estimated, a steady boost is no dodge: only a *change* of thrust
  is. Holding a long burn is predictable, and that's when to shoot. Cutting thrust when the
  shooter expects the burn to continue is a feint that makes the solution overshoot.

## The dodge budget

With the reaction chain `L ≈ 0.2 s` and a 1500 m/s beam, the miss from a fresh jink:

| Range | 3 G (strafe) | 8 G (mains) |
|---|---|---|
| 300 m | 2.4 m (hit) | 6.3 m (barely a miss) |
| 500 m | 4.2 m (borderline) | 11 m (miss) |
| 1 km | 11 m | 30 m |

So long range stays hittable with the rangefinder (the main game), 300–700 m is decided by
who manoeuvres unpredictably and who fires at the committed target, and inside ~300 m the
beam wins: the defence there is denying the angle (outside the enemy's head and arm limits,
behind the shield) and the saber. `L` is the main tuning knob, built from real delays
rather than invented inaccuracy.

## Enemy side

The same parts work in reverse: being lased sets off a laser warning with a bearing, and a
burning suit is easy to see (plumes), a coasting one hard. The practice turret and drones
should use the same track filter, so the player can dodge them the way they'd dodge a suit.

## Verification

Extend `Tools/Weapons/weapons_probe.gd` with a jinking drone (acceleration and direction-
change interval set per run) and measure hit rate across range, jink acceleration and `L`,
until the table above shows up in practice.

## As built (first pass)

- `SensorSuite` (on the RX-93, stepped by `FireControl` each tick between reading the lock and
  the weapons solving) holds the sensors and the track on the locked target. Without one, a
  suit keeps the old perfect knowledge.
- **Main camera**: a gimbal in the body frame (azimuth ±100°, elevation −40…+50°, 220°/s,
  1500°/s²) pointed at the track's prediction, or at the pilot's designation before there is
  one. Narrow field ±1°, σ 20 µrad; wide field ±30°, σ 0.3 mrad; 60 Hz, 40 ms latency; a ray
  from the eye must reach the target. The model's head doesn't turn with it yet.
- **Laser rangefinder**: DGFT, target in the narrow field, within 15 km: a pulse every 0.1 s,
  σ 0.5 m, sent with that tick's angles. Between pulses the range is the best of stereo (σ =
  R²·σθ / 0.4 m) and known size (10%). Aging a pulse with the track's velocity fed the track's
  errors back into it and broke tracks; the filter blends the sources by their errors instead.
- **Body cameras**: six (chest, backpack, shoulders, front and rear skirts), each a
  hemisphere, σ 1 mrad, 30 Hz, 60 ms, with their own line of sight. The shoulder ones look
  45° forward of sideways. Lines of sight ignore the suit's hull but not its shield: dug in
  behind it, the head loses the target and the right shoulder camera holds the track.
- **Visible centroid**: wanders 2% of the target's radius about its centre, smoothly (two
  first-order stages, τ 0.8 s each). The wander is in each measurement's covariance; without
  it honest measurements failed the gate. The first version (4%, one stage, τ 0.3 s) jumped
  every tick: the track read it as velocity, and on a still target at 30 m the aim swung at
  ~12°/s and the thrusters fought the arms (`Tools/Weapons/track_jitter_probe.gd`).
- **Track** (`SensorTrack`): 9-state Singer filter (τm 0.8 s), gate d² 16, three
  rejections in a row restart it. Adaptive process noise: σm 6 m/s² while the measurements
  fit a steady target, opening at once to 30 m/s² (the acceleration's variance grows with
  it, so the estimate follows from that update) when the smoothed d²/3 climbs toward 2, a
  measurement fails the gate, or the whitened innovations lean one way (running mean,
  weight 0.15, normalised to 1 for a steady target, full at 2.5: a steady jink shows that
  way long before it shows as large innovations); settles back over 0.6 s.
  Still target, still suit (`track_jitter_probe.gd`), old → new: velocity error 4.4 → 0.5
  (30 m) / 2.4 m/s (300 m+), acceleration 13–15 → 0.8 / 5 m/s², aim rate at 30 m 200 → ~15
  mrad/s, commanded torque 1430 → 62 kN·m (30 m), 265 → 29 (300 m). Beyond ~300 m the stereo
  range noise still half-trips the lean test (manoeuvre ≈ 0.4); not chased further.
  Jinking drone, hits of 72 (same day, `track_probe.gd`): 3 G old 47 / new 39, 6 G old 43 /
  new 41. Without the lean test the 3 G case fell to 25-38. Firm after 4 hits, coast after 0.25 s
  without one, lost after 1.2 s (the lock drops).
- **Fire control**: target position, velocity and acceleration come from the track; no
  solution until it is firm; the lead includes ½·a·t². The HUD shows the track's state as the lock's
  corner dashes.
- **Search tracks** (2026-11-17): every other contact the head's wide field or a body
  camera sees (line of sight clear; the suit's own shield blocks) gets its own `SensorTrack`,
  looked at 10 times a second, spread round-robin over the ticks (~0.2 ms a tick for 5
  contacts, `Tools/Weapons/search_probe.gd`). Angles from that camera; range from stereo
  close in, else apparent size: noise 10% a look plus a bias per contact (4%, wandering over
  6 s) the filter can't average out. A new contact starts coarse (angles ×25, range ×3.5,
  settling over 2.5 s). Settled, at 150 m–2 km: range 1–5% off (up to ~12%), angles
  0.03–0.1°. Locking hands the search track to the main pipeline (no fresh start);
  unlocking hands it back. A contact with no live track doesn't exist for the suit: not on
  the HUD, the SA page, or designatable. Everything the pilot sees of other contacts (HUD
  triangles, ranges, SA page, target page range, designation, cycling, nearest) comes from
  these tracks. Still from the engine: which contacts exist to be looked at, their type,
  hostile flag and size (identification, see todo §3), and the size used for size ranging.
- **Steady marks** (HUD, `Tools/Weapons/hud_steadiness_probe.gd`): an unlocked contact is
  drawn carried on by its velocity averaged over 1 s and pulled to its track at 0.8 Hz (its
  raw velocity read 3–20 m/s on a still buoy, and coasting on that made the mark hop at
  every look: 0.1–0.2°; now 0.002–0.02° RMS). A mark picks a new size at most once a second,
  only for a change over 8% (25% once the range doubt is under ~10%), and eases there over
  0.5 s.
- **Gun solution circle** (HUD): expected miss at the time of flight = √((2σ prediction
  across the line of sight)² + (½·agility·t²)²), agility = RMS over ~2 s of how far the
  estimated acceleration across the line of sight strays from its recent average (a steady
  thrust is predictable; a changing one isn't). Radius = 1.3 × the triangle's half side ×
  √(1 + (miss / target radius)²). `Tools/Weapons/circle_probe.gd` prints the terms: the test
  drones barely jink once at their speed cap (true high-passed accel 3–17 m/s²), so the
  circle stays within 1.0–1.5× its least size against them; a 6 G jink changing every half
  second (~40 m/s²) at 0.66 s flight time would put it near 1.6×.

### Hit rate against a jinking drone (`Tools/Weapons/track_probe.gd`)

PULSE at 1500 m/s, the suit holding still, 12 shots per cell, each fired at SHOOT (firm
solution, barrel on the lead); the drone (7 m radius) changes to a random acceleration of
0.5–1 × the jink G every 0.8–2.2 s. Hits out of 12 (±~2 from sampling alone):

| | 300 m | 500 m | 700 m | 1 km | 1.5 km | 2 km |
|---|---|---|---|---|---|---|
| Sensor track, 3 G | 7 | 7 | 10 | 8 | 9 | 6 |
| Perfect track, 3 G | 7 | 6 | 8 | 7 | 6 | 10 |
| Sensor track, 6 G | 7 | 8 | 8 | 5 | 7 | 6 |
| Perfect track, 6 G | 7 | 9 | 9 | 8 | 9 | 6 |

The sensor track is as good as perfect knowledge here (no track breaks; its acceleration
estimate even makes up for its delay). The drone holds each thrust for 0.8–2.2 s, which the
filter learns in ~0.2 s: against a target that jinks on a timer, the sensors give the
defender little. What decides a hit is timing: the 0.3 s spool (visible to the target),
the flight time, the arm's slew, and whether the thrust changes while the shot is out.
So the defender's lever is to change thrust when the enemy's barrel lights up, not
to keep thrusting hard. Close in (300 m) the arm's slew loses about as many shots as the
jink does.

### Dodging on the cue, both ways

**The drone dodges us** (`track_probe.gd dodge=6 reaction=0.25`): on top of its 3 G jink it
watches our rifle and, 0.25 s after the spool starts, thrusts at 6 G across the line of
sight. PULSE 1500 m/s, sensor track, hits out of 12:

| | 300 m | 500 m | 700 m | 1 km | 1.5 km | 2 km |
|---|---|---|---|---|---|---|
| Jink only (above) | 7 | 7 | 10 | 8 | 9 | 6 |
| Jink + dodge on the cue | 5 | 2 | 3 | 3 | 0 | 0 |

**We dodge the turret** (`dodge_probe.gd`): the turret leads from its own sensor track of the
suit (0.1 mrad, 1 m range, 50 ms, leading with the estimated acceleration), 1500 m/s bolts
after a 0.5 s spool. The scripted pilot reacts 0.25 s after the glow and full-boosts across
the line of sight for 0.8 s, then brakes. Hits out of 10:

| Pilot | 300 m | 500 m | 1 km | 2 km |
|---|---|---|---|---|
| Sits still | 10 | 10 | 10 | 10 |
| Boosts up (the mains, ~9 G) | 0 | 1 | 0 | 0 |
| Boosts left or right (~3.6 G) | 10 | 7 | 0 | 0 (of 7) |

- The cue is everything. Reacting to the spool beats any filter: the shooter commits its
  aim when the shot leaves, the defender has already started moving, and the remaining
  spool plus the flight time is the dodge window. Dodging up, on the ν's strongest axis,
  works even at 300 m. Sideways (~3.6 G) only works from about 500 m out.
- A shooter that wants hits at range has to deny the cue: a shorter or hidden spool, shots
  fired when the target can't move freely (mid-burn, braking), or many shots at once.
- The turret stopped firing once at 2 km after sideways dodges (its track went bad and never
  came back firm): the probe now has a time limit per case and reports shots resolved.
