#!/usr/bin/env python3
"""Writes soundtrack.wav: 20.000 s at 96 BPM (32 beats), the grid scene.js runs on.
Soft kick on every beat, closed hat on the off-beats, one bass note per bar, and a short tick
on each tap beat, and a soft swell under each push / sheet transition. Pure standard library; noise is seeded so every run is identical."""
import math, random, struct, wave

SR = 44100
BPM = 96
B = 60 / BPM
DUR = 32 * B
N = int(round(DUR * SR))
TAPS = [4, 6, 9, 17, 21, 24]                  # beats, same as TAPS in scene.js
SWELLS = [4, 17, 21]                          # taps that push or raise a sheet
BASS = [55.00, 55.00, 43.65, 43.65, 49.00, 49.00, 41.20, 55.00]   # A1 A1 F1 F1 G1 G1 E1 A1, one per bar
rng = random.Random(7)
noise = [rng.uniform(-1, 1) for _ in range(SR)]
buf = [0.0] * N


def add(start, fn, length):
    i0 = int(start * SR)
    for i in range(max(0, i0), min(N, i0 + int(length * SR))):
        buf[i] += fn((i - i0) / SR)


def kick(t):
    f = 45 + 75 * math.exp(-t * 28)
    phase = 2 * math.pi * (45 * t + 75 * (1 - math.exp(-t * 28)) / 28)
    return 0.55 * math.sin(phase) * math.exp(-t * 9)


def hat(t):
    i = int(t * SR) % len(noise)
    hp = noise[i] - noise[i - 1]                # crude high-pass
    return 0.07 * hp * math.exp(-t * 60)


def tick(t):
    return 0.16 * math.sin(2 * math.pi * 2200 * t) * math.exp(-t * 90)


def bass(freq):
    def fn(t):
        env = min(1, t / 0.02) * math.exp(-t * 0.9)
        s = math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(2 * math.pi * 2 * freq * t)
        return 0.22 * env * s
    return fn


for beat in range(32):
    add(beat * B, kick, 0.4)
    add(beat * B + B / 2, hat, 0.08)
for bar, f in enumerate(BASS):
    add(bar * 4 * B, bass(f), 4 * B)
for b in TAPS:
    add(b * B, tick, 0.06)


def swell(t):
    # Band-limited noise rising then falling over 0.6 s (the push / sheet movement).
    i = int(t * SR)
    lp = sum(noise[(i - k) % len(noise)] for k in range(24)) / 24      # crude low-pass
    return 0.10 * lp * math.sin(math.pi * min(1, t / 0.6)) ** 2


for b in SWELLS:
    add(b * B + 0.08, swell, 0.6)

# Fade the last 0.3 s, soft-limit, write 16-bit stereo.
for i in range(N):
    left = (N - i) / SR
    g = min(1.0, left / 0.3)
    buf[i] = math.tanh(buf[i] * g * 1.2) * 0.85

with wave.open('soundtrack.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b''.join(struct.pack('<hh', int(s * 32767), int(s * 32767)) for s in buf))
print(f'soundtrack.wav {DUR:.3f} s, {BPM} BPM')
