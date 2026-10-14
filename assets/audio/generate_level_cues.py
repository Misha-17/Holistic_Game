"""Level-hazard sound cues for Beacon Bay (Oct 2026), synthesised in code like
generate_audio.py. Run from anywhere: python generate_level_cues.py
Writes hazard.wav (forecast horn), power_down.wav, power_up.wav and wind.wav
next to this file. Deterministic: the same files every time."""
from array import array
from pathlib import Path
import math
import random
import wave

RATE = 24000
ROOT = Path(__file__).resolve().parent


def save(name, samples, level=0.7):
    peak = max(max(abs(v) for v in samples), 0.01)
    pcm = array('h')
    for v in samples:
        x = max(-1.0, min(1.0, v * level / peak))
        pcm.append(round(x * 32767))
        pcm.append(round(x * 32767))
    with wave.open(str(ROOT / name), 'wb') as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    print(f'{name}: {len(samples) / RATE:.2f}s')


def env(t, length, attack=0.01, release=0.15):
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (length - t) / release) if release > 0 else 1.0
    return max(0.0, min(a, r))


def horn():
    # Two-tone warning horn, three short blasts: "something is coming".
    out = []
    blasts = [(0.0, 0.26, 440.0), (0.32, 0.26, 587.33), (0.64, 0.42, 440.0)]
    length = 1.15
    for i in range(int(length * RATE)):
        t = i / RATE
        v = 0.0
        for start, dur, hz in blasts:
            if start <= t < start + dur:
                local = t - start
                phase = hz * local
                # soft square: a few odd harmonics
                tone = sum(math.sin(math.tau * phase * k) / k for k in (1, 3, 5, 7))
                v += 0.5 * tone * env(local, dur, 0.015, 0.06)
        out.append(v)
    return out


def power_down():
    # Electric hum dropping away with a crackle: the lights go out.
    rng = random.Random(77)
    out = []
    length = 1.0
    phase = 0.0
    for i in range(int(length * RATE)):
        t = i / RATE
        hz = 520.0 * math.exp(-3.2 * t) + 45.0
        phase += hz / RATE
        buzz = math.sin(math.tau * phase) + 0.35 * math.sin(math.tau * phase * 2.0) + 0.2 * (1 if math.sin(math.tau * phase * 3.0) > 0 else -1)
        crackle = (rng.random() * 2 - 1) * (0.5 if rng.random() < 0.02 else 0.04)
        out.append((0.55 * buzz + crackle) * env(t, length, 0.005, 0.35))
    return out


def power_up():
    # Hum rising back, then a bright three-note chime: lights back on.
    out = []
    length = 1.25
    phase = 0.0
    notes = [(0.55, 1046.5), (0.65, 1318.5), (0.75, 1568.0)]
    for i in range(int(length * RATE)):
        t = i / RATE
        v = 0.0
        if t < 0.6:
            hz = 60.0 + 440.0 * (t / 0.6) ** 1.6
            phase += hz / RATE
            v += 0.35 * (math.sin(math.tau * phase) + 0.3 * math.sin(math.tau * phase * 2.0)) * env(t, 0.6, 0.05, 0.08)
        for start, hz in notes:
            if t >= start:
                local = t - start
                v += 0.3 * math.sin(math.tau * hz * local) * math.exp(-local * 5.0) * (1 + 0.3 * math.sin(math.tau * hz * 2.0 * local))
        out.append(v * env(t, length, 0.01, 0.2))
    return out


def wind():
    # Gusting filtered noise with a faint whistle: the storm arrives.
    rng = random.Random(4242)
    out = []
    length = 1.8
    low = 0.0
    band = 0.0
    phase = 0.0
    for i in range(int(length * RATE)):
        t = i / RATE
        noise = rng.random() * 2 - 1
        cutoff = 0.02 + 0.06 * (0.5 + 0.5 * math.sin(t * 7.0))
        low += cutoff * (noise - low)
        band += 0.3 * (low - band)
        gust = 0.6 + 0.4 * math.sin(t * 5.3) * math.sin(t * 2.1)
        phase += (700.0 + 180.0 * math.sin(t * 3.0)) / RATE
        whistle = 0.05 * math.sin(math.tau * phase)
        swell = min(1.0, t / 0.5) * min(1.0, (length - t) / 0.6)
        out.append((3.2 * (low - band) * gust + whistle) * max(0.0, swell))
    return out


if __name__ == '__main__':
    save('hazard.wav', horn(), 0.62)
    save('power_down.wav', power_down(), 0.6)
    save('power_up.wav', power_up(), 0.6)
    save('wind.wav', wind(), 0.66)
