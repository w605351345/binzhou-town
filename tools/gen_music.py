#!/usr/bin/env python3
"""Generate deterministic, seamless background-music loops for Meadowbrook."""

from __future__ import annotations

import argparse
import math
import random
import wave
from pathlib import Path

SAMPLE_RATE = 16000
MAJOR = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 24]
MINOR = [0, 2, 3, 5, 7, 8, 10, 12, 14, 15, 17, 19, 20, 24]

TRACKS = {
    "farm": {
        "root": 50, "scale": MAJOR, "tempo": 78, "chords": [0, 5, 3, 4, 0, 5, 3, 4],
        "melody": [4, 6, 7, 9, 7, 6, 4, 2, 4, 7, 9, 11, 9, 7, 6, 4],
        "voices": ("pluck", "bass", "pad", "shaker"), "brightness": 0.72,
    },
    "home": {
        "root": 48, "scale": MAJOR, "tempo": 62, "chords": [0, 3, 5, 3, 0, 4, 3, 0],
        "melody": [7, 5, 4, 5, 7, 9, 7, 4, 5, 4, 2, 4, 5, 7, 5, 2],
        "voices": ("bell", "bass", "pad"), "brightness": 0.56,
    },
    "town": {
        "root": 55, "scale": MAJOR, "tempo": 94, "chords": [0, 4, 5, 3, 0, 4, 5, 4],
        "melody": [7, 9, 11, 9, 7, 6, 4, 6, 7, 11, 9, 7, 6, 4, 2, 4],
        "voices": ("pluck", "flute", "bass", "shaker"), "brightness": 0.82,
    },
    "shop": {
        "root": 53, "scale": MAJOR, "tempo": 84, "chords": [0, 5, 3, 4, 0, 5, 4, 3],
        "melody": [4, 6, 7, 11, 9, 7, 6, 4, 2, 4, 6, 7, 9, 7, 6, 4],
        "voices": ("bell", "pluck", "bass", "shaker"), "brightness": 0.78,
    },
    "post": {
        "root": 52, "scale": MAJOR, "tempo": 72, "chords": [0, 4, 3, 5, 0, 4, 5, 3],
        "melody": [7, 6, 4, 6, 7, 9, 7, 4, 5, 7, 11, 9, 7, 6, 4, 2],
        "voices": ("flute", "bell", "bass"), "brightness": 0.68,
    },
    "restaurant": {
        "root": 50, "scale": MAJOR, "tempo": 88, "chords": [0, 3, 4, 5, 0, 3, 4, 4],
        "melody": [4, 5, 7, 9, 7, 5, 4, 2, 4, 7, 9, 11, 9, 7, 5, 4],
        "voices": ("pluck", "bell", "bass", "shaker"), "brightness": 0.74,
    },
    "clinic": {
        "root": 53, "scale": MAJOR, "tempo": 60, "chords": [0, 3, 5, 4, 0, 3, 4, 3],
        "melody": [7, 6, 4, 2, 4, 6, 7, 9, 7, 6, 4, 5, 4, 2, 0, 2],
        "voices": ("bell", "pad", "bass"), "brightness": 0.58,
    },
    "workshop": {
        "root": 48, "scale": MAJOR, "tempo": 82, "chords": [0, 4, 5, 3, 0, 4, 3, 5],
        "melody": [4, 4, 7, 6, 4, 2, 4, 5, 7, 7, 9, 7, 6, 4, 5, 2],
        "voices": ("pluck", "bass", "shaker"), "brightness": 0.62,
    },
    "river": {
        "root": 51, "scale": MAJOR, "tempo": 68, "chords": [0, 5, 3, 4, 0, 5, 4, 3],
        "melody": [7, 9, 11, 9, 7, 6, 7, 4, 5, 7, 9, 11, 9, 7, 6, 4],
        "voices": ("flute", "pad", "bass"), "brightness": 0.64,
    },
    "forest": {
        "root": 47, "scale": MINOR, "tempo": 62, "chords": [0, 3, 5, 4, 0, 3, 4, 5],
        "melody": [7, 9, 10, 9, 7, 5, 4, 5, 7, 10, 12, 10, 9, 7, 5, 4],
        "voices": ("flute", "pad", "bass"), "brightness": 0.48,
    },
    "theater": {
        "root": 45, "scale": MINOR, "tempo": 58, "chords": [0, 5, 3, 4, 0, 5, 4, 3],
        "melody": [7, 8, 10, 12, 10, 8, 7, 5, 4, 7, 10, 8, 7, 5, 4, 2],
        "voices": ("bell", "pad", "bass"), "brightness": 0.46,
    },
    "mine": {
        "root": 43, "scale": MINOR, "tempo": 52, "chords": [0, 5, 3, 4, 0, 5, 3, 4],
        "melody": [0, 2, 3, 5, 3, 2, 0, -2, 0, 3, 5, 7, 5, 3, 2, 0],
        "voices": ("pulse", "pad", "bass"), "brightness": 0.34,
    },
    "ranch": {
        "root": 50, "scale": MAJOR, "tempo": 74, "chords": [0, 3, 4, 5, 0, 3, 5, 4],
        "melody": [4, 7, 9, 7, 4, 2, 4, 5, 7, 9, 11, 9, 7, 5, 4, 2],
        "voices": ("pluck", "flute", "bass", "shaker"), "brightness": 0.76,
    },
    "museum": {
        "root": 49, "scale": MAJOR, "tempo": 60, "chords": [0, 4, 3, 5, 0, 4, 5, 3],
        "melody": [7, 5, 4, 2, 4, 5, 7, 9, 11, 9, 7, 5, 4, 2, 0, 2],
        "voices": ("bell", "flute", "pad", "bass"), "brightness": 0.54,
    },
}


