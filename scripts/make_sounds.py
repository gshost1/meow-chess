#!/usr/bin/env python3
"""Three original synthesized packs. Pure Python; no recordings or external audio.

Run from the repo root. Every event has a distinct gesture (rhythm, contour or
voice), not merely a transposition. Deterministic noise keeps regeneration exact.
"""
import math
from pathlib import Path
import random
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'ios/MeowChess/Sounds'
PREVIEWS = ROOT / 'screenshots/sound-previews'
EVENTS = ('move', 'capture', 'check', 'checkmate', 'castle', 'blunder',
          'mistake', 'inaccuracy', 'best', 'correct', 'wrong')


def voice(duration, pitches, gain=0.12, kind='mew', roll=0):
    phase = 0.0
    noise = random.Random(41)
    filtered = 0.0
    samples = []
    n = round(duration * RATE)
    for i in range(n):
        x = i / (n - 1)
        t = i / RATE
        segment = min(int(x * (len(pitches) - 1)), len(pitches) - 2)
        u = (x * (len(pitches) - 1) - segment)
        u = (1 - math.cos(math.pi * u)) / 2
        hz = pitches[segment] + (pitches[segment + 1] - pitches[segment]) * u
        phase += 2 * math.pi * hz / RATE
        filtered = 0.84 * filtered + 0.16 * noise.uniform(-1, 1)
        if kind == 'mew':
            tone = (math.sin(phase) + 0.18 * math.sin(2 * phase)
                    + 0.04 * math.sin(3 * phase)) / 1.22
        elif kind == 'chirp':
            tone = (math.sin(phase) + 0.11 * math.sin(3 * phase)) / 1.11
        elif kind == 'purr':
            tone = (0.65 * math.sin(phase) + 0.3 * filtered) * (0.55 + 0.45 * math.sin(2 * math.pi * 27 * t))
        elif kind == 'puff':
            tone = filtered * 1.8
        else:  # a round, damped paw pop
            tone = math.sin(phase) * math.exp(-5 * x)
        envelope = math.sin(math.pi * x) ** (1.7 if kind != 'pop' else 0.7)
        tremolo = 0.65 + 0.35 * math.cos(2 * math.pi * roll * t) if roll else 1
        samples.append(gain * envelope * tremolo * tone)
    return samples


def phrase(*gestures):
    samples = []
    for duration, pitches, kind, gain, roll in gestures:
        if samples:
            samples.extend([0.0] * round(0.035 * RATE))
        samples.extend(voice(duration, pitches, gain, kind, roll))
    return samples


def g(duration, pitches, kind='mew', gain=0.13, roll=0):
    return duration, pitches, kind, gain, roll


def packs():
    soft = {
        'move': [g(.075, [440, 540, 410], gain=.065)],
        'capture': [g(.07, [380, 600]), g(.13, [590, 350])],
        'check': [g(.19, [460, 800, 800], roll=15)],
        'checkmate': [g(.12, [520, 650]), g(.12, [650, 760]), g(.24, [760, 480])],
        'castle': [g(.10, [340, 440]), g(.10, [440, 340])],
        'blunder': [g(.34, [620, 500, 260], roll=9)],
        'mistake': [g(.17, [380, 390, 700])],
        'inaccuracy': [g(.09, [480, 430])],
        'best': [g(.17, [480, 760, 600], kind='chirp')],
        'correct': [g(.10, [440, 620]), g(.23, [620, 850, 660], roll=22)],
        'wrong': [g(.08, [420, 340]), g(.12, [340, 260])],
    }
    chirps = {
        'move': [g(.055, [680, 1050, 800], 'chirp', .055)],
        'capture': [g(.07, [620, 1200], 'chirp'), g(.09, [1100, 600], 'chirp')],
        'check': [g(.075, [950, 1300], 'chirp'), g(.075, [950, 1300], 'chirp')],
        'checkmate': [g(.10, [600, 1000], 'chirp'), g(.10, [750, 1250], 'chirp'), g(.27, [1000, 700], 'chirp', roll=28)],
        'castle': [g(.23, [600, 850, 600], 'chirp', roll=24)],
        'blunder': [g(.28, [1100, 700, 320], 'chirp', roll=13)],
        'mistake': [g(.06, [650, 550], 'chirp'), g(.15, [550, 950], 'chirp')],
        'inaccuracy': [g(.08, [850, 650, 800], 'chirp', .09)],
        'best': [g(.20, [700, 1050], 'chirp', roll=32)],
        'correct': [g(.08, [700, 1000], 'chirp'), g(.08, [900, 1200], 'chirp'), g(.20, [1100, 850], 'chirp', roll=35)],
        'wrong': [g(.10, [750, 480], 'chirp'), g(.08, [650, 400], 'chirp')],
    }
    purrs = {
        'move': [g(.065, [260, 100], 'pop', .12)],
        'capture': [g(.07, [360, 130], 'pop', .20), g(.09, [150, 80], 'puff', .16)],
        'check': [g(.07, [450, 240], 'pop', .20), g(.07, [450, 240], 'pop', .20)],
        'checkmate': [g(.08, [300, 150], 'pop'), g(.10, [400, 200], 'pop'), g(.32, [160, 230, 150], 'purr', .20)],
        'castle': [g(.07, [220, 120], 'pop'), g(.12, [160, 100], 'pop')],
        'blunder': [g(.30, [150, 80], 'puff', .22)],
        'mistake': [g(.07, [100, 100], 'puff', .16), g(.12, [220, 150], 'purr', .19)],
        'inaccuracy': [g(.09, [120, 80], 'puff', .13)],
        'best': [g(.24, [130, 200, 150], 'purr', .20)],
        'correct': [g(.09, [300, 150], 'pop'), g(.32, [140, 230, 180], 'purr', .22)],
        'wrong': [g(.10, [110, 80], 'puff', .20), g(.10, [110, 80], 'puff', .20)],
    }
    return {'soft': soft, 'chirps': chirps, 'purrs': purrs}


def main():
    for pack, sounds in packs().items():
        assert set(sounds) == set(EVENTS)
        for event, gestures in sounds.items():
            samples = phrase(*gestures)
            assert max(abs(s) for s in samples) < .25
            # Prefixes survive Xcode resource flattening without name collisions.
            name = f'{pack}_{event}.wav'
            for target in (OUT / name, PREVIEWS / pack / f'{event}.wav'):
                target.parent.mkdir(parents=True, exist_ok=True)
                with wave.open(str(target), 'wb') as out:
                    out.setnchannels(1)
                    out.setsampwidth(2)
                    out.setframerate(RATE)
                    out.writeframes(b''.join(struct.pack('<h', round(s * 32767)) for s in samples))
            print(f'{pack}/{event}: {len(samples) / RATE:.3f}s')


if __name__ == '__main__':
    main()
