"""Generates the game's music and sound effects.

Kept in the repo so the audio can be re-rendered or retuned later instead of
being an opaque binary blob. Run it from anywhere:

    python3 make_audio.py <output-folder>
"""
import os
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
RNG = np.random.default_rng(20261022)


# --- building blocks --------------------------------------------------------

def seconds(n):
    return np.zeros(int(SR * n))


def env_adsr(n, attack, decay, sustain, release):
    """Classic four-stage envelope, lengths in seconds."""
    a, d, r = int(SR * attack), int(SR * decay), int(SR * release)
    s = max(n - a - d - r, 0)
    parts = [
        np.linspace(0, 1, a, endpoint=False) if a else np.array([]),
        np.linspace(1, sustain, d, endpoint=False) if d else np.array([]),
        np.full(s, sustain),
        np.linspace(sustain, 0, r) if r else np.array([]),
    ]
    out = np.concatenate([p for p in parts if p.size])
    return np.resize(out, n)


def env_exp(n, hold=0.0, power=3.0):
    """Percussive decay: flat for `hold` seconds, then falling away."""
    h = int(SR * hold)
    tail = np.linspace(0, 1, max(n - h, 1)) ** power
    return np.concatenate([np.ones(h), 1.0 - tail])[:n]


def pluck(freq, dur, damping=0.996, brightness=0.5):
    """Karplus-Strong string: a short burst of noise fed through a delay line.

    This is what gives the melody its plucked, sarangi-like voice rather than
    the glassy sine tone a simple oscillator would produce.
    """
    n = int(SR * dur)
    period = max(int(SR / freq), 2)
    buf = RNG.uniform(-1, 1, period)
    buf = signal.lfilter([brightness, 1.0 - brightness], [1.0], buf)
    out = np.empty(n)
    idx = 0
    for i in range(n):
        out[i] = buf[idx]
        buf[idx] = damping * 0.5 * (buf[idx] + buf[(idx + 1) % period])
        idx = (idx + 1) % period
    return out * env_adsr(n, 0.002, 0.05, 0.75, max(dur * 0.4, 0.05))


def breath_tone(freq, dur, vibrato=4.6, depth=0.006, noise=0.10):
    """A bansuri-ish voice: sine plus a little air and a slow vibrato."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    bend = 1.0 + depth * np.sin(2 * np.pi * vibrato * t + RNG.uniform(0, 6))
    phase = 2 * np.pi * freq * np.cumsum(bend) / SR
    tone = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    air = band(RNG.normal(0, 1, n), freq * 1.6, freq * 4.0) * noise
    return (tone + air) * env_adsr(n, 0.08, 0.12, 0.85, dur * 0.35)


def drone(freqs, dur):
    """Tanpura-style bed: detuned pairs beating slowly against each other."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in freqs:
        for detune, level in ((1.0, 1.0), (1.003, 0.7), (0.997, 0.7), (2.0, 0.25)):
            out += level * np.sin(2 * np.pi * f * detune * t + RNG.uniform(0, 6))
    swell = 0.80 + 0.20 * np.sin(2 * np.pi * 0.07 * t)
    return low(out / (len(freqs) * 3.0), 900) * swell


