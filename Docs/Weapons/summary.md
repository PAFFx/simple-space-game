# Weapons and Fire Control

Ranged weapons on the RX-93: beam rifle (PULSE and LINEAR beams), twin head vulcans, four
shield missiles, and the shield guard. Nothing is hit-scan. The suit never turns itself to shoot: each weapon has an
envelope fixed to the body, and bringing the target into it is flying.

```
PilotCommand (weapon fields)          keyboard / twin sticks / scripted
      │
FireControl (suit)                    master arm, master mode, lock, selection, block
  ├── MsWeapon "Weapon"   (BeamRifle equipment)    beam_rifle      PULSE; arm aims, torso helps
  ├── MsWeapon "Linear"   (BeamRifle equipment)    beam_linear     LINEAR; draws on Weapon's E-pack
  ├── MsWeapon "Guard"    (Shield equipment)       shield_guard    follows the pilot's look
  ├── MsWeapon "Missiles" (Shield equipment)       shield_missile  unguided, proximity burst
  └── MsWeapon "Vulcan"   (rides the head bone)    vulcan          head tracks the target
      │  aim (az / el in the body frame)      │ shots
WeaponAimModifier (skeleton)           ProjectileManager (scene) ── apply_hit() ──► targets
```

| File | Role |
|---|---|
| `Entities/Vehicles/Components/FireControl/fire_control.gd` | modes, lock, selection, block, hit bookkeeping |
| `.../FireControl/ms_weapon.gd` | one weapon: readying, envelope, lead solution, slew, ammo, firing |
| `.../FireControl/weapon_aim_modifier.gd` | turns the aim bone so the muzzle points along the aim |
| `Entities/Projectiles/projectile_spec.gd` + `Specs/*.tres` | how a shot flies, hurts and looks |
| `Entities/Projectiles/projectile_manager.gd` | flies and draws every shot, flashes, sparks |
| `Entities/Projectiles/Shader/beam.gdshader`, `flash.gdshader` | bolt + wake strip, glow sprite |
| `.../PanoramicHud/Widgets/weapons_widget.gd` | HUD symbology |
| `.../CockpitDisplays/target_page.gd`, `weapon_ring.gd` | right MFD: target, stores, weapon ring pop-up |
| `.../Cockpits/Components/BeamGlow/cockpit_beam_glow.gd` | beams light the cockpit |
| `Entities/Environment/Space/TargetDrone/target_drone.gd` | practice targets (static, drift, jink, turret) |
| `Stages/Components/RangeControl/range_control.gd` | F4 panel: spawn / clear targets, rearm |

## Controls

Both sticks number their buttons alike. Exports on `TwinStickPilotInput`; keys in `PilotInputActions`.

| Function | Stick | Key |
|---|---|---|
| Vulcan open / fire | right 0 (first detent) / 1 (second) | X |
| Fire selected weapon | right 2 (weapon release) | left mouse (captured) |
| Weapon hat fwd / right / aft / left / depress | right 15 / 16 / 17 / 18 / 19 | 1 2 3 4 5 |
| Master arm on / off | right 24 / 25 | M (toggle) |
| Sensor of interest | right 10 (SCS forward) | Tab |
| HUD cursor slew | right axes 3, 4 | numpad 4 6 8 2 |
| Lock preview / commit | left 0 / 1 | T / G |
| Shield block (hold) | left 2 | B |
| NAV / DGFT / BVR | left 14 / 10 / 12 | N / J / K |

- **Master arm** SAFE: triggers dead, symbology live (the lead cue says SAFE instead of SHOOT).
- **Modes.** NAV stows everything. DGFT always opens on the beam rifle. BVR is a label only for
  now; selecting a weapon in NAV drops to DGFT, in BVR it doesn't.
- **Weapon hat** ("press again"): a press selects the direction's first weapon at once; pressing
  the same direction while it is selected swaps to the second. Layout in `FireControl.hat_layout`:
  forward pulse → linear, right funnels, aft bazooka (back → hand), left shield missiles,
  depress saber. Swapping pulse ↔ linear keeps the arm up (`MsWeapon.take_over`).
- **Spool.** A beam (`ProjectileSpec.spool_time` > 0) fires once per pull: hold the trigger
  while the barrel glows (pulse 0.3 s, linear 0.9 s), the shot leaves when it is spooled, and
  letting go early drops it. Press again for the next shot. The glow
  (`ProjectileManager.set_charge`) is the dodge cue; the turret drone spools too (0.5 s).
- **E-pack.** 32 rounds shared through `ammo_from`: pulse uses 1, linear 3 (`ammo_cost`).
  The cooldown is shared too (pulse 2 s, linear 5 s). Unfitted
  entries show dim on the ring and flash red when pressed.
- **Lock.** Preview marks the contact nearest the designation (pulsing brackets); commit locks it,
  or unlocks when the candidate is already locked or nothing is designated. The designation is
  the HUD cursor (default sensor of interest) or the pilot's line of sight (HMCS).
- **Shield block** holds the shield toward where the pilot looks, within its envelope. It stops
  shots arriving within `shield_cover_deg` of its facing (HUD: BLOCK, else HIT). Missiles can't
  launch while blocking. The suit has no damage model yet.

## Aiming

`MsWeapon.aim` is azimuth / elevation in the body frame. With a lock it slews (`slew_rate_deg`,
speeding up and braking at `slew_accel_deg` 600°/s², so the limb's reaction on the suit stays
finite: see LimbReaction in `Docs/FlightControl/summary.md`) toward the lead direction, clamped to `az_limits` / `el_limits`; without one it sits on
`boresight`. Shots leave along `aim`, so the barrel's lag is real: the HUD shows the gun cross
(where the barrel is) and the lead diamond (where it must be); SHOOT when they meet.

