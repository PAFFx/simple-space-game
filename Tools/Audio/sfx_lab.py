"""SFX lab: builds the game's sound effects from source audio, the way sfx.toml says.

    sfx_lab.sh build [name...]                 render recipes into the project (all by default)
    sfx_lab.sh report <out_dir> [name...]      raw cut + cleaned wav + spectrogram per recipe
    sfx_lab.sh sweep <name> <out_dir> key=[a,b] [key=...]   variants of one recipe to compare
                                               (JSON arrays, e.g. 'low_fade=[[400,0.3,0.8]]')
    sfx_lab.sh check <file...>                 format sanity + levels of any audio file
    sfx_lab.sh synth <file.scd> <out.wav> [seconds]   render a SuperCollider NRT script

Chain per recipe: cut -> high/low pass -> spectral denoise (noise profile from a reference
range) -> downward expander -> low-band fade -> notch fades -> channels -> pedalboard fx ->
fades -> level -> 16-bit WAV.
"""

from __future__ import annotations

import itertools
import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path

import numpy as np
import soundfile as sf

LAB = Path(__file__).resolve().parent
PROJECT = LAB.parent.parent
CACHE = LAB / ".cache"
RATE = 48000

DEFAULTS = {
    "start": 0.0,
    "end": None,           # s in the source; None = to its end
    "channels": 1,         # 1 for anything placed in 3D, 2 for cockpit / UI
    "highpass": 40.0,      # Hz, 0 = off
    "lowpass": 0.0,        # Hz, 0 = off
    "noise": "auto",       # [from, to] s in the source, "auto" (quietest 0.25 s), or "none"
    "denoise": 0.85,       # how much of the noise profile to take out, 0..1
    "denoise_smooth_ms": 40.0,   # time smoothing of the noise mask (less "musical" noise)
    "stationary": True,
    "expand_db": 0.0,      # downward expander threshold below the peak, dB (0 = off)
    "expand_ratio": 3.0,
    "low_fade": [],        # [hz, from, to]: the band under hz fades out from..to s into the cut
                           # (keeps an attack's thump, drops rumble that swells in the tail)
    "notch_fade": [],      # [[hz, q, from, to], ...]: a notch on hz that blends in from..to s
                           # (a whine the body masks but the tail lays bare); from = to = 0: always
    "tail": {},            # replace the tail with noise in the sound's own colour (tail_resynth):
                           # {at, xfade, length, decay_db, cutoff_from, cutoff_to, grain, ref, seed}
    "fx": [],              # pedalboard plugins: [{type = "Reverb", room_size = 0.2}, ...]
    "fade_in_ms": 3.0,
    "fade_out_ms": 30.0,
    "peak_db": -1.0,       # level to this peak, unless lufs is set
    "lufs": None,
    "out": None,           # res:// path of the game file
}


def load_recipes() -> dict[str, dict]:
    with open(LAB / "sfx.toml", "rb") as f:
        raw = tomllib.load(f)
    return {name: {**DEFAULTS, **r} for name, r in raw.items()}


# ---------------------------------------------------------------- sources

def decode(path: Path) -> np.ndarray:
    """Any format ffmpeg reads -> float32 (frames, channels) at RATE."""
    info = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=channels", "-of", "json", str(path)],
        capture_output=True, text=True, check=True)
    ch = json.loads(info.stdout)["streams"][0]["channels"]
    pcm = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(RATE), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(pcm, np.float32).reshape(-1, ch).copy()


def source_audio(src: str) -> np.ndarray:
    path = LAB / src
    if path.suffix == ".scd":
        rendered = CACHE / (path.stem + ".wav")
        if not rendered.exists() or rendered.stat().st_mtime < path.stat().st_mtime:
            synth(path, rendered)
        path = rendered
    return decode(path)


