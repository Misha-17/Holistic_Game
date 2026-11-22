"""Original, reproducible 72 BPM ambient score; standard library only.

Soft sine-based keys and slow chord swells, without drums, noise or pressure
layers. Tails wrap around the loop boundary; the original audio is untouched.
"""
from array import array
from pathlib import Path
import math
import wave

RATE = 24000
BEAT = 60 / 72
BAR = 4 * BEAT
DURATION = 16 * BAR
OUTPUT = Path(__file__).with_name("beacon_bay_soft_v080.wav")


def compose():
    frames = round(DURATION * RATE)
    left = array("f", [0.0]) * frames
    right = array("f", [0.0]) * frames

    def note(start, pitch, duration, gain, pan=0.0, pad=False):
        hz = 440 * 2 ** ((pitch - 69) / 12)
        count = round(duration * RATE)
        begin = round(start * RATE)
        gl = gain * math.sqrt((1 - pan) / 2)
        gr = gain * math.sqrt((1 + pan) / 2)
        attack = 1.3 if pad else 0.12
        release = 2.0 if pad else 0.9
        for i in range(count):
            t = i / RATE
            onset = min(1.0, t / attack)
            end = min(1.0, (duration - t) / release)
            envelope = (0.5 - 0.5 * math.cos(math.pi * onset))
            envelope *= 0.5 - 0.5 * math.cos(math.pi * end)
            if not pad:
                envelope *= math.exp(-t * 0.95)
            phase = math.tau * hz * t
            # Fundamental dominates: neither metallic overtones nor sharp hits.
            value = math.sin(phase) + 0.075 * math.sin(2 * phase)
            value += 0.025 * math.sin(3 * phase) * math.exp(-t)
            value *= envelope
            index = (begin + i) % frames
            left[index] += value * gl
            right[index] += value * gr

    chords = [
        (48, (55, 59, 64, 67)),  # Cmaj7
        (43, (55, 57, 62, 67)),  # Gadd9
        (45, (55, 60, 64, 69)),  # Am7
        (41, (53, 57, 60, 64)),  # Fmaj7
        (50, (57, 60, 64, 65)),  # Dm9
        (43, (55, 60, 62, 67)),  # Gsus4
        (48, (55, 59, 64, 67)),  # Cmaj7
        (41, (53, 57, 60, 67)),  # Fadd9; resolves across the seam
    ]
    melody = [(76, 79), (74, 71), (72, 76), (69, 72),
              (74, 76), (74, 71), (72, 79), (76, 74)]
    for index, (bass, chord) in enumerate(chords):
        start = index * 2 * BAR
        note(start, bass, 2 * BAR + 2, 0.095, -0.08, pad=True)
        for voice, pitch in enumerate(chord):
            note(start, pitch, 2 * BAR + 2, 0.058, (voice - 1.5) * 0.3, pad=True)
        for step, pitch in enumerate(melody[index]):
            when = start + (1.5 + 3.75 * step) * BEAT
            pan = -0.2 if step == 0 else 0.2
            note(when, pitch, 3.3, 0.21, pan)
            note(when + BEAT * 0.75, pitch, 3.3, 0.025, -pan)

    peak = max(max(map(abs, left)), max(map(abs, right)))
    rms = math.sqrt(sum(x * x + y * y for x, y in zip(left, right)) / (2 * frames))
    scale = min(0.16 / rms, 0.50 / peak)
    pcm = array("h")
    for l, r in zip(left, right):
        pcm.extend((round(l * scale * 32767), round(r * scale * 32767)))
    with wave.open(str(OUTPUT), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    seam = max(abs(left[0] - left[-1]), abs(right[0] - right[-1])) * scale
    print(f"{OUTPUT.name}: {DURATION:.3f}s stereo, {RATE} Hz")
    print(f"peak={20 * math.log10(peak * scale):.2f} dBFS "
          f"RMS={20 * math.log10(rms * scale):.2f} dBFS seam={seam:.6f}")


if __name__ == "__main__":
    compose()