The lead solves `|rel_pos + rel_vel·t| = distance(t)` (`SpatialMath.intercept_time`), iterated for
missiles, whose speed grows during the burn. Shots inherit the shooter's velocity.

`WeaponAimModifier` runs after the pose animation and AMBAC: it twists `torso_bone` by
`torso_share` of the azimuth (rifle: 20%, ≤ 10°), then rotates each weapon's `aim_bone` by the
arc from the muzzle's current direction to the aim. The ready pose supplies the base posture.

| Weapon | Azimuth | Elevation | Slew | Notes |
|---|---|---|---|---|
| Beam rifle | −35 … +75 | −50 … +55 | 80°/s | right arm; narrow across the chest |
| Vulcans | ±55 | −25 … +40 | 200°/s | head; ready whenever a weapons mode is on |
| Shield missiles | −60 … +25 | −40 … +45 | 70°/s | left arm raised, shield tip forward |
| Shield guard | −110 … +35 | −50 … +60 | 140°/s | follows the look |

These are first guesses to tune in the equipment scenes (`rx93_beam_rifle.tscn`,
`rx93_shield.tscn`) and `Tools/Godot/build_rx93_scene.gd` (vulcans, `shield_fire` pose).

## Projectiles

`ProjectileManager.of(node)` makes one manager per scene on first use. Each shot is plain data,
stepped per physics tick with a swept ray (no tunnelling), drawn every frame as a camera-facing
strip from its head back along its path. A hit calls `apply_hit(damage, position, direction,
source)` on the collider or its nearest ancestor that has it. Missiles burst within
`fuse_radius` of anything in the `damageable` group and hurt everything inside `blast_radius`.

| Spec | Speed | Life | Range | Damage |
|---|---|---|---|---|
| `nu_beam_rifle` (pulse) | 3000 m/s | 2.5 s | 7.5 km | 1000 |
| `nu_beam_linear` | 3200 m/s, emits 1.2 s | 1.2 s | 3.8 km | 3000 once per target |
| `vulcan_60mm` | 1100 m/s | 1.6 s | 1.8 km | 14 (2 × 640 rpm, 600 rounds) |
| `shield_missile` | 120 m/s + 450 m/s² for 1.6 s | 6 s | ~3.9 km | 450, blast 90 m |
| `drone_shot` | 900 m/s | 5 s | 4.5 km | 100 |

A 4–7 G target moves 5–9 m in 0.5 s, so a shot is roughly unavoidable inside `speed × 0.5 s`
and dodgeable beyond: the tuning rule for `speed`.

**Beam look** (`beam.gdshader`): a white-hot spear `bolt_length` long at the head, then a wake
that spreads, breaks up (noise threshold rising with age) and fades over `trail_time`: the beam
dissipates after the bolt has passed. The strip is clamped between `min_angle` and `max_angle`
on screen, so a far beam stays a visible line and a wake passing the camera isn't a wall;
`flash.gdshader` does the same and fades out right at the camera, so a hit on your own suit is a
flash, not a white screen. Colour comes from the spec (ν Gundam: red).

**Pulse** (`beam.gdshader`): a short spindle-shaped burst whose outline boils (noise over
length and time), white core in a coloured halo, a few thin streaks dying within
`trail_time` behind it. No long wake.

**Linear beam** (`linear_beam.gdshader`): while it emits (`emit_time`, 1.2 s) it is a straight
beam from the barrel along the barrel, swinging with it like a laser; its front still travels
at `speed`, so it reaches only `speed × age`. Each tick one ray from the muzzle along it: what
lies in it is hit (once per target), the beam ends there and splashes. The aim leads by what
is left for the front to cover (`_lead_with_head_start`). Let go, it stays where it was and
breaks up over `trail_time` (0.45 s).

**Charge** (`set_charge`, `flash.gdshader` with `flash_charge`): a ragged, boiling knot with
arcs crackling off it and a white core growing with the spool. It, the linear beam's barrel
end and muzzle flashes ride the muzzle's drawn (physics-interpolated) position
(`ProjectileManager.drawn_position`).

**Explosions** are spheres of light (`ProjectileManager.explode` / `ball`, `flash.gdshader`
with `flash_ball`): a white-hot ball of the given radius (a missile's: its blast radius),
smaller balls bubbling out one after another, cooling to the colour and fading.

**Cockpit glow.** `ProjectileManager.sample_glow(position)` sums nearby shots and flashes by
`spec.glow` and distance; `CockpitBeamGlow` drives one light (cockpit + pilot layers only) in
that colour, from that direction.

## Testing

- `F4` in the test range: spawn static / drifting / jinking / turret targets at a chosen range,
  clear them, rearm.
- `godot-double --headless --path . -s Tools/Weapons/weapons_probe.gd`: scripted check of modes,
  hat, lock, SAFE, lead on a crossing target, vulcans, missiles, block.
- `Tools/Weapons/weapons_snapshot.gd -- <out_dir> [shots]`: renders HUD, beam, poses, impact,
  ring, vulcan, missile, block and turret views to PNGs (run it windowed).

## Not done yet

Damage to the player's suit and part destruction, holes in structures, recoil and missile mass,
E-pack reloads, the pod-opening animation, funnels, bazooka, sabers, BVR, lock line-of-sight.
