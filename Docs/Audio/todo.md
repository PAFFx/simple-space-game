# Audio TODO

What still needs a sound, and the open decisions. How sounds are made and wired:
[summary.md](summary.md). Bus: **E** = External (simulated outside sound, 3D), **C** = Cockpit.
Source: **syn** = synthesize (SuperCollider, `Tools/Audio/Synth/`), **rec** = recorded / sampled
material (layered, cleaned in the lab), **either**.

## Order

Own suit's sounds first; enemy and cockpit-alert sounds after.

## Parked (tried, then taken out of the game 2026-11-20)

Recipes and scripts stay in `Tools/Audio/sfx.toml` / `Synth/` (no `out`, so `build` skips them).

- **Enemy beam fire** (`drone_beam_fire`, raw cut): was the drones' `fire_sound` with a short
  range (40 m unit size, silent past 1.2 km).
- **Beam pass-by**: a `pass_sound` played where someone else's shot goes by the listener.
  Candidates: cuts of beam 2's zip, a generated sizzle and zip (a Doppler buzz sounded like a
  car). When it comes back it must be gated on the cameras seeing the beam, not read from the
  shot's data.
- **Cockpit warnings** (raw cuts of the low / medium ping and the threat). Decided meanings:
  low ping = new contact, medium ping = locked on, threat = incoming fire. They must come
  from what the suit's sensors sense: new contact from sensor tracks; incoming fire from the
  cameras seeing a muzzle charge (line of sight, brightness at range); locked on needs an
  emitter to sense (radar, not implemented): a camera lock is passive.

## Warnings and cockpit cues (C)

| Sound | When | Source |
|-------|------|--------|
| Own lock acquired / lock lost | FireControl lock changes | syn |
| Missile incoming | A missile homing on you (fast, urgent) | syn |
| Collision / proximity | Closing on a body or structure too fast | syn |
| Propellant low | Propellant under a threshold | syn |
| Hull damage / critical | Hit taken; part destroyed | syn + rec thump |
| Overheat | Beam rifle / thrusters too hot (once heat exists) | syn |
| Rifle empty / E-pack | Out of rounds; reload | syn |
| Master caution chime | Any new caution | syn |
| Computer voice callouts | Optional: "Lock", "Missile", "Propellant low" | rec |

## Weapons

| Sound | Bus | Source | Notes |
|-------|-----|--------|-------|
| Beam rifle fire | E | rec | done (`beam_rifle_fire`); re-check by ear |
| Enemy beam fire | E | rec | parked (see above) |
| Beam rifle charge hum | E/C | syn | while `spool` rises; pitch with spool fraction |
| Vulcan | E | either | looping burst while firing |
| Missile launch + motor | E | either | launch thump, motor loop riding the missile |
| Beam hit: armor / shield / rock | E | rec | `impact()`; the shield block distinct |
| Beam pass-by | E | ? | parked (see above) |
| Beam saber | E | either | ignite, hum loop, swing, clash (when sabers exist) |

## Outside (simulated, E)

| Sound | Source | Notes |
|-------|--------|-------|
| Explosions (drone, suit, missile burst) | rec | layered; size-scaled with `explode()` |
| Debris / rock strikes on the hull | rec | also felt through the frame (C) |
| Enemy suit passing by | syn | thruster roar fly-by |
| Station machinery | either | low hum near the station |

## Own suit (C, through the frame)

| Sound | Source | Notes |
|-------|--------|-------|
| Main thruster boost | syn | loop + start / stop, level from thrust |
| RCS / attitude puffs | syn | short bursts per thruster firing |
| Joint servos / AMBAC limbs | syn | whir with limb speed |
| Hatch open / close | either | `CockpitHatch` sequence |
| Shield raise / guard | rec | mechanical clunk |

## Cockpit interior (C)

| Sound | Source | Notes |
|-------|--------|-------|
| Switch clicks, button presses | rec | `CockpitSwitch` / clickable controls |
| MFD page change, mode change chime | syn | NAV / DGFT, SOI changes |
| Panoramic screen boot-up | syn | when the screen comes on with the hatch |
| Interior hum / life support | syn | quiet loop, the floor everything sits on |
| Linear seat motion | syn | seat moving on the gimbal under G |

## System work

- Sensor-gated External sounds: a source the sensors can't see makes no sound.
- Mix pass: bus levels, a limiter on Master, ducking External under urgent warnings.
- Credits: origin and licence of `Sources/cockpit_beam_sfx.mp3` (`Sources/CREDITS.md`).