def midi_to_hz(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def add_tone(buf: list[float], start: int, duration: float, freq: float,
             amp: float, kind: str, rng: random.Random) -> None:
    size = len(buf)
    count = min(size, max(1, int(duration * SAMPLE_RATE)))
    phase = rng.random() * math.tau
    for i in range(count):
        t = i / SAMPLE_RATE
        attack = min(1.0, t / (0.012 if kind in ("pluck", "pulse") else 0.18))
        if kind == "pluck":
            env = attack * math.exp(-5.8 * t / max(duration, 0.01))
            value = (math.sin(math.tau * freq * t + phase)
                     + 0.34 * math.sin(math.tau * freq * 2.01 * t + phase * 0.7)
                     + 0.12 * math.sin(math.tau * freq * 3.99 * t))
        elif kind == "bell":
            env = attack * math.exp(-4.2 * t / max(duration, 0.01))
            value = (math.sin(math.tau * freq * t + phase)
                     + 0.46 * math.sin(math.tau * freq * 2.73 * t)
                     + 0.20 * math.sin(math.tau * freq * 5.04 * t))
        elif kind == "flute":
            release = min(1.0, (count - i) / (0.20 * SAMPLE_RATE))
            env = attack * release * 0.82
            vibrato = math.sin(math.tau * 4.7 * t) * 0.006
            value = math.sin(math.tau * freq * (1.0 + vibrato) * t + phase)
            value += 0.16 * math.sin(math.tau * freq * 2.0 * t + phase)
        elif kind == "pad":
            release = min(1.0, (count - i) / (0.42 * SAMPLE_RATE))
            env = attack * release * 0.56
            value = (math.sin(math.tau * freq * t + phase)
                     + 0.50 * math.sin(math.tau * freq * 1.003 * t + 0.5)
                     + 0.18 * math.sin(math.tau * freq * 0.5 * t))
        elif kind == "bass":
            env = attack * math.exp(-3.1 * t / max(duration, 0.01))
            value = math.sin(math.tau * freq * t + phase)
            value += 0.18 * math.sin(math.tau * freq * 2.0 * t)
        elif kind == "pulse":
            env = math.exp(-11.0 * t) * 0.8
            value = math.sin(math.tau * freq * 0.5 * t) * 0.7 + math.sin(math.tau * freq * t) * 0.3
        else:
            env = math.exp(-34.0 * t)
            value = rng.uniform(-1.0, 1.0)
        buf[(start + i) % size] += value * env * amp


def render(spec: dict, seed: int) -> bytes:
    rng = random.Random(seed)
    beat = 60.0 / float(spec["tempo"])
    bar = beat * 4.0
    total = int(bar * len(spec["chords"]) * SAMPLE_RATE)
    buf = [0.0] * total
    root = int(spec["root"])
    scale = spec["scale"]
    voices = set(spec["voices"])
    brightness = float(spec["brightness"])

    for bar_index, chord_degree in enumerate(spec["chords"]):
        bar_start = int(bar_index * bar * SAMPLE_RATE)
        chord_root = root + scale[chord_degree]
        if "pad" in voices:
            for interval in (0, 4, 7):
                add_tone(buf, bar_start, bar * 0.94, midi_to_hz(chord_root + interval),
                         0.018 + brightness * 0.008, "pad", rng)
        if "bass" in voices:
            add_tone(buf, bar_start, beat * 2.5, midi_to_hz(chord_root - 12), 0.055, "bass", rng)
            add_tone(buf, bar_start + int(beat * 2 * SAMPLE_RATE), beat * 1.56,
                     midi_to_hz(chord_root - 7), 0.040, "bass", rng)
        melody = spec["melody"]
        for step in range(8):
            degree = melody[(bar_index * 8 + step) % len(melody)]
            start = bar_start + int(beat * (0.5 if step % 2 else 0.0) * SAMPLE_RATE)
            start += int(step * beat * 0.5 * SAMPLE_RATE)
            note = root + scale[max(0, min(len(scale) - 1, degree))]
            if "pluck" in voices and step % 2 == 0:
                add_tone(buf, start, beat * 0.92, midi_to_hz(note + 12),
                         0.045 + brightness * 0.018, "pluck", rng)
            if "bell" in voices and step in (1, 3, 5, 7):
                add_tone(buf, start, beat * 1.2, midi_to_hz(note + 12),
                         0.030 + brightness * 0.012, "bell", rng)
            if "flute" in voices and step % 4 in (0, 3):
                add_tone(buf, start, beat * 1.52, midi_to_hz(note + 12),
                         0.028 + brightness * 0.012, "flute", rng)
            if "pulse" in voices and step % 4 == 0:
                add_tone(buf, start, beat * 0.8, midi_to_hz(note),
                         0.045, "pulse", rng)
            if "shaker" in voices and step % 2 == 1:
                add_tone(buf, start, 0.09, 0.0, 0.012 + brightness * 0.004, "noise", rng)

    delay = int(0.19 * SAMPLE_RATE)
    wet = [0.0] * total
    for i, sample in enumerate(buf):
        wet[i] = sample + (wet[i - delay] if i >= delay else wet[(i - delay) % total]) * 0.16
    peak = max(1e-9, max(abs(v) for v in wet))
    gain = 0.62 / peak
    pcm = bytearray()
    for sample in wet:
        value = max(-1.0, min(1.0, sample * gain))
        pcm += int(value * 32767.0).to_bytes(2, "little", signed=True)
    return bytes(pcm)


def write_wav(path: Path, pcm: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(pcm)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Meadowbrook music loops")
    parser.add_argument("--out", default="assets/audio/music")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    out_dir = Path(args.out)
    made = 0
    skipped = 0
    for index, (name, spec) in enumerate(TRACKS.items()):
        path = out_dir / f"{name}.wav"
        if path.exists() and not args.force:
            skipped += 1
            continue
        write_wav(path, render(spec, 0xB17 + index * 97))
        made += 1
        print(f"  ✓ {path}")
    print(f"背景音乐:生成 {made} 首，跳过 {skipped} 首 → {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