def synth(scd: Path, out: Path, seconds: float = 3.0) -> None:
    """SuperCollider NRT render: the script gets [out_path, seconds] in thisProcess.argv."""
    out.parent.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen"}
    subprocess.run(["sclang", str(scd), str(out), str(seconds)], check=True, env=env,
                   timeout=120, stdout=subprocess.DEVNULL)
    if not out.exists():
        sys.exit(f"{scd.name} rendered nothing to {out}")


def quietest(x: np.ndarray, length: float = 0.25) -> tuple[float, float]:
    """Start/end (s) of the quietest window: room tone between the sounds. Windows with
    digital silence in them (gaps an editor zeroed) don't count."""
    n = int(length * RATE)
    mono = x.mean(1)
    if len(mono) <= n:
        return 0.0, len(mono) / RATE
    hop = n // 4
    starts = range(0, len(mono) - n, hop)
    rms = np.array([np.sqrt(np.mean(mono[i:i + n] ** 2)) for i in starts])
    silent = np.array([(np.abs(mono[i:i + n]) < 1e-6).mean() > 0.01 for i in starts])
    rms[silent] = np.inf
    if np.isinf(rms).all():
        return 0.0, 0.0
    i = int(np.argmin(rms)) * hop
    return i / RATE, (i + n) / RATE


# ---------------------------------------------------------------- processing

def butter(x: np.ndarray, hz: float, kind: str) -> np.ndarray:
    from scipy.signal import butter as design, sosfiltfilt
    sos = design(4, hz, btype=kind, fs=RATE, output="sos")
    return sosfiltfilt(sos, x, axis=0).astype(np.float32)


def filters(x: np.ndarray, r: dict) -> np.ndarray:
    if r["highpass"]:
        x = butter(x, r["highpass"], "highpass")
    if r["lowpass"]:
        x = butter(x, r["lowpass"], "lowpass")
    return x


def denoise(x: np.ndarray, noise: np.ndarray, r: dict) -> np.ndarray:
    import noisereduce as nr
    if r["denoise"] <= 0.0 or len(noise) < 2048:
        return x
    y = nr.reduce_noise(y=x.T, sr=RATE, y_noise=noise.T, stationary=r["stationary"],
                        prop_decrease=r["denoise"], time_mask_smooth_ms=r["denoise_smooth_ms"],
                        n_fft=2048)
    return np.asarray(y, np.float32).reshape(x.shape[1], -1).T


def expand(x: np.ndarray, r: dict) -> np.ndarray:
    """Downward expander: quieter than peak - expand_db sinks further, by expand_ratio.
    Takes the leftover hiss out of a fading tail without touching the body."""
    if not r["expand_db"]:
        return x
    env = np.abs(x).max(1)
    att, rel = np.exp(-1 / (0.002 * RATE)), np.exp(-1 / (0.08 * RATE))
    follow = np.empty_like(env)
    level = 0.0
    for i, v in enumerate(env):
        level = att * level + (1 - att) * v if v > level else rel * level + (1 - rel) * v
        follow[i] = level
    db = 20 * np.log10(follow + 1e-9)
    threshold = db.max() - r["expand_db"]
    under = np.minimum(db - threshold, 0.0)
    gain = 10 ** (under * (r["expand_ratio"] - 1) / 20)
    return (x * gain[:, None]).astype(np.float32)


def low_fade(x: np.ndarray, r: dict) -> np.ndarray:
    if not r["low_fade"]:
        return x
    hz, a, b = r["low_fade"]
    return (x - butter(x, hz, "lowpass") * ramp(len(x), a, b)).astype(np.float32)


def ramp(n: int, a: float, b: float) -> np.ndarray:
    """0 before a, 1 after b (s), linear between."""
    t = np.arange(n) / RATE
    return np.clip((t - a) / max(b - a, 1e-3), 0.0, 1.0).astype(np.float32)[:, None]


def notch_fade(x: np.ndarray, r: dict) -> np.ndarray:
    from scipy.signal import iirnotch, filtfilt
    for hz, q, a, b in r["notch_fade"]:
        bb, aa = iirnotch(hz, q, fs=RATE)
        notched = filtfilt(bb, aa, x, axis=0).astype(np.float32)
        w = ramp(len(x), a, b)
        x = x * (1.0 - w) + notched * w
    return x


