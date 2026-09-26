#!/usr/bin/env python3
"""Lays the narration clips on one timeline, adds Ambient's chimes, and writes:

  out/film/timeline.json   scene starts and durations, read by film.js
  out/film/narration.wav   the mixed voice-and-chime track (24 kHz mono)
  out/film/captions.srt    captions for platforms that take a sidecar file

Run with the Kokoro environment's Python (it has numpy and soundfile):
  <open-tts>/.venv/bin/python film/timeline.py
"""

import json
import math
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
RATE = 24_000
LEAD = 0.5  # seconds of picture before the voice starts
TAIL = 0.9  # seconds after it ends
MIN_SCENE = 5.0
# Scenes that open on a chime give it room before the voice.
LEAD_FOR = {"needs-you": 1.0, "done": 0.8}
TAIL_FOR = {"cta": 2.8, "agents": 1.2}


def chime(notes, warmth=0.3, rate=RATE):
    """Ambient's Chimes.swift formula: decaying sine partials with a 4 ms attack."""
    length = max(start + decay * 6 for _, start, decay in notes)
    t_all = np.arange(int(length * rate)) / rate
    out = np.zeros_like(t_all)
    for freq, start, decay in notes:
        t = t_all - start
        on = t >= 0
        tt = t[on]
        env = np.minimum(1, tt / 0.004) * np.exp(-tt / decay)
        w = 2 * math.pi * freq * tt
        out[on] += env * (np.sin(w) + warmth * np.sin(2 * w) * np.exp(-tt / (decay * 0.5)) + 0.08 * np.sin(3 * w))
    return out / np.max(np.abs(out)) * 0.55


CHIMES = {
    "waiting": chime([(880, 0, 0.16), (880, 0.17, 0.26)]),
    "done": chime([(659.25, 0, 0.38), (987.77, 0.11, 0.5)]),
}
# Which scene opens on which chime, and when.
CHIME_AT = {"needs-you": ("waiting", 0.35), "done": ("done", 0.25)}


def srt_time(seconds):
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"


def main():
    script = json.loads((ROOT / "film" / "script.json").read_text())
    out = ROOT / "out" / "film"
    out.mkdir(parents=True, exist_ok=True)

    scenes, start = [], 0.0
    for i, scene in enumerate(script["scenes"]):
        clip, rate = sf.read(ROOT / "out" / "narration" / f"scene-{i:04}.wav", dtype="float64")
        assert rate == RATE, f"scene {i}: expected {RATE} Hz, got {rate}"
        lead = LEAD_FOR.get(scene["id"], LEAD)
        tail = TAIL_FOR.get(scene["id"], TAIL)
        voice = len(clip) / RATE
        duration = max(MIN_SCENE, math.ceil((lead + voice + tail) * 10) / 10)
        scenes.append({"id": scene["id"], "start": round(start, 3), "duration": duration,
                       "voiceStart": round(start + lead, 3), "voiceDuration": round(voice, 3),
                       "caption": scene["caption"], "clip": clip})
        start += duration

    total = start
    mix = np.zeros(int(math.ceil(total * RATE)) + RATE)
    for s in scenes:
        at = int(s["voiceStart"] * RATE)
        mix[at:at + len(s["clip"])] += s["clip"]
        if s["id"] in CHIME_AT:
            name, offset = CHIME_AT[s["id"]]
            c = CHIMES[name] * 0.45
            at = int((s["start"] + offset) * RATE)
            mix[at:at + len(c)] += c
    peak = np.max(np.abs(mix))
    if peak > 0.95:
        mix *= 0.95 / peak
    sf.write(out / "narration.wav", mix[: int(total * RATE)], RATE, subtype="PCM_16")

    with open(out / "captions.srt", "w") as f:
        for i, s in enumerate(scenes, 1):
            a = s["voiceStart"] - 0.1
            b = s["voiceStart"] + s["voiceDuration"] + 0.4
            f.write(f"{i}\n{srt_time(a)} --> {srt_time(b)}\n{s['caption']}\n\n")

    for s in scenes:
        del s["clip"]
    (out / "timeline.json").write_text(json.dumps({"fps": 30, "duration": round(total, 3), "scenes": scenes}, indent=2))
    print(f"{len(scenes)} scenes, {total:.1f} s")
    for s in scenes:
        print(f"  {s['start']:6.2f}  {s['duration']:4.1f}s  {s['id']}")


if __name__ == "__main__":
    main()
