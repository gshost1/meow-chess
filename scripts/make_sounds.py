#!/usr/bin/env python3
"""Synthesizes the app's cat sound effects into ios/MeowChess/Sounds/*.wav.

A meow is modeled as a voice: a buzzy source whose pitch rises and falls, shaped by
mouth resonances (formants) that glide through vowels like "m-ee-ah-ow". Pure Python,
no dependencies. Run from the repository root: python3 scripts/make_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "ios", "MeowChess", "Sounds")

# Vowel resonances for a small cat: (frequency Hz, bandwidth Hz, gain)
VOWELS = {
    "m": [(350, 120, 1.0), (1300, 250, 0.15), (2600, 300, 0.05)],
    "i": [(500, 120, 1.0), (2700, 220, 0.6), (3600, 300, 0.35)],
    "e": [(700, 130, 1.0), (2300, 220, 0.5), (3300, 300, 0.3)],
    "a": [(1150, 160, 1.0), (1750, 200, 0.7), (3100, 300, 0.3)],
    "o": [(700, 140, 1.0), (1100, 180, 0.5), (2700, 300, 0.15)],
    "u": [(450, 120, 1.0), (900, 160, 0.3), (2500, 300, 0.08)],
}


def interp(points, x):
    """Piecewise-linear interpolation over [(x, y), ...] with x in 0..1."""
    if x <= points[0][0]:
        return points[0][1]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0) if x1 > x0 else 0
            return y0 + (y1 - y0) * t
    return points[-1][1]


def vowel_at(track, x):
    """Blend formants along a vowel track [(x, 'vowel'), ...]."""
    if x <= track[0][0]:
        return VOWELS[track[0][1]]
    for (x0, v0), (x1, v1) in zip(track, track[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0) if x1 > x0 else 0
            t = t * t * (3 - 2 * t)
            return [
                (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
                for a, b in zip(VOWELS[v0], VOWELS[v1])
            ]
    return VOWELS[track[-1][1]]


def voice(duration, pitch, vowels, env, vibrato=(0.0, 6.0), trill=None, breath=0.04, gain=0.8, seed=1):
    """One vocalisation.

    pitch:  [(x, Hz)]        vowels: [(x, 'a')]        env: [(x, amplitude 0..1)]
    vibrato: (depth as fraction of pitch, rate Hz)      trill: (rate Hz, depth 0..1, until x)
    """
    rnd = random.Random(seed)
    n = int(duration * RATE)
    out = [0.0] * n
    phase = 0.0
    block = 64
    amps = []
    lp = 0.0
    for i in range(n):
        x = i / n
        t = i / RATE
        f0 = interp(pitch, x)
        if vibrato[0]:
            f0 *= 1 + vibrato[0] * math.sin(2 * math.pi * vibrato[1] * t)
        f0 *= 1 + 0.004 * (rnd.random() - 0.5)  # slight jitter so it sounds alive
        if i % block == 0:
            formants = vowel_at(vowels, x)
            amps = []
            k = 1
            while k * f0 < 9000 and k < 40:
                h = k * f0
                a = sum(g / (1 + ((h - fc) / bw) ** 2) for fc, bw, g in formants)
                amps.append(a / (k ** 0.6))
                k += 1
        phase += 2 * math.pi * f0 / RATE
        s = 0.0
        for k, a in enumerate(amps, start=1):
            s += a * math.sin(k * phase)
        # Breathiness: filtered noise mixed in.
        lp += 0.25 * ((rnd.random() * 2 - 1) - lp)
        s += breath * 6 * lp
        a = interp(env, x)
        if trill and x < trill[2]:
            a *= 1 - trill[1] * (0.5 + 0.5 * math.cos(2 * math.pi * trill[0] * t))
        out[i] = s * a
    return normalize(out, gain)


def purr(duration, rate=26.0, gain=0.5, seed=2):
    rnd = random.Random(seed)
    n = int(duration * RATE)
    out = [0.0] * n
    lp1 = lp2 = 0.0
    for i in range(n):
        t = i / RATE
        x = i / n
        lp1 += 0.08 * ((rnd.random() * 2 - 1) - lp1)
        lp2 += 0.08 * (lp1 - lp2)
        pulse = (0.5 + 0.5 * math.sin(2 * math.pi * rate * t)) ** 4
        hum = 0.35 * math.sin(2 * math.pi * rate * 2 * t)
        env = min(1.0, x * 8) * min(1.0, (1 - x) * 5)
        out[i] = (lp2 * 4 + hum * 0.2) * pulse * env
    return normalize(out, gain)


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def normalize(samples, gain):
    peak = max(1e-9, max(abs(s) for s in samples))
    return [s / peak * gain for s in samples]


def fade(samples, ms=6):
    n = int(RATE * ms / 1000)
    for i in range(min(n, len(samples))):
        samples[i] *= i / n
        samples[-1 - i] *= i / n
    return samples


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    samples = fade(samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))
    print(f"{name:12s} {len(samples) / RATE:.2f}s")


def main():
    # Ordinary move: a short, soft "mew".
    write("move", voice(0.24, [(0, 640), (0.4, 790), (1, 600)], [(0, "i"), (0.5, "e"), (1, "a")],
                        [(0, 0), (0.15, 1), (0.6, 0.8), (1, 0)], gain=0.45))

    # Capture: a little "mrrp" trill into a confident "meow".
    write("capture", voice(0.42, [(0, 520), (0.25, 600), (0.5, 760), (1, 470)],
                           [(0, "m"), (0.25, "e"), (0.55, "a"), (1, "o")],
                           [(0, 0), (0.08, 0.7), (0.3, 1), (0.8, 0.7), (1, 0)],
                           trill=(32, 0.8, 0.25), gain=0.7, seed=3))

    # Check: a high, alarmed "MEOW!".
    write("check", voice(0.46, [(0, 820), (0.35, 1180), (0.7, 1050), (1, 880)],
                         [(0, "i"), (0.4, "a"), (1, "a")],
                         [(0, 0), (0.08, 1), (0.7, 0.9), (1, 0)],
                         vibrato=(0.02, 9), breath=0.03, gain=0.85, seed=4))

    # Checkmate: a long, dramatic yowl.
    write("checkmate", voice(1.25, [(0, 480), (0.2, 820), (0.45, 1000), (0.7, 760), (1, 430)],
                             [(0, "m"), (0.15, "e"), (0.4, "a"), (0.7, "o"), (1, "u")],
                             [(0, 0), (0.1, 0.9), (0.5, 1), (0.85, 0.7), (1, 0)],
                             vibrato=(0.035, 6.5), gain=0.9, seed=5))

    # Castling: a contented purr and a small chirp.
    chirp = voice(0.16, [(0, 620), (1, 950)], [(0, "e"), (1, "i")], [(0, 0), (0.3, 1), (1, 0)],
                  trill=(40, 0.6, 0.5), gain=0.55, seed=6)
    write("castle", purr(0.45) + silence(0.02) + chirp)

    # Blunder: a sad, drooping "meeeooww...".
    write("blunder", voice(0.95, [(0, 720), (0.3, 640), (0.7, 470), (1, 360)],
                           [(0, "i"), (0.3, "e"), (0.6, "a"), (0.85, "o"), (1, "u")],
                           [(0, 0), (0.1, 0.9), (0.5, 0.8), (1, 0)],
                           vibrato=(0.03, 4.5), breath=0.06, gain=0.75, seed=7))

    # Mistake: a questioning "mew?" that rises at the end.
    write("mistake", voice(0.36, [(0, 560), (0.5, 600), (1, 920)], [(0, "m"), (0.3, "e"), (1, "i")],
                           [(0, 0), (0.15, 0.9), (0.85, 0.9), (1, 0)], gain=0.6, seed=8))

    # Inaccuracy: a soft, unsure "mm?".
    write("inaccuracy", voice(0.28, [(0, 500), (1, 620)], [(0, "m"), (1, "u")],
                              [(0, 0), (0.25, 0.8), (1, 0)], breath=0.02, gain=0.45, seed=9))

    # Best move: a happy double chirp.
    c1 = voice(0.12, [(0, 780), (1, 1120)], [(0, "e"), (1, "i")], [(0, 0), (0.3, 1), (1, 0)], gain=0.6, seed=10)
    c2 = voice(0.13, [(0, 860), (1, 1250)], [(0, "e"), (1, "i")], [(0, 0), (0.3, 1), (1, 0)], gain=0.6, seed=11)
    write("best", c1 + silence(0.04) + c2)

    # Puzzle solved: three rising chirps.
    notes = []
    for j, base in enumerate([700, 880, 1050]):
        notes += voice(0.11, [(0, base), (1, base * 1.3)], [(0, "e"), (1, "i")],
                       [(0, 0), (0.3, 1), (1, 0)], gain=0.6, seed=20 + j) + silence(0.03)
    write("correct", notes)

    # Puzzle wrong: a grumpy low "mrrrr".
    write("wrong", voice(0.42, [(0, 330), (1, 270)], [(0, "m"), (0.4, "o"), (1, "u")],
                         [(0, 0), (0.2, 0.9), (1, 0)], trill=(28, 0.7, 1.0), breath=0.05, gain=0.6, seed=30))


if __name__ == "__main__":
    main()