TAIL_DEFAULTS = {
    "at": 0.6,            # s into the cut where the made tail starts to come in
    "xfade": 0.15,        # s of equal-power crossfade from the recording into it
    "length": 0.8,        # s of made tail after `at`
    "decay_db": 60.0,     # how far it falls over `length`
    "curve": 0.8,         # decay shape: < 1 falls fast then lingers, > 1 holds then drops
    "cutoff_from": 16000.0,   # Hz, the made tail's top end as it starts...
    "cutoff_to": 1500.0,      # ...and as it ends: it darkens as it dissipates
    "grain": 0.35,        # random roughness of its level, frame to frame (crackle)
    "ref": 0.15,          # s before `at` whose colour it copies
    "seed": 1,
}


def tail_resynth(x: np.ndarray, r: dict) -> np.ndarray:
    """Swaps the recorded tail for noise shaped like the sound just before it. The colour is
    median-smoothed across frequency, so whines and tones in the recording drop out."""
    if not r["tail"]:
        return x
    from scipy.ndimage import median_filter, uniform_filter1d
    from scipy.signal import istft, stft
    p = {**TAIL_DEFAULTS, **r["tail"]}
    rng = np.random.default_rng(p["seed"])
    n_fft, hop = 2048, 256
    at = int(p["at"] * RATE)
    n_tail = int(p["length"] * RATE)
    ref = x[max(at - int(p["ref"] * RATE), 0):at]
    f = np.fft.rfftfreq(n_fft, 1 / RATE)
    frames = n_tail // hop + 1
    u = np.arange(frames) / max(frames - 1, 1)
    level = 10 ** (-p["decay_db"] * u ** p["curve"] / 20)
    grain = 1.0 + p["grain"] * uniform_filter1d(rng.standard_normal(frames), 3) * np.sqrt(3)
    level *= np.clip(grain, 0.0, None)
    cutoff = p["cutoff_from"] * (p["cutoff_to"] / p["cutoff_from"]) ** u
    rolloff = 1.0 / np.sqrt(1.0 + (f[:, None] / cutoff[None, :]) ** 4)
    out = np.zeros((at + n_tail, x.shape[1]), np.float32)
    n_x = int(p["xfade"] * RATE)
    fade = np.sin(np.linspace(0, np.pi / 2, n_x, dtype=np.float32))
    for c in range(x.shape[1]):
        _, _, Z = stft(ref[:, c], RATE, nperseg=n_fft, noverlap=n_fft - hop)
        colour = np.sqrt((np.abs(Z) ** 2).mean(1))
        colour = uniform_filter1d(median_filter(colour, size=25), 5)
        mag = colour[:, None] * rolloff * level[None, :]
        phase = np.exp(2j * np.pi * rng.random(mag.shape))
        _, made = istft(mag * phase, RATE, nperseg=n_fft, noverlap=n_fft - hop)
        made = made[:n_tail].astype(np.float32)
        # Match the recording's level where they meet.
        k = min(int(0.05 * RATE), len(ref), len(made))
        rms_ref = np.sqrt((ref[-k:, c] ** 2).mean())
        rms_made = np.sqrt((made[:k] ** 2).mean()) + 1e-12
        made *= rms_ref / rms_made
        out[:at, c] = x[:at, c]
        out[at:at + len(made), c] = made
        # Equal power: the recording runs on under the made tail for `xfade`.
        m = min(n_x, len(x) - at, len(made))
        out[at:at + m, c] = x[at:at + m, c] * fade[::-1][:m] + made[:m] * fade[:m]
    return out


def channels(x: np.ndarray, n: int) -> np.ndarray:
    if x.shape[1] == n:
        return x
    mono = x.mean(1, keepdims=True)
    return mono if n == 1 else np.repeat(mono, n, axis=1)


