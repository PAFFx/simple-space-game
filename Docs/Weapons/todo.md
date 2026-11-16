# Weapons pass: TODO

Feedback from the first flight test of the weapons pass (2026-11-15). Too big to do at once:
fix bit by bit. Details of what's done are in `Docs/FlightControl/summary.md`.

## 1. Weaponry

- [x] Beam FX isn't what it should be: rework the look.
      Done: the rifle fires two beam types (weapon hat forward = PULSE, forward again =
      LINEAR; the shield missiles moved to hat left). PULSE (ours and the turret's) is a short,
      fat, boiling burst of energy with a few short streaks, no long wake; LINEAR is a long
      beam, white core in a thick ragged red sheath.
- [x] Beam speed is definitely too fast: slow it down. Done: pulse 4000 → 3000 m/s,
      linear 3200 m/s.
- [x] Vulcan RPM / ammo. Done: 640 rpm per gun (two guns firing in turn, 1280 rpm), 300
      rounds in all (was 2000 rpm, 1200 rounds).
- [x] Shield missile explosion radius is very small; it can't be used to force a manoeuvre.
      Done: blast 45 → 90 m, proximity fuse 14 → 25 m; the light sphere grows to the blast.
- [x] Destruction FX should be much better. Done: explosions are spheres of light (a big
      white-hot ball, smaller balls bubbling out around it, cooling and fading).
- [x] Beams need a spool-up time that can be seen from afar: that is the dodge cue.
      Done: every beam (ours and the turret's) glows on the barrel while it spools: pulse
      0.3 s, linear 0.9 s, turret 0.5 s. The trigger has to be held through the spool; letting
      go early drops the shot. One shot per pull: press again for the next. Longer cooldown
      after a shot (pulse 2 s, linear 5 s, shared: one barrel). E-pack 12 → 32, shared:
      pulse uses 1, linear 3.
- [x] A launched projectile like the beam shouldn't lag behind the barrel that fired it: for a
      long beam type it should follow the barrel for a bit while it dissipates.
      Done: LINEAR is a straight beam from the barrel for 0.6 s that swings with it like a
      laser, its front still advancing at 3200 m/s (reach 1.9 km); the lead accounts for the
      front's head start. Let go, it stays where it was and breaks up over 0.45 s. When the
      lock drops (target destroyed) the barrel holds its aim for 0.8 s, and for as long as a
      linear beam is still coming out, instead of swinging back to the boresight.
      Charge and muzzle glows ride the muzzle where it is drawn (physics-interpolated), so
      they no longer stutter behind a moving gun; the charge is a boiling knot with arcs.

## 2. Physics

- [x] Bump up the ν's side thrusters: it's very slow sideways, and an MS should be a highly
      manoeuvrable machine. Allow a 3D vector on the main backpack thrusters (the backpack's own
      vectoring stays 2D, but the thrusters can move in 3D). Currently the only reliable dodge is
      forward or upward.
      Done: small ports re-rated by their size (sideways 2.3 → 3.5–3.7 G, down 0.8 → 1.6 G), the
      mains' nozzles swing up to 10° sideways, outward only (the pod channel and the bazooka
      allow no more); boosted strafe 8 → 14 m in its first second.
- [x] The arm movement for the shield and rifle doesn't go into AMBAC / Newton's third law: no
      thruster fires and no other limb balances it. The MS should have gone into a spin by now
      with these motions.
      Done: LimbReaction measures the arms, head, pods, rifle and shield from the final pose and
      pushes the body back; AMBAC and the thrusters counter it (≤ 0.5° over the test sequence),
      the aim accelerates (600°/s²) instead of jumping to full speed.
- [x] A full-boost strafe rolls the ν ~60° and takes about a second to roll back over when the
      strafe is reversed (it first keeps going the old way for ~0.5 s). The roll-over is throttled
      by the FBW's tracking-lag guard, not by thrust: look at faster swings for reversals.
      Done: faster swings only stole thrust from the push. Instead the mains' nozzles swing
      sideways on their own at 240°/s, and a strafe rolls at most 30°: full-boost reversal
      1.0 → 7.1 m in its first second, going the new way at once.
- [x] Holding a lock at rest kept many thrusters pulsing and the suit jittering, even in
      coupled mode. Done: the measured limb momentum is smoothed (frame / tick timing noise),
      and AMBAC leaves the waist alone while an arm weapon aims (its twist made the aimed arm
      swing back, which needed countering again). Body rate 0.5 → 0.004 °/s, no visible firing.
- [x] The mains' nozzles swing up to 10° sideways (outward), but their meshes belong to the pod
      (fore/aft only): give each nozzle its own bone so the swing shows, not just the plume.
      Done: each cup has its own bone under its pod, pivoting at its throat, turned by its
      thruster's sideways gimbal (`ThrusterGuard.follow_yaw`); it stays inside the pod channel.

## 3. HUD

- [ ] SOI symbology on both the panoramic screen and the MFD isn't what it should be.
- [ ] TMS and HMCS cursor UI are bad.
- [ ] Locked target and enemy symbology need improvement.
- [x] In DGFT / BVR the MS body and weapons should actually be visible through the panoramic
      screen; the shield and funnels stay outlines only.
      Done: in DGFT / BVR the rifle and the arms show as outlines (`Layers.SENSOR_COMBAT`,
      skinned outlines for the arms); the body is hidden (the whole body blocked too much
      while manoeuvring). The full body is still on `SENSOR_BODY_PARTS`, kept for close combat
      (`FireControl.show_body_in_weapons_mode`).
- [ ] Remove the HIT / BLOCK cue from the HUD: it belongs in a debug menu, not the real UI.
- [ ] Mode, weapon and armed status on the panoramic screen need improvement.
- [ ] Targeting envelope UI needs improvement.
- [ ] We shouldn't be able to see or target contacts behind an obstacle.
- [ ] SHOOT / off-target UI needs improvement.
- [ ] DGFT mode needs a more visible cue than the small DGFT mode label.
- [ ] The TMS cursor can only reach about half the cockpit: it should go anywhere.
- [ ] Long-range targets aren't lockable.
- [ ] The shoot cue sits a bit in front of the target, so when the MS moves away the cue is out
      of place instead of on the target.

## 4. Animation

- [x] Add a lot more joints so both the rifle and the shield are more manoeuvrable; joints
      other than the arm can also help widen the targeting envelope.
      Done: collarbones (chest → clavicle → shoulder armour / upper arm), the wrist in the aim
      chain, and a shield swivel (`shield_mount.L`, spins about the outward axis at the
      forearm bracket). `MsWeapon.aim_assist_bones` spread the turn: rifle collarbone 25% ≤ 12°,
      wrist 30% ≤ 25°; shield missiles collarbone 25% ≤ 12°. The rifle is held low with a bent
      elbow that straightens toward the edges; its envelope widened to az −55…+90, el −60…+65
      (the HUD outline follows `az_limits` / `el_limits`).
- [x] Shield is bad: it clips through the body. The design where it follows the pilot's look is
      also bad: it should just be posed. Increase the shoulder joint's range, and let the shield
      itself rotate around its attachment point, so it can protect more than the abdomen.
      Done: one dug-in pose (the waist turns the left side 30° forward, the shield stands
      upright on its swivel in front; the hips stay, turning them kicked the hull 17°; legs
      free for AMBAC). The shield is solid (shots stop on it, own weapons hold fire into it:
      MASKED); the rifle's envelope shrinks while it is up; the head loses the target behind
      it and a body camera tracks.
- [x] Look at the shoulder armour blocking the way (it can definitely be moved).
      Done: it followed AMBAC angles only, so the pose and the aim never moved it. Now it follows
      the arm's final pose (`LimbFollower.from_pose`): all of its fore/aft swing, half its
      sideways one.

## 5. Model

- [x] Remove the switches and the hatch panel next to the armrest. The switches aren't needed
      and the hatch panel can move elsewhere (ideas TBD). There should only be an armrest, not a
      panel that blocks the view.
      Done: armrests only; the hatch is two seat-side pull handles (lock, then override), after a
      fighter's seat arming handle: Docs/MobileSuit/linear_seat_v2_cockpit.md.

- [x] Beams should feel scarier up close. Tried on the panoramic screen (white-out,
      exposure dip, after-image streak) and removed: it read as weird. Instead the beams light
      the cockpit harder (CockpitBeamGlow). Sound is out of scope for now.
- [x] The suit's own overlay (arm / rifle outlines now, the body for close combat later)
      resolves in from blue blocks that halve in size until sharp, and breaks up the same way,
      on a mode change or when what it shows changes. Done: SensorHead draws it with a second
      camera on its own transparent image (`set_overlay`); the panoramic screen pixelates it
      by `overlay_reveal` (in 0.5 s, out 0.3 s). The whole silhouette pixelates, not just
      the rim: the outlines mark their body with a faint fill (`SensorOutline.fill_alpha`),
      counted while resolving and dropped once in.

## 6. Graphics

- [x] Anti-aliasing: things far away (enemies included) are hard to see. Done: MSAA 4×
      (`rendering/anti_aliasing/quality/msaa_3d`), also on the sensor head's viewport, which
      is what draws the outside world onto the panoramic screen.
- [x] MFD pages unreadable: the page is drawn far larger than it shows, with no mipmaps.
      Done: the screens area-filter it (`mfd_screen.gdshader`, 4×4 samples per pixel).
- [ ] Far suits may still be sub-pixel at long range even with MSAA: if so, look at a
      minimum on-screen size or a contact glint for far hostiles.
