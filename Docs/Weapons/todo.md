# Combat HUD pass: TODO

The user's first review of the combat HUD (2026-11-17). It replaces the weapons pass todo; that pass is
done (its last open item is carried over at the bottom, and the old list is in git history).

**The goal: declutter.** The target must stay visible, because seeing what it does is the fight. Same
style as the reviewed flight HUD, after the Ξ Gundam cockpit in *Hathaway's Flash*: thin, mostly
white-grey, with colour only for what needs attention.

Reference: small target triangle, red velocity tail, gun solution circle (two thin rings, broken):

![target, tail and gun solution circle](images/ref_target_and_gun_circle.png)

Reference: the TMS cursor, three double-railed arms pointing at an empty centre:

![TMS cursor](images/ref_tms_cursor.png)

## 1. Lock flow and controls

- [x] **Hovering previews.** Whatever is under the active cursor (TMS or HMCS) is the lock
      candidate with no button held: its blue bars flash. No first-detent preview.
- [x] **Lock**: left trigger first *or* second detent (buttons 0 / 1), left hat depress (19), key G.
      Locking again with a target locked does **not** unlock it (with no cursor while locked,
      it does nothing).
- [x] **Unlock**: left hat aft (17), key T. If the zoom window is open, the first press only
      closes it and the second unlocks.
- [x] **Cycle targets**: left hat left / right (18 / 16), keys `[` / `]`. The lock steps to the next
      contact by azimuth from the current one (right = the nearest one further right, wrapping
      round).
- [x] **Cursor hides while locked.** On unlock it comes back at its default place (straight ahead).
- [x] **Unbind the left hat from the views.** `StickLook.button` (19: tap = recentre, hold = switch
      view) goes to -1. Key V still switches view.

## 2. Contact and target symbology

- [x] **Keep** the blue broken triangle (all contacts) and the inner red triangle corners (hostile).
- [x] **Remove** the white pre-lock brackets, the solid lock brackets, and the winged V on the
      selected contact.
- [x] **Track quality marks**: the outer red corner dashes appear only on the locked target.
      | Track | Mark |
      |---|---|
      | coasting (no measurement for a moment) | one dash, blinking |
      | acquiring / poor (tentative, or firm with a large position error) | one dash, solid |
      | good (firm, position error small next to the target) | two dashes, solid |
      `LOST` drops the lock, as now.
- [x] **Drawn from the sensor, not the truth.** The locked target's triangle sits at the track's
      estimate (`FireControl.get_target_position`), so it can be a bit off the real suit. It must not
      jitter, so filter it like the weapon aim (a 1 euro filter) and extrapolate it to the frame time.
- [x] **The size shows the uncertainty.** Triangle half-size = max(apparent size × fit, the track's
      angular position error × k). A new, far track starts big and shrinks as it firms up, with no
      smoothing needed.
- [x] **Other contacts from a cheap search track.** Unlocked contacts are drawn where a search
      look puts them (`FireControl.get_contact_position`): a slowly wandering angle (body camera
      noise, 1 mrad) and range (known-size ranging, 10%), τ 2.5 s. The range label reads ~10%
      off until the contact is locked (laser / stereo then).
- [x] **Velocity tail** on the locked target: a thin pink-violet line (`suit_accent_color`) from the
      triangle's edge (never across it) along the target's motion across the view (velocity
      relative to us, about 1 s ahead), its length clamped.
- [x] **Label**: type and range only. Vc, aspect and the rest stay on the MFD target page.
- [x] **Hidden contacts vanish**: a line-of-sight ray from the sensor head per contact (at the label
      rate, 10 Hz). A contact behind an obstacle isn't drawn and can't be designated or locked.
      Later: show them on the MFD SA page as last-known positions.

## 3. Gun solution circle (replaces the lead diamond, SHOOT and the envelope)

- [x] **Remove** the lead diamond, the swing line, the SHOOT / OUT text, the time-of-flight number and
      the selected weapon's envelope outline.
- [x] **One circle around the target**: two thin concentric rings with gaps, as in the reference,
      bigger than the target's triangle and never smaller (so it never hides the target).
  - *Centre*: where the shot would go, relative to the target: the target (sensor estimate)
    offset by the angle between where the barrel points and the lead. Barrel on the lead =
    centred on the target. Lead outside the envelope = the barrel stops at its limit, so
    the circle slides off the target.
  - *Radius*: how sure the shot is: the predicted impact error at the time of flight
    (`FireControl.get_target_covariance_ahead`, as an angle), plus the barrel's lag.
  - **The circle is the shoot cue.** Circle on the target = shootable; the smaller it is, the
    better the shot. The pilot chooses how sure they want to be. No SHOOT text.
  - Dim while the weapon isn't ready (spooling, cooldown); small MASKED / SAFE text on the
    ring only when the trigger is dead.
