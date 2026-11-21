# Audio

## How sound works in space here

Space carries no sound. What the pilot hears is the panoramic cockpit **simulating** outside
sound. For now only the suit's own beam rifle makes a sound; enemy and cockpit sounds come
later (todo.md).

Bus layout (`default_bus_layout.tres`): `External` (simulated outside sound, placed in 3D)
→ Master. The camera is the listener (Godot's default). No Doppler: the cockpit would not
simulate it.

## Shot sounds

`ProjectileSpec.fire_sound` plays on the muzzle as the shot leaves
(`ProjectileManager.muzzle_flash()` → `play_sound()`), riding it like the flash, on External:
full volume within `sound_unit_size` (150 m), falling off past it, silent past
`sound_max_distance` (2 km). `fire_volume_db` sets its level.

| Spec | fire_sound |
|------|-----------|
| `nu_beam_rifle.tres` (RX-93 rifle) | `Entities/Projectiles/Sounds/beam_rifle_fire.wav` (raw cut) |

`play_sound(stream, position, velocity, anchor, volume_db, unit_size, max_distance)` takes one
of `MAX_VOICES` pooled `AudioStreamPlayer3D`s (a free one, else the oldest); it is public for
other one-shot world sounds. `Tools/Weapons/weapons_probe.gd` checks the rifle's sound plays
on its muzzle.

## SFX lab (`Tools/Audio/`)

Every game sound is built by a script from a source file and a recipe, so a sound can be
re-cut, re-cleaned or re-levelled by changing a number. Nothing goes through a hand export.

```
Tools/Audio/
├── sfx_lab.sh / sfx_lab.py   the lab (uv project: pyproject.toml, venv made on first run)
├── sfx.toml                  one recipe per game sound
├── Sources/                  source audio (LFS) + CREDITS.md
└── Synth/                    SuperCollider scripts for generated sounds (_template.scd)
```

Commands (`Tools/Audio/sfx_lab.sh …`):

| Command | Does |
|---------|------|
| `build [name…]` | renders recipes into the project (all by default), prints levels |
| `report <out_dir> [name…]` | raw cut + cleaned wav + spectrogram/waveform PNG of each |
| `sweep <name> <out_dir> key=[a,b] …` | variants of one recipe (JSON arrays), wav + PNG each |
| `check <file…>` | format sanity (catches exports whose header lies) + levels |
| `synth <file.scd> <out.wav> [s]` | renders a SuperCollider script offline (no audio device) |

After `build`, reimport: `godot-double --headless --path . --import`.

### The chain

cut → high/low pass → spectral denoise → downward expander → low-band fade → notch fades → channels →
pedalboard fx → fades → level → 48 kHz 16-bit WAV. Keys and defaults are in `DEFAULTS` at the
top of `sfx_lab.py`:

- `noise`: where the denoiser learns the noise from: `[from, to]` in the source, `"auto"` (the
  quietest 0.25 s, skipping digital silence), or `"none"`. Pick a stretch with *only* the
  noise in it: tones in the reference get carved out of the sound.
- `stationary = false`: the denoiser tracks noise over time instead of using one profile;
  better when the noise swells (the beam's tail).
- `low_fade = [hz, from, to]`: fades out only the band under `hz` between `from` and `to` s,
  keeping an attack's thump while dropping rumble that takes over the tail.
- `notch_fade = [[hz, q, from, to], …]`: notches a whine in only from `from` to `to` s (the
  rifle's ~1.31 kHz whine, which the body masks but the dissipating tail lays bare).
- `tail = {at, xfade, length, decay_db, curve, cutoff_from, cutoff_to, grain}`: replaces the
  recorded tail from `at` with noise in the sound's own colour (median-smoothed, so whines
  drop out), decaying by `decay_db` and darkening from `cutoff_from` to `cutoff_to`, crossfaded
  in over `xfade`. For a tail too noisy or too filtered to keep.
- Spectral denoise can dull a sound with texture (the beam): measure it against no denoise and
  prefer targeted fixes (low_fade, notch_fade) when the noise has a shape.
- `expand_db`: pushes down whatever is quieter than peak − expand_db (hiss in a tail that
  fades well below the body; useless when the noise is as loud as the sound).
- `fx`: any pedalboard plugin by class name, e.g. `fx = [{type = "Reverb", room_size = 0.2}]`.
- `channels = 1` for anything placed in 3D, 2 for cockpit sounds.
- `peak_db` (default −1) or `lufs` sets the level; game balance is then `fire_volume_db` / bus.

### Judging a result

The lab can't listen. Spectrogram PNGs saturate on the log colour scale and are poor for
"how much quieter"; measure band energy over time instead (STFT, sum per band) and compare raw
vs cleaned. The ear decides the rest: `report` writes the wavs to compare side by side.

### Sources

`Sources/cockpit_beam_sfx.mp3`: cockpit pings, a threat warning and two beam shots (13.8 s).
Its gaps are digital silence and a broadband "air" noise runs under every sound: rumble below
~400 Hz and a beating band at 0.5–1.2 kHz. The pings are thin tone lines (≈1.7–4.4 kHz)
above that band, so a steep high pass takes most of the air out, but they stay hissy;
resynthesising them (Synth/) may beat cleaning.

## Not done yet

Everything still to make, and the open warning decision: [todo.md](todo.md).