def fx(x: np.ndarray, r: dict) -> np.ndarray:
    if not r["fx"]:
        return x
    import pedalboard
    plugins = [getattr(pedalboard, p["type"])(**{k: v for k, v in p.items() if k != "type"})
               for p in r["fx"]]
    return pedalboard.Pedalboard(plugins)(x.T, RATE).T.astype(np.float32)


def fades(x: np.ndarray, r: dict) -> np.ndarray:
    x = x.copy()
    n_in = min(int(r["fade_in_ms"] * RATE / 1000), len(x))
    n_out = min(int(r["fade_out_ms"] * RATE / 1000), len(x))
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in, dtype=np.float32)[:, None]
    if n_out:
        x[-n_out:] *= (np.cos(np.linspace(0, np.pi / 2, n_out)) ** 2).astype(np.float32)[:, None]
    return x


def level(x: np.ndarray, r: dict) -> np.ndarray:
    if r["lufs"] is not None:
        gain_db = r["lufs"] - loudness(x)
    else:
        gain_db = r["peak_db"] - peak_db(x)
    x = x * 10 ** (gain_db / 20)
    over = peak_db(x) - (-0.3)
    return (x * 10 ** (-over / 20) if over > 0 else x).astype(np.float32)


def cut(src: np.ndarray, start: float, end: float | None) -> np.ndarray:
    a = int(start * RATE)
    b = len(src) if end is None else int(end * RATE)
    return src[a:b]


def render(r: dict, src: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """-> (raw cut, finished sound)."""
    if src is None:
        src = source_audio(r["source"])
    raw = cut(src, r["start"], r["end"])
    x = filters(raw, r)
    if r["noise"] != "none":
        a, b = quietest(src) if r["noise"] == "auto" else r["noise"]
        x = denoise(x, filters(cut(src, a, b), r), r)
    x = expand(x, r)
    x = low_fade(x, r)
    x = notch_fade(x, r)
    x = channels(x, r["channels"])
    x = tail_resynth(x, r)
    x = fx(x, r)
    x = fades(x, r)
    return raw, level(x, r)


# ---------------------------------------------------------------- measuring

def peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(np.abs(x).max() + 1e-12))


def loudness(x: np.ndarray) -> float:
    """Integrated LUFS; a sound under 0.4 s is measured padded with silence."""
    import pyloudnorm as pyln
    if len(x) < int(0.41 * RATE):
        x = np.pad(x, ((0, int(0.41 * RATE) - len(x)), (0, 0)))
    v = pyln.Meter(RATE).integrated_loudness(x.astype(np.float64))
    return float(v) if np.isfinite(v) else -99.0


def floor_db(x: np.ndarray) -> float:
    """Noise floor: 10th percentile of 20 ms RMS windows."""
    n = int(0.02 * RATE)
    mono = x.mean(1)
    w = mono[: len(mono) // n * n].reshape(-1, n)
    if not len(w):
        return -99.0
    return float(20 * np.log10(np.percentile(np.sqrt((w ** 2).mean(1)), 10) + 1e-12))


def stats(x: np.ndarray) -> str:
    return (f"{len(x) / RATE:5.2f}s {x.shape[1]}ch  peak {peak_db(x):6.1f} dBFS  "
            f"{loudness(x):6.1f} LUFS  floor {floor_db(x):6.1f} dBFS")


def smoothness(x: np.ndarray) -> float:
    """Lag-1 autocorrelation: real audio sits near 1, bytes read the wrong way near 0."""
    m = x[:, 0].astype(np.float64)
    m = m - m.mean()
    d = (m * m).sum()
    return float((m[:-1] * m[1:]).sum() / d) if d else 1.0


def spectrogram(wav: Path, png: Path, title: str) -> None:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-lavfi",
         f"[0:a]showspectrumpic=s=900x260:legend=1:scale=log:fscale=log:stop=20000,"
         f"drawtext=text='{title}':x=10:y=4:fontcolor=white:fontsize=16[s];"
         f"[0:a]showwavespic=s=900x80:colors=orange[w];"
         f"[w][s]scale2ref=w=iw:h=80[w2][s2];[s2][w2]vstack=inputs=2", str(png)],
        check=True)


