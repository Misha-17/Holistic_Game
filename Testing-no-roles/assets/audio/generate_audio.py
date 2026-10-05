from array import array
from pathlib import Path
import math
import random
import wave
RATE = 24000
TAU = math.tau
BPM = 90
BEAT = 60.0 / BPM
BARS = 16
DURATION = BARS * 4 * BEAT
ROOT = Path(__file__).resolve().parent
RNG = random.Random(3107)

class Canvas:

    def __init__(self, duration, loop=False):
        self.n = round(duration * RATE)
        self.left = array('f', [0.0]) * self.n
        self.right = array('f', [0.0]) * self.n
        self.loop = loop

    def add(self, start, samples, gain=1.0, pan=0.0):
        begin = round(start * RATE)
        gl = math.sqrt((1 - pan) * 0.5) * gain
        gr = math.sqrt((1 + pan) * 0.5) * gain
        for i, v in enumerate(samples):
            idx = begin + i
            if self.loop:
                idx %= self.n
            elif idx >= self.n:
                break
            if idx < 0:
                continue
            self.left[idx] += v * gl
            self.right[idx] += v * gr

    def save(self, name, level=0.76):
        peak = max(max((abs(v) for v in self.left)), max((abs(v) for v in self.right)), 0.01)
        scale = min(level / peak, 1.6)
        pcm = array('h')
        for l, r in zip(self.left, self.right):
            pcm.append(round(max(-1, min(1, l * scale)) * 32767))
            pcm.append(round(max(-1, min(1, r * scale)) * 32767))
        with wave.open(str(ROOT / name), 'wb') as out:
            out.setnchannels(2)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(pcm.tobytes())
        print(f'{name}: {self.n / RATE:.3f}s, peak {peak * scale:.3f}')

def frequency(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)

def tone(note, duration, kind='marimba'):
    hz = frequency(note)
    result = array('f')
    n = round(duration * RATE)
    for i in range(n):
        t = i / RATE
        phase = TAU * hz * t
        if kind == 'pad':
            attack = min(1.0, t / 0.32)
            release = min(1.0, (duration - t) / 0.7)
            env = attack * release * 0.7
            value = math.sin(phase) + 0.2 * math.sin(phase * 2) + 0.1 * math.sin(phase * 3 + math.sin(TAU * 0.18 * t) * 0.05)
            value *= env * (0.97 + 0.03 * math.sin(TAU * 0.32 * t))
        elif kind == 'bass':
            env = min(1.0, t / 0.015) * math.exp(-t * 2.3) * min(1.0, (duration - t) / 0.1)
            value = (math.sin(phase) + 0.11 * math.sin(phase * 2) + 0.06 * math.sin(phase * 3)) * env
        elif kind == 'bell':
            env = min(1.0, t / 0.009) * math.exp(-t * 2.6) * min(1.0, (duration - t) / 0.07)
            value = (math.sin(phase) + 0.24 * math.sin(phase * 2) * math.exp(-t * 3.0) + 0.09 * math.sin(phase * 3) * math.exp(-t * 7)) * env
        elif kind == 'pluck':
            env = min(1.0, t / 0.01) * math.exp(-t * 5.0) * min(1.0, (duration - t) / 0.03)
            value = (math.sin(phase) + 0.22 * math.sin(phase * 2) + 0.08 * math.sin(phase * 3)) * env
        elif kind == 'pulse':
            env = min(1.0, t / 0.025) * math.exp(-t * 3.4) * min(1.0, (duration - t) / 0.08)
            value = (math.sin(phase) + 0.28 * math.sin(phase * 2) * math.exp(-t * 2) + 0.13 * math.sin(phase * 3) + 0.035 * math.sin(phase * 5)) * env
        else:
            env = min(1.0, t / 0.008) * math.exp(-t * 4.0) * min(1.0, (duration - t) / 0.04)
            value = (math.sin(phase) + 0.3 * math.sin(phase * 3) * math.exp(-t * 18) + 0.1 * math.sin(phase * 7) * math.exp(-t * 40)) * env
        result.append(value)
    return result

def drum(kind):
    duration = {'kick': 0.2, 'rim': 0.07, 'brush': 0.12, 'tick': 0.065, 'tom': 0.31}[kind]
    result = array('f')
    noise_last = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        noise = RNG.uniform(-1, 1)
        low = 0.73 * noise_last + 0.27 * noise
        noise_last = low
        attack = min(1, t / 0.001)
        tail = min(1, (duration - t) / 0.01)
        if kind == 'kick':
            phase = TAU * (48 * t + 9 * (1 - math.exp(-t * 25)))
            value = math.sin(phase) * math.exp(-t * 21) * 0.72
        elif kind == 'rim':
            value = (0.18 * low + math.sin(TAU * 910 * t) * 0.22 + math.sin(TAU * 1340 * t) * 0.12) * math.exp(-t * 75)
        elif kind == 'brush':
            value = (noise - low) * math.exp(-t * 37) * 0.25
        elif kind == 'tom':
            phase = TAU * (71 * t + 2.8 * (1 - math.exp(-t * 20)))
            value = (math.sin(phase) + 0.14 * math.sin(phase * 1.55)) * math.exp(-t * 12) * 0.74
        else:
            value = (noise - low) * math.exp(-t * 75) * 0.17
        result.append(value * attack * tail)
    return result

