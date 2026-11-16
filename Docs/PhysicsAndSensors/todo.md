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

## 2. Sensors (DGFT)

Pilot locks, the sensors and fire control do the rest. Laser rangefinder on in DGFT only.

- [ ] `SensorTrack`: Singer-model Kalman filter (position, velocity, acceleration), timed
      measurements with latency, gating, tentative / firm / coast / lost.
- [ ] Main camera on the head: narrow (telescope) and wide fields, the neck's limits and
      slew rate as its gimbal, line-of-sight check, visible-centroid wander.
- [ ] Laser rangefinder boresighted to the main camera, DGFT only, needs a narrow-field
      track. Laser warning on the target side.
- [ ] Body cameras (chest, shoulders, skirts, backpack, legs): wide, fixed, lower grade;
      fallback track and reacquire when the head can't look.
- [ ] Stereo range from the twin eyes as the silent close-range source.
- [ ] Fire control and weapons read the track, not the target body; lead with the estimated
      acceleration; lock needs a firm track and drops after ~1 s of coast.
- [ ] HUD: impact-uncertainty circle on the pipper; track state (firm / coast) on the lock
      symbol; laser warning.
- [ ] Practice turret and drones use the same track filter.
- [ ] Probe: hit rate against a jinking drone across range, jink and reaction-chain delay.

## 3. Later (BVR)

- [ ] Minovsky density field: radar range and radio datalinks fall off with it.
- [ ] IR: plumes visible far away, coasting suits hard to see.
- [ ] Laser datalink: wingmen's bearings triangulate range.

## 4. Related (damage, for the weapons list)

- [ ] The shield works like an extra life (a beam destroys any part in one hit). A beam-
      coated shield that ablates instead: each hit takes coating in proportion to how
      squarely it lands; glancing hits mostly deflect.
