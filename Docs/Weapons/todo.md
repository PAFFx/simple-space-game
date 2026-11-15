# Weapons pass: TODO

Feedback from the first flight test of the weapons pass (2026-11-15). Too big to do at once:
fix bit by bit. Nothing here is started.

## 1. Weaponry

- [ ] Beam FX isn't what it should be: rework the look.
- [ ] Beam speed is definitely too fast: slow it down.
- [ ] Vulcan RPM should go up by a lot.
- [ ] Shield missile explosion radius is very small; it can't be used to force a manoeuvre.
- [ ] Destruction FX should be much better.
- [ ] Beams need a spool-up / charge time that can be seen from afar: that is the dodge cue.
      The charge can be held, so the beam fires when the weapon release is let go, not on the press.
- [ ] A launched projectile like the beam shouldn't lag behind the barrel that fired it: for a
      long beam type it should follow the barrel for a bit while it dissipates.

## 2. Physics

- [ ] Bump up the ν's side thrusters: it's very slow sideways, and an MS should be a highly
      manoeuvrable machine. Allow a 3D vector on the main backpack thrusters (the backpack's own
      vectoring stays 2D, but the thrusters can move in 3D). Currently the only reliable dodge is
      forward or upward.
- [ ] The arm movement for the shield and rifle doesn't go into AMBAC / Newton's third law: no
      thruster fires and no other limb balances it. The MS should have gone into a spin by now
      with these motions.
- [ ] Other MS' beams should definitely be faster than the turret's here, so MS manoeuvrability
      needs to be better: probably have to resort to increasing thruster output.

## 3. HUD

- [ ] SOI symbology on both the panoramic screen and the MFD isn't what it should be.
- [ ] TMS and HMCS cursor UI are bad.
- [ ] Locked target and enemy symbology need improvement.
- [ ] In DGFT / BVR the MS body and weapons should actually be visible through the panoramic
      screen; the shield and funnels stay outlines only.
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

- [ ] Add a lot more joints so both the rifle and the shield are more manoeuvrable; joints
      other than the arm can also help widen the targeting envelope.
- [ ] Shield is bad: it clips through the body. The design where it follows the pilot's look is
      also bad: it should just be posed. Increase the shoulder joint's range, and let the shield
      itself rotate around its attachment point, so it can protect more than the abdomen.
- [ ] Look at the shoulder armour blocking the way (it can definitely be moved).
- [ ] Mid / late UC MS have magnetic coating: joint movement (rifle aiming, shield, etc.) can
      be a lot faster.

## 5. Model

- [ ] Remove the switches and the hatch panel next to the armrest. The switches aren't needed
      and the hatch panel can move elsewhere (ideas TBD). There should only be an armrest, not a
      panel that blocks the view.
