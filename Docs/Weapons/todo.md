# Combat HUD pass: TODO

From the user's reviews of the combat HUD (2026-11-17, two rounds). It replaces the weapons pass
todo; that pass is done (the old list is in git history). How it all works now:
`Docs/Weapons/summary.md` (controls, lock, SOI, zoom), `Docs/PanoramicCockpit/hud.md`
(symbology), `Docs/PhysicsAndSensors/sensors.md` (search tracks, gun circle, steady marks).

**The goal: declutter.** The target must stay visible, because seeing what it does is the fight. Same
style as the reviewed flight HUD, after the Ξ Gundam cockpit in *Hathaway's Flash*: thin, mostly
white-grey, with colour only for what needs attention. **A sim:** everything the pilot sees of
other contacts comes from the sensors, never the engine's truth.

Reference: small target triangle, red velocity tail, gun solution circle (two thin rings, broken):

![target, tail and gun solution circle](images/ref_target_and_gun_circle.png)

Reference: the TMS cursor, three double-railed arms pointing at an empty centre:

![TMS cursor](images/ref_tms_cursor.png)

## 1. Controls

- [x] **TMS switch** (left 5-way hat): forward = zoom window (locks the contact under the cursor
      first if nothing is locked; again = next level), aft = unlock (closes the zoom first),
      right / left = next contact by azimuth, depress = lock the nearest contact. Keys Z, T,
      `]` / `[`, H.
- [x] **Lock**: either left trigger detent (0 / 1), key G: the contact under the cursor. No
      preview button: hovering is the preview. Locking never unlocks.
- [x] **SCS** (right stick, 10 / 11 / 12 / 13 forward / right / aft / left; Tab, numpad 9 / 5 / 7):
      forward = TMS cursor ↔ HMCS, aft / left / right = centre / left / right MFD. The centre MFD
      has the SOI from the start.
- [x] The cursor hides while locked and is back straight ahead on unlock.
- [x] The left hat no longer recentres / switches the view (`StickLook.button` -1; key V does).

## 2. Contact and target symbology

- [x] Kept: the blue broken triangle (all contacts), the inner red corners (hostile).
- [x] Removed: the white pre-lock brackets, the lock brackets, the winged V, the white gun cross
      (the "FPS crosshair"), the HIT / BLOCK cue (debug export, off).
- [x] **Candidate** (under the cursor): the triangle's bars filled solid, no blink.
- [x] **Lock dashes by track quality**: two = good, one = poor / acquiring, one blinking = coasting.
- [x] **From the sensors**: every contact is drawn where its sensor track puts it, smoothed so it
      doesn't hop between looks; a contact the sensors don't track isn't drawn at all.
- [x] **Size shows the doubt**: as big as it could look (angular error, and how much nearer it
      could be for its range error). A new contact starts ~2.5× and shrinks as it settles; the
      size is picked at most once a second (8% deadband, 25% once settled) and eased.
- [x] **Tail**: where the locked target came from (its own estimated velocity, 2 s), a thin
      pink-violet line from the triangle's edge. Tail on the left = moving right.
- [x] **Label**: type and range only (range from the track).

## 3. Gun solution circle (replaces the lead diamond, SHOOT and the envelope)

- [x] Removed: the lead diamond, the swing line, SHOOT / OUT, the time of flight, the envelope.
- [x] **One circle**, two broken rings, the shoot cue: centred where a shot would go relative to
      the target; radius 1.3 × the triangle × √(1 + (expected miss / target radius)²), expected
      miss = the track's prediction error and the dodge from the target's recent jinking
      (agility). Hugging the triangle = a likely hit.
- [x] The locked target's label moves outside the circle.
- [ ] Vulcans: the same circle treatment (TBD); their ring stays for now.

## 4. Cursors and SOI

- [x] **TMS cursor**: three double-railed arms, a faint Y in the middle. Out of SOI: one dim rail,
      holds still. Reaches anywhere (azimuth wraps, elevation ±85°).
- [x] **HMCS cursor**: a 4.5° ring broken left and right, three inward ticks, a centre dot; the
      breaks close over a contact.
- [x] **SOI** (F-16 style): every MFD can take it (red border); the SA page also has a cursor
      (slew it over the map, lock takes the contact under it). Taking the SOI on the panoramic
      screen sweeps a ring out from the cursor. No SOI text.

## 5. Zoom window

- [x] What the head telescope sees, stabilised (GIMBAL when out of the gimbal's reach) in a 14° × 10.5° inset over the target, ×2 doubling to ×128, resolving in from blocks
      at each level; the HUD fades to 35% inside it.
- [x] The level number and a row of square cells, one per level, filled up to the one shown.
- [x] Cost: +0.5 ms a frame open (`Tools/Profiling/zoom_cost.gd`). The frame and cells are drawn
      by the screen shader; on the HUD canvas they cost +3.9 ms.

## Reviewed in game

Flown and passed by the user (2026-11-17): the SCS button numbers (10–13), the lock flow and
cycle order, the track dashes, the contact marks' steadiness, the gun circle against jinking,
the tail length (2 s), zoom at ×32–×128.

- [ ] If the marks ever feel busy: snap sizes to a few classes by range, or freeze a contact's
      size once identified with a fading outer bracket for the range doubt.

## Later / TBD

- [ ] Long-range targets aren't lockable: investigate (`lock_range`, the track at range).
- [ ] Mode, weapon and armed status on the panoramic screen need work.
- [ ] A separate DGFT HUD character (a more visible cue than the mode label).
- [ ] A fixed cockpit-level reference line inside the suit attitude line, for keeping the
      cockpit's horizontal centre in fast rotations (start where the suit line starts; it doesn't
      follow it).
- [ ] Hidden contacts on the SA page as last-known positions.
- [ ] Friend / foe / unknown symbology and identification: in the sensors todo (BVR).
- [ ] Far suits may still be sub-pixel at long range even with MSAA: if so, look at a
      minimum on-screen size or a contact glint for far hostiles.