- [x] Gun cross: only without a lock (where an unaimed shot goes). With a lock, the circle replaces it.
- [ ] Vulcans: the same circle treatment (TBD); their ring stays for now.

## 4. Cursors

- [x] **TMS cursor**: three double-railed arms (up-left, up-right, down) pointing at an empty
      centre with a small faint Y in it (see the reference). Steel blue, a fainter fill between
      the rails.
- [x] **HMCS cursor**: a large ring, about 4.5° radius (now 1.5°), made of two arcs with
      gaps at left and right, three short inward ticks at 120° matching the TMS arms, and a dot in
      the middle. The gaps close while a contact is under it.
- [x] **TMS reach**: the cursor goes anywhere on the sphere. Azimuth wraps through ±180°,
      elevation ±85° (now ±70° / ±45°).
- [x] Both hide while locked and reset to centre on unlock (see 1).

## 5. Sensor of interest (F-16 / F-18 style)

- [x] The SOI is a display: the panoramic screen (TMS cursor), the HMCS, or an MFD page that has a
      cursor. Pages without one can't take it. The SOI switch (right SCS forward, Tab) cycles
      through the ones that can.
- [x] **MFD**: the SOI page gets a border in the HUD's red / pink-violet accent.
- [x] **Panoramic screen**: no text. The cursor itself shows it: in SOI it's bright with
      both rails and slews; out of SOI it drops to one dim rail and holds still. On taking SOI, an
      accent-coloured ring sweeps out from the cursor once.
- [x] The SA page has a cursor (so it can be the SOI): slew it over the map, lock takes the
      contact under it.
- [x] Remove the `SOI HUD` / `SOI HMCS` text.

## 6. Zoom window (left hat forward, 15; key Z)

Built: levels ×2 … ×128, doubling (7 levels); the HUD is faded to 35% inside the window
so the magnified target reads; measured 0.2–0.65 ms GPU while open.

- [x] With a lock, it opens a rectangular inset on the panoramic screen over the target, showing it
      magnified (×2 / ×4 / ×8). Pressing again cycles the level. Unlock (aft) closes it first.
- [x] It is what the main camera's telescope sees: it needs the head gimbal to reach the target
      (`SensorSuite` head limits). Outside them it doesn't open, or closes, with a short cue.
- [x] Opening and changing level resolve in from pixel blocks, like the NAV / DGFT overlay
      (`overlay_reveal`).
- [x] **Performance**: a second camera on the sensor head, a narrow frustum (few objects to
      draw), into a small SubViewport (512²), possibly at 30 Hz, sampled by the panoramic shader
      as an inset. Measure with `Docs/Performance/frame_budget.md` before polishing.

## 7. Cleanup

- [x] Remove the HIT / BLOCK cue from the HUD (debug only: an export, off by default).
- [x] Update `Docs/Weapons/summary.md` and `Docs/PanoramicCockpit/hud.md` to match.

## Needs review in game

Built while the user was asleep (2026-11-17), checked with the probe and rendered snapshots
(`weapons_snapshot.gd hud,hudmove,soi,zoom`). Fly each and tick it off, or note what to change.

- [ ] Lock flow on the sticks: either trigger detent / hat depress locks, aft unlocks, left /
      right cycles, forward zooms. Is the cycle order by azimuth what you want?
- [ ] Candidate flash rate (`ContactsWidget.flash_hz` 2.5, `flash_dim` 0.85) and coast blink.
- [ ] Track dashes: two = firm and position error under the target's radius, one = tentative
      or worse, blinking = coasting (`FireControl.get_track_mark`).
- [ ] Shown-target smoothing (`FireControl.shown_cutoff_hz` 1.5, `shown_beta` 4): no jitter, no
      visible lag on a crossing target?
- [ ] Gun circle: rings, gaps, size; it is mostly at its least size (the narrow camera tracks
      well), growing on far / poor tracks and long times of flight.
- [ ] Tail: 2 s of relative motion, from the circle's edge.
- [ ] TMS / HMCS cursor look; HMCS ring 4.5°.
- [ ] SOI: the red MFD border, the dim TMS out of SOI, the take-over sweep.
- [ ] Zoom window: size (14° × 10.5°), levels, the HUD fade inside, the block resolve.

## Later / TBD

- [ ] Long-range targets aren't lockable: investigate (`lock_range`, the track at range).
- [ ] Mode, weapon and armed status on the panoramic screen need work.
- [ ] A separate DGFT HUD character (a more visible cue than the mode label).
- [ ] A fixed cockpit-level reference line inside the suit attitude line, for keeping the
      cockpit's horizontal centre in fast rotations (start where the suit line starts; it doesn't
      follow it).
- [ ] Far suits may still be sub-pixel at long range even with MSAA: if so, look at a
      minimum on-screen size or a contact glint for far hostiles.
