#!/usr/bin/env python3
"""Original synthesized cat mews for Meow Chess; no recordings or third-party audio.

Pure Python. Run from the repo root: python3 scripts/make_sounds.py.
A rounded voice with smoothly gliding pitch/vowels, four soft partials, and a
raised-sine envelope avoids the old bright, jittery, high-harmonic buzz.
"""
import math
from pathlib import Path
import struct
import wave

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "ios/MeowChess/Sounds"


def glide(points, x):
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x <= x1:
            t = max(0, min(1, (x - x0) / (x1 - x0)))
            t = (1 - math.cos(math.pi * t)) / 2
            return y0 + (y1 - y0) * t
    return points[-1][1]


def mew(duration, pitches, gain):
    n = round(duration * RATE)
    phase = 0.0
    samples = []
    for i in range(n):
        x = i / (n - 1)
        t = i / RATE
        frequency = glide(pitches, x) * (1 + 0.006 * math.sin(2 * math.pi * 5 * t))
        phase += 2 * math.pi * frequency / RATE
        # Closed "m", opening "ee-ah", then closing "ow". Keep the fundamental
        # dominant; higher partials roll off rapidly and remain far below clipping.
        opening = math.sin(math.pi * x) ** 2
        tone = (math.sin(phase)
                + (0.10 + 0.12 * opening) * math.sin(2 * phase)
                + 0.045 * opening * math.sin(3 * phase)
                + 0.012 * opening * math.sin(4 * phase)) / 1.3
        envelope = math.sin(math.pi * x) ** 1.8
        samples.append(gain * envelope * tone)
    return samples


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    assert max(abs(s) for s in samples) < 0.25
    with wave.open(str(OUT / (name + ".wav")), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(s * 32767)) for s in samples))
    print(f"{name:12s} {len(samples) / RATE:.2f}s, peak {max(abs(s) for s in samples):.3f}")


def main():
    # All are short cat vocal gestures. Ordinary moves stay especially quiet.
    sounds = {
        "move": (0.09, [460, 560, 410], 0.075),
        "capture": (0.20, [420, 620, 390], 0.15),
        "check": (0.24, [560, 740, 520], 0.17),
        "checkmate": (0.42, [400, 690, 350], 0.18),
        "castle": (0.23, [360, 500, 440], 0.13),
        "blunder": (0.36, [560, 450, 300], 0.15),
        "mistake": (0.22, [400, 460, 640], 0.13),
        "inaccuracy": (0.16, [380, 420, 480], 0.10),
        "best": (0.21, [520, 720, 580], 0.14),
        "correct": (0.30, [450, 730, 610], 0.16),
        "wrong": (0.24, [380, 340, 280], 0.12),
    }
    for name, (duration, pitches, gain) in sounds.items():
        write(name, mew(duration, list(zip([0, 0.45, 1], pitches)), gain))


if __name__ == "__main__":
    main()
