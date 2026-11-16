# Sensors and targeting (DGFT first)

Design for replacing the fire control's perfect knowledge of the target with what the suit's
sensors can actually measure. Status: design, nothing built yet (see `todo.md`).

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
