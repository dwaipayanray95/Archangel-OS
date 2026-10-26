#!/usr/bin/env python3
"""Generates Archangel OS's start-up chime. Original audio, stdlib only.

Run from the repository root:

    python3 -I tools/make_boot_chime.py

Writes app/frontend/assets/sounds/boot_chime.wav (about 2.8 s, played with the
long 7 s animation) and boot_chime_short.wav (about 1.2 s, for the short 2 s
animation). Both are 44.1 kHz, 16-bit stereo, peaking at about -6 dBFS.

The sound: a soft D major-9 arpeggio of bell-like notes (a sine fundamental
plus a few slightly inharmonic overtones, slow attack, long exponential
release), then a "bloom" where the whole chord opens together over a low,
quiet pad. Each note sits at its own place in the stereo field and the right
channel is a few milliseconds late, so it feels wide but stays calm.

The bloom lands at BLOOM seconds into each file (1.0 s long, 0.4 s short);
boot_splash.dart starts the files late enough that the bloom meets the
wordmark reveal.
"""

import math
import os
import random
import struct
import wave

RATE = 44100
PEAK = 0.501  # -6 dBFS
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "app", "frontend", "assets", "sounds")

# D major 9: D, F#, A, C#, E (Hz).
D3 = 146.83
D4 = 293.66
A4 = 440.00
CS5 = 554.37
E5 = 659.25
FS5 = 739.99
CS6 = 1108.73

# Bell partials: (frequency ratio, level, decay speed multiplier).
BELL = [(1.0, 1.0, 1.0), (2.0, 0.32, 1.6), (2.76, 0.12, 2.4), (5.4, 0.05, 3.5)]


def note(buf_l, buf_r, t0, freq, amp, pan, attack, decay, rng):
    """Adds one bell-like note starting at t0 seconds. pan runs -1..1."""
    start = int(t0 * RATE)
    n = int(min(len(buf_l) - start, (attack + decay * 7) * RATE))
    gl = math.cos((pan + 1) * math.pi / 4)
    gr = math.sin((pan + 1) * math.pi / 4)
    delay = int(0.011 * RATE)  # Haas-style widening: right side a touch late
    detune = 1 + rng.uniform(-0.0015, 0.0015)
    for ratio, level, speed in BELL:
        w = 2 * math.pi * freq * ratio * detune / RATE
        phase = rng.uniform(0, 2 * math.pi)
        for i in range(n):
            t = i / RATE
            env = (1 - math.exp(-t / (attack / 3))) * math.exp(-t * speed / decay)
            s = math.sin(w * i + phase) * level * amp * env
            buf_l[start + i] += s * gl
            j = start + i + delay
            if j < len(buf_r):
                buf_r[j] += s * gr


def pad(buf_l, buf_r, dur, freq, amp):
    """A very quiet, slow-swelling low sine group (the 'glow')."""
    n = min(len(buf_l), int(dur * RATE))
    for ratio, pan, weight in ((1.0, -0.3, 1.0), (1.0035, 0.3, 1.0), (1.5, 0.0, 0.5)):
        w = 2 * math.pi * freq * ratio / RATE
        gl = math.cos((pan + 1) * math.pi / 4)
        gr = math.sin((pan + 1) * math.pi / 4)
        for i in range(n):
            x = i / n
            env = math.sin(math.pi * min(1.0, x * 1.15)) ** 2 * (1 - x) ** 0.5
            s = math.sin(w * i) * amp * weight * env
            buf_l[i] += s * gl
            buf_r[i] += s * gr


def render(path, length, arpeggio, bloom_t, bloom_decay, pad_len):
    rng = random.Random(7)  # fixed seed: the same file every run
    n = int(length * RATE)
    left = [0.0] * n
    right = [0.0] * n
    pad(left, right, pad_len, D3, 0.10)
    # Rising arpeggio, each note a little quieter than a full strike.
    for t, f, pan in arpeggio:
        note(left, right, t, f, 0.42, pan, 0.045, 0.55, rng)
    # The bloom: the whole chord opens together, slower attack, long release.
    chord = [(D3, 0.50, -0.1), (D4, 0.42, -0.35), (A4, 0.38, 0.30), (E5, 0.34, -0.20), (FS5, 0.30, 0.45), (CS6, 0.16, 0.20)]
    for f, a, pan in chord:
        note(left, right, bloom_t, f, a, pan, 0.16, bloom_decay, rng)
    # Fade the last 120 ms so nothing clicks.
    fade = int(0.12 * RATE)
    for i in range(fade):
        g = i / fade
        left[n - 1 - i] *= g
        right[n - 1 - i] *= g
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    scale = PEAK / peak
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for a, b in zip(left, right):
            frames += struct.pack("<hh", int(a * scale * 32767), int(b * scale * 32767))
        w.writeframes(bytes(frames))
    print(f"{os.path.normpath(path)}: {length:.2f} s, {os.path.getsize(path) // 1024} KB, peak {20 * math.log10(PEAK):.1f} dBFS")


def main():
    os.makedirs(OUT, exist_ok=True)
    # Long cut: arpeggio over the first second, bloom at 1.0 s.
    render(
        os.path.join(OUT, "boot_chime.wav"),
        length=2.8,
        arpeggio=[(0.00, D4, -0.4), (0.18, A4, 0.3), (0.36, CS5, -0.2), (0.54, E5, 0.4), (0.72, FS5, -0.1)],
        bloom_t=1.0,
        bloom_decay=0.62,
        pad_len=2.6,
    )
    # Short cut: a quick three-note lift, bloom at 0.4 s.
    render(
        os.path.join(OUT, "boot_chime_short.wav"),
        length=1.2,
        arpeggio=[(0.00, A4, -0.3), (0.10, E5, 0.3), (0.20, FS5, 0.0)],
        bloom_t=0.4,
        bloom_decay=0.30,
        pad_len=1.1,
    )


if __name__ == "__main__":
    main()
