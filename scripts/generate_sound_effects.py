"""Original procedural BAT TV cues. No samples, recordings, songs or downloads.

Deterministic PCM16 mono/32000 Hz assets, compatible with both native mixers.
Run to regenerate; --check verifies committed bytes without writing files.
"""
import argparse
import hashlib
import math
from pathlib import Path
import struct

RATE = 32000
ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / 'iPhone/COURTSIDE/BATWeb', ROOT / 'Android/app/src/main/assets']


def synthesize(name):
    duration = {'horn': 1.75, 'crowd': 4.0, 'drums': 3.75}[name]
    seed = {'horn': 107, 'crowd': 211, 'drums': 307}[name]
    samples = []
    low = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        seed = (1664525 * seed + 1013904223) & 0xffffffff
        noise = seed / 2147483648.0 - 1.0
        low += .16 * (noise - low)
        if name == 'horn':
            # Single unpitched-pattern stadium-style horn, no musical phrase.
            phase = 2 * math.pi * (233 * t + .3 * math.sin(2 * math.pi * 5 * t))
            value = sum(math.sin(k * phase) / k for k in range(1, 7)) / 2
        elif name == 'crowd':
            # Synthetic cheering/applause texture, not an actual crowd recording.
            value = .48 * low
            for j in range(6):
                frequency = 290 + 37 * j
                phase = 2 * math.pi * (frequency * t + 5 * math.sin(t * (3 + j * .3)))
                voice = math.sin(phase) + .3 * math.sin(phase * 2)
                swell = max(0, math.sin(t * (2.2 + j * .12) + j)) ** 2
                value += .07 * voice * swell
            clap_age = t % .137
            value += .35 * noise * math.exp(-clap_age * 65)
        else:
            # Noise bursts and a descending membrane oscillator create a roll.
            age = t % .075
            phase = 2 * math.pi * (110 * age + 6 * (1 - math.exp(-age * 30)))
            value = (.65 * noise + .35 * math.sin(phase)) * math.exp(-age * 48)
            value *= .5 + .5 * t / duration
        fade = min(1.0, t / .025, (duration - 1 / RATE - t) / .12)
        samples.append(value * max(0, fade))
    # Fixed -6 dBFS peak leaves headroom before the native 25% cue mix.
    scale = 16384 / max(abs(x) for x in samples)
    pcm = b''.join(struct.pack('<h', round(x * scale)) for x in samples)
    header = b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVEfmt '
    header += struct.pack('<IHHIIHH', 16, 1, 1, RATE, RATE * 2, 2, 16)
    return header + b'data' + struct.pack('<I', len(pcm)) + pcm


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for name in ('horn', 'crowd', 'drums'):
        wav = synthesize(name)
        for target in TARGETS:
            path = target / (name + '.wav')
            if args.check:
                assert path.read_bytes() == wav, f'Non-reproducible cue: {path}'
            else:
                path.write_bytes(wav)
        print(name, hashlib.sha256(wav).hexdigest())


if __name__ == '__main__':
    main()
