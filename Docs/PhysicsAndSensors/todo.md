# Physics and sensors: TODO

Work that came out of the close-range dodge analysis (2026-11-16): a 1500 m/s beam is
almost undodgeable inside 1 km against a perfect fire control, and more thrust can't fix
that (see `sensors.md`). The fix is realistic physics on our side and realistic sensors
on the shooter's. Separate from the weapons pass (`Docs/Weapons/todo.md`).

## 1. Physics

- [x] Every part of the model has a mass, and the propellant sits in tanks around the body.
      The centre of mass and inertia follow the pose and the tanks, and the hull recoils so
      the suit's centre of mass stays put. Legs and waist are measured like the arms (no more
      guessed joint inertias). See `mass_model.md`.
- [x] AMBAC joints were limited by angular acceleration only. Done for the legs and waist:
      a torque rating (`AmbacJoint.max_torque`, the peak torque they were tuned with), and
      acceleration = torque / inertia, so a heavier limb swings slower. Arms still use their
      acceleration limit: rate them too once their actuators are sized.
- [x] Yaw turns were about half as quick as before the mass model (the collision boxes gave
      half the real yaw inertia). Clean yaw torque is a layout limit (~8 MN·m, every small
      port saturated; the fore/aft nozzles sit only ±1.25 m off the centreline): wider
      shoulder swings or 3× side-skirt thrust add at most 18%. But it holds all of it while
      pushing at 4 G, where the turn-rate cap assumed 60%: `loaded_torque_share` is per axis
      now, yaw 1.0. Boost + 1 s yaw 49° → 70°, full boost 62° → 91° (was 96 / 75 before the
      mass model); stops take 0.42–0.48 s after release (was ~0.3). More would need AMBAC:
      a stronger waist twist, and AMBAC planning with each joint's full 3D reaction (a leg
      scissor makes yaw, which AMBAC's single-axis model doesn't know).
- [ ] Forward boost now pitches the suit (up to ~38°/s, 22 m in the first second, was 24.5):
      the real centre of mass is 1.2 m below the old guess, under the mains' line of thrust.
      Look at the pods' fore/aft range or the stance for forward pushes.
- [ ] The loadout is lopsided (shield on the left forearm, fin funnels on the left of the
      backpack): the centre of mass sits 0.6 m left of the centreline full, 1.0 m empty.
      The FBW trims it, at some cost in thrust. Check it in flight; jettisoning the funnels
      or the bazooka should shift it back.
- [ ] Jettison equipment (bazooka, funnels, shield): drop the part from the mass model and
      the payload, push the suit by the release impulse.
- [ ] Off-diagonal inertia isn't applied: Godot takes principal moments along the body axes
      only. The products of inertia are ~5–10% of the diagonal (`mass_model_probe.gd report`).
      Either accept it or rotate the body's inertia frame.
- [x] `Docs/FlightControl/summary.md`'s RX-93 thruster table showed the design ratings, not
      the scene's thrusts (× 63.0 / 59.5). Done, with the capability re-measured.

- [ ] Reliable lateral dodges (2026-11-16). Up dodges everything on the cue (~9 G); sideways
      (3.6 G) fails inside ~500 m: a dodge has the rest of the enemy spool plus the flight
      time (0.45 s at 300 m, 0.58 s at 500 m) to clear ~8 m, so it needs ~8 G within ~0.15 s.
      Tried and reverted, AMBAC leg stances for full-boost strafes:
      - A leg swing rolls the body only ~a quarter of the swing (each leg is ~13% of the roll
        inertia): 45° / 15° on the two hips rolled the free body 7.8°, 60° on both ~15°.
        Pointing the mains sideways needs 45–90° of roll, so the thrusters must do most of it.
      - Far leg out 45° aims its sole / calf / shin nozzles sideways: clean sideways 3.7 → 5.0 G
        (60°: 5.2, 90°: 5.25), but its swing rolls the body against the FBW's strafe roll:
        half acceleration took 0.58 s (was 0.18), 12.6 m in 1 s (was 14.8).
      - Near leg out rolls the right way: onset 0.15 s, roll 71°/s (was ~50), but tops out at
        4.9 G under the 30° roll cap. With the cap at 60–90° a full-boost strafe holds 7.4 G
        (was 5.8: the mains really push sideways), yet the roll takes most of a second: 2.4 m
        in 0.5 s, 11.7 m in 1 s, and a full-boost reversal fell to 2.1 m in 1 s.
      Every variant moved 2.1–2.6 m in the first 0.5 s. Rotation costs time a dodge doesn't
      have; sideways at close range needs direct sideways thrust and a faster onset:
      - [ ] "Break" input: full clean thrust in the commanded direction at once, no velocity-
            loop ramp, no attitude change (today 2.4 m in 0.5 s where 3.7 G alone gives 4.5).
      - [ ] Main pods swinging sideways (a second pod axis, ±30–45°), measured first in the
            capability probe, then a model / bone change.
      - [ ] Optional: a 60° roll cap for a sustained full-boost sideways sprint (7.4 G), not
            for dodging.

## 2. Sensors (DGFT)

Pilot locks, the sensors and fire control do the rest. Laser rangefinder on in DGFT only.
First pass built: `Entities/Vehicles/Components/Sensors/`, see `sensors.md` ("As built").

- [x] `SensorTrack`: Singer-model Kalman filter (position, velocity, acceleration), timed
      measurements with latency, gating, tentative / firm / coast / lost.
- [x] Main camera: narrow (telescope) and wide fields on a gimbal with neck-like limits and
      slew, line-of-sight check, visible-centroid wander.
- [ ] The model's head should turn with the main camera's gimbal (it only follows the vulcans).
- [x] Laser rangefinder boresighted to the main camera, DGFT only, needs a narrow-field track.
- [ ] Laser warning on the target side (the suite already knows when it is lasing).
- [x] Body cameras: six hemispheres, coarse, own line of sight; fallback track.
- [x] Stereo range from the twin eyes, and known-size range as a last resort.
- [x] Fire control and weapons read the track; lead with the estimated acceleration; no
      solution until firm; the lock drops when the track is lost.
- [x] HUD: ACQUIRING / COAST where it said NO SOLUTION.
- [ ] HUD: impact-uncertainty circle on the pipper (`FireControl.get_target_covariance_ahead`).
- [ ] Practice turret and drones use the same track filter (they still aim with truth).
- [x] Probe: hit rate against a jinking drone, sensor vs perfect track (`track_probe.gd`).
- [ ] A drone that dodges like a pilot: changes thrust when the shooter's barrel lights up
      (spool cue), so the probe measures the dodge the design is about, not a timer.
- [ ] Shoot-cue report: "the SHOOT cue sits far off the real target after locking and moving
      off". Not reproduced (`weapons_snapshot.gd offaxis`: lead, gun and shot agree while
      turning and strafing). The lead does move off the target as the suit's own speed grows
      (3.4° at 190 m/s, 900 m), because the beam keeps the suit's velocity. Need the exact
      situation (speed, range, weapon, target moving?) from a flight.

## 3. Later (BVR)

- [ ] Minovsky density field: radar range and radio datalinks fall off with it.
- [ ] IR: plumes visible far away, coasting suits hard to see.
- [ ] Laser datalink: wingmen's bearings triangulate range.

## 4. Related (damage, for the weapons list)

- [ ] The shield works like an extra life (a beam destroys any part in one hit). A beam-
      coated shield that ablates instead: each hit takes coating in proportion to how
      squarely it lands; glancing hits mostly deflect.