def membrane(freq, dur, bend=0.55, noise=0.25, power=3.0):
    """Tabla-ish drum: a pitched head that drops in pitch, plus a slap."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    sweep = freq * (1.0 + bend * np.exp(-t * 26.0))
    body = np.sin(2 * np.pi * np.cumsum(sweep) / SR)
    body += 0.35 * np.sin(2 * np.pi * np.cumsum(sweep * 1.58) / SR)
    slap = band(RNG.normal(0, 1, n), freq * 3.0, 7000) * np.exp(-t * 90.0)
    return (body + noise * slap) * env_exp(n, 0.002, power)


def bell(freq, dur):
    """Temple bell: inharmonic partials over a long decay."""
    n = int(SR * dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, level, decay in ((1.0, 1.0, 1.6), (2.76, 0.55, 2.6), (5.40, 0.30, 4.0),
                                (8.93, 0.16, 6.0), (1.49, 0.22, 2.2)):
        out += level * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay)
    return out * env_adsr(n, 0.001, 0.02, 0.9, dur * 0.5)


def low(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff / (SR / 2), 0.99), btype="low")
    return signal.lfilter(b, a, x)


def high(x, cutoff, order=2):
    b, a = signal.butter(order, max(cutoff / (SR / 2), 1e-4), btype="high")
    return signal.lfilter(b, a, x)


def band(x, lo, hi, order=2):
    lo = max(lo / (SR / 2), 1e-4)
    hi = min(hi / (SR / 2), 0.99)
    if lo >= hi:
        return x
    b, a = signal.butter(order, [lo, hi], btype="band")
    return signal.lfilter(b, a, x)


def place(track, clip, at, gain=1.0):
    """Mixes `clip` into `track` at `at` seconds, wrapping any tail to the
    start so a loop joins onto itself without a click."""
    n = len(track)
    start = int(SR * at) % n
    end = start + len(clip)
    if end <= n:
        track[start:end] += clip * gain
    else:
        track[start:] += clip[: n - start] * gain
        wrapped = clip[n - start :][:n] * gain
        track[: len(wrapped)] += wrapped
    return track


def pan_gains(pan):
    """pan 0 = hard left, 1 = hard right."""
    angle = np.clip(pan, 0.0, 1.0) * np.pi / 2
    return np.cos(angle), np.sin(angle)


def normalise(x, peak=0.89):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def soften(x, drive=1.4):
    """Gentle saturation so transients glue instead of clipping."""
    return np.tanh(x * drive) / np.tanh(drive)


def fade_edges(x, ms=6):
    n = int(SR * ms / 1000)
    if len(x) > 2 * n and n > 0:
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    return x


# --- notes ------------------------------------------------------------------

def note(name):
    """'D4' -> frequency. Sharps written as 'A#3'."""
    table = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
             "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    octave = int(name[-1])
    semitone = table[name[:-1]]
    return 440.0 * 2 ** ((semitone - 9) / 12 + (octave - 4))


# --- sound effects ----------------------------------------------------------

def sfx_whoosh(dur, lo, hi, body):
    n = int(SR * dur)
    t = np.arange(n) / SR
    noise = RNG.normal(0, 1, n)
    sweep = np.zeros(n)
    # A moving band-pass reads as something cutting through the air.
    steps = 14
    for i in range(steps):
        a, b = int(n * i / steps), int(n * (i + 1) / steps)
        f = lo + (hi - lo) * np.sin(np.pi * (i + 0.5) / steps)
        sweep[a:b] = band(noise, f * 0.6, f * 1.8)[a:b]
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
    thump = np.sin(2 * np.pi * body * t) * np.exp(-t * 16.0) * 0.4
    return fade_edges(normalise(sweep * shape + thump, 0.72))


def sfx_impact(dur, pitch, crunch, weight):
    n = int(SR * dur)
    t = np.arange(n) / SR
    sweep = pitch * (1.0 + 1.1 * np.exp(-t * 34.0))
    thud = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * env_exp(n, 0.004, 2.2)
    snap = band(RNG.normal(0, 1, n), 900, 5200) * np.exp(-t * 48.0) * crunch
    sub = np.sin(2 * np.pi * pitch * 0.5 * t) * np.exp(-t * 11.0) * weight
    return fade_edges(normalise(soften(thud + snap + sub, 1.8), 0.88))


def build_sfx():
    out = {}

    out["punch_whoosh"] = sfx_whoosh(0.17, 700, 2600, 180)
    out["kick_whoosh"] = sfx_whoosh(0.26, 420, 1900, 120)

    out["hit_light"] = sfx_impact(0.26, 150, 0.55, 0.45)
    out["hit_heavy"] = sfx_impact(0.42, 92, 0.75, 0.85)

    # Jump: a scuff of the shoe plus a short rising breath.
    n = int(SR * 0.22)
    t = np.arange(n) / SR
    scuff = band(RNG.normal(0, 1, n), 600, 4200) * np.exp(-t * 26.0)
    rise = np.sin(2 * np.pi * np.cumsum(np.linspace(220, 520, n)) / SR) * env_exp(n, 0.0, 2.0) * 0.5
    out["jump"] = fade_edges(normalise(scuff + rise, 0.6))

    # Landing: low thud with grit on the stone.
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * np.cumsum(110 * (1 + 0.8 * np.exp(-t * 30))) / SR) * env_exp(n, 0.003, 2.4)
    grit = band(RNG.normal(0, 1, n), 1400, 7000) * np.exp(-t * 34.0) * 0.5
    out["land"] = fade_edges(normalise(soften(thud + grit, 1.5), 0.75))

    # UI: small wooden blips, tuned so they sit inside the music.
    n = int(SR * 0.09)
    t = np.arange(n) / SR
    blip = (np.sin(2 * np.pi * note("A5") * t) + 0.4 * np.sin(2 * np.pi * note("E6") * t))
    out["ui_move"] = fade_edges(normalise(blip * env_exp(n, 0.0, 2.5), 0.5))

    pick = seconds(0.42)
    place(pick, pluck(note("D5"), 0.34, 0.993), 0.0, 0.9)
    place(pick, pluck(note("A5"), 0.34, 0.993), 0.055, 0.8)
    out["ui_select"] = fade_edges(normalise(pick, 0.72))

    back = seconds(0.34)
    place(back, pluck(note("A4"), 0.3, 0.992), 0.0, 0.9)
    place(back, pluck(note("D4"), 0.3, 0.992), 0.05, 0.8)
    out["ui_back"] = fade_edges(normalise(back, 0.65))

    # Round start: a struck bell over the arena.
    gong = seconds(1.9)
    place(gong, bell(note("D4"), 1.8), 0.0, 1.0)
    place(gong, membrane(70, 0.5, 0.7, 0.4), 0.0, 0.8)
    out["round_start"] = fade_edges(normalise(soften(gong, 1.3), 0.85))

    # Knockout: heavy impact, then the bell rings out.
    ko = seconds(2.4)
    place(ko, sfx_impact(0.5, 70, 0.9, 1.0), 0.0, 1.0)
    place(ko, bell(note("A3"), 2.2), 0.09, 0.8)
    place(ko, membrane(52, 0.8, 0.6, 0.3, 2.0), 0.02, 0.7)
    out["ko"] = fade_edges(normalise(soften(ko, 1.5), 0.9))

    return out


# --- music ------------------------------------------------------------------
# Both tracks sit in D minor pentatonic over a D drone, which is the closest
# a few lines of synthesis get to the Himalayan folk colour of the stage.

PENT = ["D4", "F4", "G4", "A4", "C5", "D5", "F5", "G5", "A5"]


def build_menu_music():
    bpm = 68.0
    beat = 60.0 / bpm
    bars = 12
    total = bars * 4 * beat
    n = int(SR * total)
    left, right = np.zeros(n), np.zeros(n)

    bed = drone([note("D2"), note("A2"), note("D3")], total) * 0.34
    left += bed
    right += np.roll(bed, 700)

    # A slow, sparse flute line: four phrases, each answering the last.
    phrases = [
        [(0.0, "D5", 1.6), (2.0, "F5", 1.2), (3.4, "A4", 2.0)],
        [(0.0, "G4", 1.4), (1.8, "A4", 1.0), (3.0, "C5", 2.4)],
        [(0.0, "D5", 1.2), (1.4, "C5", 1.0), (2.6, "A4", 1.2), (3.9, "G4", 2.0)],
        [(0.0, "F4", 1.6), (2.2, "G4", 1.2), (3.6, "D4", 2.6)],
    ]
    for bar in range(bars):
        at = bar * 4 * beat
        phrase = phrases[bar % len(phrases)]
        if bar % 3 == 2:
            continue  # leave room to breathe
        for offset, name, dur in phrase:
            clip = breath_tone(note(name), dur) * 0.26
            place(left, clip, at + offset * beat, 0.9)
            place(right, clip, at + offset * beat + 0.012, 0.9)

    # Plucked counterpoint, panned the other way.
    for bar in range(bars):
        at = bar * 4 * beat
        for i, name in enumerate(["D4", "A4", "C5", "G4"]):
            if (bar + i) % 2:
                continue
            clip = pluck(note(name), 1.3, 0.994, 0.42) * 0.17
            place(right, clip, at + i * beat, 1.0)
            place(left, clip, at + i * beat, 0.5)

    for bar in range(0, bars, 4):
        clip = bell(note("D5"), 2.6) * 0.15
        place(left, clip, bar * 4 * beat)
        place(right, clip, bar * 4 * beat)

    left, right = soften(left, 1.1), soften(right, 1.1)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right))) or 1.0
    return np.stack([left, right], axis=1) * (0.52 / peak)


def build_arena_music():
    bpm = 100.0
    beat = 60.0 / bpm
    bars = 16
    total = bars * 4 * beat
    n = int(SR * total)
    left, right = np.zeros(n), np.zeros(n)

    bed = drone([note("D2"), note("A2")], total) * 0.26
    left += bed
    right += np.roll(bed, 900)

    # Tabla groove: a sixteen-step cycle with the accents on 1 and 3.
    pattern = [
        ("dha", 0), ("", 0), ("", 0), ("ti", 0),
        ("", 0), ("", 0), ("na", 0), ("", 0),
        ("dha", 0), ("", 0), ("", 0), ("ti", 0),
        ("", 0), ("ta", 0), ("", 0), ("", 0),
    ]
    voices = {
        "dha": (78.0, 0.42, 0.22, 1.0),
        "na": (300.0, 0.16, 0.45, 0.62),
        "ti": (420.0, 0.11, 0.55, 0.45),
        "ta": (240.0, 0.18, 0.40, 0.58),
    }
    for bar in range(bars):
        for step, (voice, _) in enumerate(pattern):
            if not voice:
                continue
            if bar % 4 == 3 and step in (6, 14):
                voice = "na"  # small turnaround fill
            freq, dur, noise, level = voices[voice]
            clip = membrane(freq, dur, 0.5, noise) * level * 0.22
            at = (bar * 4 + step * 0.25) * beat
            gl, gr = pan_gains(0.5 + (0.16 if voice in ("ti", "ta") else -0.06))
            place(left, clip, at, gl * 1.41)
            place(right, clip, at, gr * 1.41)

    # Bass: root movement that walks under the riff.
    bass_bars = [["D2", "D2", "A1", "D2"], ["D2", "C2", "A1", "A1"],
                 ["D2", "D2", "F2", "G2"], ["A1", "A1", "C2", "D2"]]
    for bar in range(bars):
        line = bass_bars[bar % len(bass_bars)]
        for i, name in enumerate(line):
            n_b = int(SR * beat * 0.9)
            t = np.arange(n_b) / SR
            f = note(name)
            tone = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t))
            clip = low(tone, 420) * env_adsr(n_b, 0.006, 0.08, 0.7, beat * 0.4) * 0.30
            place(left, clip, (bar * 4 + i) * beat, 1.0)
            place(right, clip, (bar * 4 + i) * beat, 1.0)

    # Melody: a four-bar riff, opened up in the second half of the loop.
    riff = [
        (0.0, "D5", 0.5), (0.5, "F5", 0.5), (1.0, "A4", 0.75), (2.0, "C5", 0.5),
        (2.5, "D5", 0.5), (3.0, "A4", 1.0),
    ]
    answer = [
        (0.0, "G5", 0.5), (0.75, "F5", 0.5), (1.25, "D5", 0.75), (2.25, "C5", 0.5),
        (3.0, "D5", 1.0),
    ]
    for bar in range(bars):
        at = bar * 4 * beat
        line = riff if (bar // 4) % 2 == 0 else answer
        if bar % 4 == 3:
            line = answer if line is riff else riff
        for offset, name, dur in line:
            level = 0.30 if bar < bars // 2 else 0.36
            clip = pluck(note(name), dur * beat * 1.6, 0.9955, 0.55) * level
            place(left, clip, at + offset * beat, 1.0)
            place(right, clip, at + offset * beat + 0.010, 0.92)

    for bar in range(0, bars, 8):
        clip = bell(note("D4"), 3.0) * 0.13
        place(left, clip, bar * 4 * beat)
        place(right, clip, bar * 4 * beat)

    left, right = soften(left, 1.2), soften(right, 1.2)
    # Left under 0.6 on purpose: Vorbis overshoots dense material slightly, and
    # the music must sit behind the hits rather than fight them.
    peak = max(np.max(np.abs(left)), np.max(np.abs(right))) or 1.0
    return np.stack([left, right], axis=1) * (0.58 / peak)


# --- output -----------------------------------------------------------------

def write_wav(path, data):
    wavfile.write(path, SR, (np.clip(data, -1, 1) * 32767).astype(np.int16))


def main(folder):
    os.makedirs(os.path.join(folder, "sfx"), exist_ok=True)
    for name, data in build_sfx().items():
        write_wav(os.path.join(folder, "sfx", name + ".wav"), data)
        print("sfx/%s.wav  %.2fs  peak %.2f" % (name, len(data) / SR, np.max(np.abs(data))))

    for name, builder in (("bgm_menu", build_menu_music), ("bgm_arena", build_arena_music)):
        stereo = builder()
        raw = os.path.join(folder, name + ".raw.wav")
        write_wav(raw, stereo)
        ogg = os.path.join(folder, name + ".ogg")
        os.system('ffmpeg -y -hide_banner -loglevel error -i "%s" -c:a libvorbis -q:a 5 "%s"' % (raw, ogg))
        os.remove(raw)
        print("%s.ogg  %.2fs  peak %.2f" % (name, len(stereo) / SR, np.max(np.abs(stereo))))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "audio")