def write(x: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, x, RATE, subtype="PCM_16")


def project_path(res: str) -> Path:
    return PROJECT / res.removeprefix("res://")


# ---------------------------------------------------------------- commands

def pick(recipes: dict, names: list[str]) -> dict:
    unknown = [n for n in names if n not in recipes]
    if unknown:
        sys.exit(f"no recipe: {', '.join(unknown)} (have: {', '.join(recipes)})")
    return {n: recipes[n] for n in names} if names else recipes


def cmd_build(names: list[str]) -> None:
    for name, r in pick(load_recipes(), names).items():
        if not r["out"]:
            print(f"{name:24s} skipped (no out)")
            continue
        _, x = render(r)
        write(x, project_path(r["out"]))
        print(f"{name:24s} {stats(x)}  -> {r['out']}")


def cmd_report(out: str, names: list[str]) -> None:
    out_dir = Path(out)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, r in pick(load_recipes(), names).items():
        raw, x = render(r)
        write(raw, out_dir / f"{name}.raw.wav")
        write(x, out_dir / f"{name}.wav")
        spectrogram(out_dir / f"{name}.raw.wav", out_dir / f"{name}.raw.png", f"{name} raw")
        spectrogram(out_dir / f"{name}.wav", out_dir / f"{name}.png", f"{name} clean")
        print(f"{name:24s} raw   {stats(raw)}")
        print(f"{'':24s} clean {stats(x)}")


def cmd_sweep(name: str, out: str, specs: list[str]) -> None:
    r = pick(load_recipes(), [name])[name]
    out_dir = Path(out)
    out_dir.mkdir(parents=True, exist_ok=True)
    keys, values = [], []
    for s in specs:
        k, v = s.split("=", 1)
        if k not in DEFAULTS:
            sys.exit(f"unknown key {k}")
        variants = json.loads(v)
        if not isinstance(variants, list):
            sys.exit(f"{k}: give a JSON array of variants, e.g. {k}=[0.5,1.0]")
        keys.append(k)
        values.append(variants)
    src = source_audio(r["source"])
    for combo in itertools.product(*values):
        tag = "_".join(f"{k}{json.dumps(v, separators=(',', ':'))}" for k, v in zip(keys, combo))
        tag = tag.translate(str.maketrans({"[": "", "]": "", "{": "", "}": "", ",": "-", ":": "=", '"': ""}))
        _, x = render({**r, **dict(zip(keys, combo))}, src)
        wav = out_dir / f"{name}.{tag}.wav"
        write(x, wav)
        spectrogram(wav, wav.with_suffix(".png"), f"{name} {tag}")
        print(f"{tag:28s} {stats(x)}")


def cmd_check(files: list[str]) -> None:
    for f in files:
        info = sf.info(f) if Path(f).suffix.lower() in (".wav", ".flac", ".ogg") else None
        x = decode(Path(f))
        s = smoothness(x)
        header = f"{info.samplerate} Hz {info.channels}ch {info.subtype}" if info else ""
        verdict = "ok" if s > 0.3 else "BROKEN? content reads as white noise (wrong format?)"
        print(f"{f}\n  {header}  {stats(x)}  smoothness {s:.2f}  {verdict}")


def main(argv: list[str]) -> None:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return
    cmd, args = argv[0], argv[1:]
    if cmd == "build":
        cmd_build(args)
    elif cmd == "report" and args:
        cmd_report(args[0], args[1:])
    elif cmd == "sweep" and len(args) >= 3:
        cmd_sweep(args[0], args[1], args[2:])
    elif cmd == "check" and args:
        cmd_check(args)
    elif cmd == "synth" and len(args) >= 2:
        synth(Path(args[0]).resolve(), Path(args[1]).resolve(), float(args[2]) if len(args) > 2 else 3.0)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