def note_with_echo(canvas, beat, note, gain=0.14, pan=0.0, kind='marimba', duration=1.2):
    samples = tone(note, duration, kind)
    start = beat * BEAT
    canvas.add(start, samples, gain, pan)
    canvas.add(start + BEAT * 0.75, samples, gain * 0.16, -pan)
    canvas.add(start + BEAT * 1.5, samples, gain * 0.065, pan)

def compose():
    music = Canvas(DURATION, loop=True)
    tension = Canvas(DURATION, loop=True)
    pressure = Canvas(DURATION, loop=True)
    voicings = [(41, [57, 60, 64, 67]), (41, [57, 60, 64, 67]), (48, [55, 59, 62, 64]), (48, [55, 59, 62, 64]), (45, [55, 60, 64, 67]), (45, [55, 60, 64, 67]), (43, [55, 59, 62, 69]), (43, [55, 59, 62, 69]), (41, [57, 60, 64, 67]), (41, [57, 60, 64, 67]), (45, [55, 60, 64, 67]), (45, [55, 60, 64, 67]), (38, [57, 60, 64, 65]), (43, [55, 59, 62, 69]), (48, [55, 60, 64, 69]), (48, [55, 59, 62, 67])]
    kick, rim, brush, tick, tom = (drum(k) for k in ['kick', 'rim', 'brush', 'tick', 'tom'])
    for bar, (root, chord) in enumerate(voicings):
        start = bar * 4
        for j, n in enumerate(chord):
            music.add(start * BEAT, tone(n, BEAT * 4 + 0.7, 'pad'), 0.055, (j - 1.5) * 0.27)
        for b, n, gain in [(0, root, 0.23), (1.75, root + 7, 0.16), (2.5, root + 12, 0.12)]:
            music.add((start + b) * BEAT, tone(n, 0.7, 'bass'), gain, -0.08)
        for beat in [0, 2.5]:
            music.add((start + beat) * BEAT, kick, 0.29)
        for beat in [1, 3]:
            music.add((start + beat) * BEAT, rim, 0.22, 0.26)
        for eighth in range(8):
            offset = 0.018 if eighth % 2 else 0
            music.add((start + eighth * 0.5) * BEAT + offset, brush, 0.13 if eighth % 2 else 0.075, -0.4 if eighth % 2 else 0.32)
        for j, b in enumerate([0.5, 1.5, 2.75, 3.5]):
            n = chord[(j + bar) % 4] + 12
            note_with_echo(music, start + b, n, 0.08, -0.3 if j % 2 else 0.3, 'pluck', 0.9)
        for eighth in range(8):
            n = chord[(eighth + bar) % 4] + 12
            tension.add((start + eighth * 0.5) * BEAT, tone(n, 0.32, 'pluck'), 0.15, (eighth % 3 - 1) * 0.25)
            tension.add((start + eighth * 0.5) * BEAT + 0.17, tick, 0.3, -0.2)
        if bar % 4 == 3:
            tension.add((start + 3.5) * BEAT, rim, 0.35, 0.4)
        for beat in [0, 1.5, 2.5, 3.25]:
            pressure.add((start + beat) * BEAT, tone(root + 12, 0.34, 'pulse'), 0.25, -0.1)
            pressure.add((start + beat) * BEAT, kick, 0.38)
        for eighth in range(8):
            n = chord[(eighth // 2 + bar) % 4]
            pressure.add((start + eighth * 0.5 + 0.25) * BEAT, tone(n, 0.31, 'pulse'), 0.15 if eighth % 2 else 0.11, -0.42 if eighth % 2 else 0.42)
            pressure.add((start + eighth * 0.5) * BEAT, brush, 0.31 if eighth % 2 else 0.18, 0.34)
        for beat in [1, 3]:
            pressure.add((start + beat) * BEAT, tom, 0.36, -0.28)
            pressure.add((start + beat + 0.025) * BEAT, rim, 0.26, 0.18)
        for n in chord[1:]:
            pressure.add((start + 0.75) * BEAT, tone(n + 12, 0.55, 'pulse'), 0.09, 0.28)
        if bar % 4 == 3:
            for offset, gain in [(3.25, 0.17), (3.5, 0.23), (3.75, 0.29)]:
                pressure.add((start + offset) * BEAT, tom, gain, -0.35 + (offset - 3.25))
    melody = [(0.5, 76), (1.5, 79), (2.75, 81), (4.5, 79), (6, 76), (8.5, 74), (9.5, 76), (11, 79), (13, 76), (14.5, 74), (16.5, 72), (17.5, 76), (18.75, 79), (20.5, 81), (22, 79), (24.5, 74), (26, 71), (27.5, 74), (29, 76), (30.5, 74), (32.5, 76), (33.5, 79), (34.75, 84), (36.5, 81), (38, 79), (40.5, 76), (42, 72), (43.5, 76), (45, 79), (46.5, 81), (48.5, 77), (50, 76), (51.5, 74), (53, 71), (54.5, 74), (56.5, 76), (58, 79), (59.5, 76), (61, 74), (62.5, 72)]
    for j, (beat, note) in enumerate(melody):
        note_with_echo(music, beat, note, 0.17 if j % 3 == 0 else 0.145, math.sin(j * 1.7) * 0.17, 'marimba', 1.45)
    music.save('beacon_bay_90bpm.wav', 0.69)
    tension.save('beacon_bay_tension.wav', 0.38)
    pressure.save('beacon_bay_pressure.wav', 0.54)

def radio_noise(duration, gain=0.1):
    result = array('f')
    low = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        sample = RNG.uniform(-1, 1)
        low = 0.8 * low + 0.2 * sample
        env = min(1.0, t / 0.004) * min(1.0, (duration - t) / 0.012)
        result.append(low * env * gain)
    return result

def siren_pair():
    out = Canvas(0.72)
    sound = array('f')
    phase = 0.0
    duration = 0.58
    hz = 440.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        target = 440.0 if t < 0.22 else 659.255
        hz += (target - hz) * 0.0025
        phase += TAU * hz / RATE
        env = min(1.0, t / 0.018) * min(1.0, (duration - t) / 0.17)
        value = (math.sin(phase) + 0.12 * math.sin(phase * 3)) * env * 0.38
        sound.append(value)
    out.add(0.045, sound, 0.74, -0.08)
    out.add(0, radio_noise(0.055, 0.32), 0.75)
    out.add(0.61, radio_noise(0.055, 0.2), 0.48, 0.12)
    out.save('dispatch.wav', 0.43)

def response_cues():
    siren_pair()
    cue('urgent', [(0, 71, 0.46), (0.13, 71, 0.37), (0.28, 76, 0.39)], 0.82, 0.48, 'pulse')
    arrival = Canvas(0.55)
    arrival.add(0, radio_noise(0.032, 0.2), 0.65)
    arrival.add(0.04, tone(67, 0.24, 'pluck'), 0.44, -0.15)
    arrival.add(0.15, tone(72, 0.35, 'marimba'), 0.42, 0.15)
    arrival.save('arrival.wav', 0.37)
    surge = Canvas(1.12)
    surge.add(0, radio_noise(0.1, 0.36), 0.74, -0.1)
    surge.add(0.025, drum('tom'), 0.85, -0.15)
    surge.add(0.21, drum('tom'), 0.68, 0.12)
    surge.add(0.41, tone(48, 0.65, 'pulse'), 0.44)
    surge.add(0.41, tone(55, 0.65, 'pulse'), 0.23, 0.17)
    surge.add(0.45, radio_noise(0.21, 0.15), 0.6)
    surge.save('surge.wav', 0.57)
    work = Canvas(0.27)
    work.add(0, drum('rim'), 0.34, -0.12)
    work.add(0.073, tone(60, 0.18, 'pluck'), 0.19, 0.12)
    work.add(0.1, radio_noise(0.045, 0.1), 0.38)
    work.save('work.wav', 0.25)

def cue(name, notes, duration, volume=0.55, kind='bell'):
    out = Canvas(duration)
    for start, note, gain in notes:
        samples = tone(note, min(1.25, duration - start), kind)
        out.add(start, samples, gain, -0.1 if note % 2 else 0.1)
        out.add(start + 0.095, samples, gain * 0.12, 0.35)
    out.save(f'{name}.wav', volume)

def cues():
    response_cues()
    cue('rescue', [(0, 72, 0.48), (0.095, 76, 0.43), (0.19, 79, 0.42), (0.31, 84, 0.38)], 1.55, 0.57)
    cue('alarm', [(0, 69, 0.34), (0.25, 72, 0.3)], 0.75, 0.4, 'marimba')
    cue('click', [(0, 72, 0.24)], 0.105, 0.23, 'pluck')
    cue('upgrade', [(0, 60, 0.32), (0.075, 64, 0.35), (0.15, 67, 0.34), (0.225, 72, 0.36), (0.34, 76, 0.34), (0.46, 79, 0.33)], 1.9, 0.6)
    cue('fail', [(0, 64, 0.4), (0.18, 60, 0.36), (0.36, 57, 0.31)], 1.1, 0.44, 'marimba')
    cue('shift', [(0, 60, 0.35), (0, 67, 0.25), (0.16, 64, 0.32), (0.32, 69, 0.32), (0.48, 72, 0.34), (0.64, 76, 0.32), (0.64, 79, 0.25)], 2.1, 0.63)
    cue('combo', [(0, 79, 0.33), (0.075, 84, 0.35), (0.15, 88, 0.29)], 1.2, 0.51)
if __name__ == '__main__':
    compose()
    cues()
