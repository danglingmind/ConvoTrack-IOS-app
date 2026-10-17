"""Render the three onboarding clips + posters straight into the app.

    tools/onboarding-video/.venv/bin/python tools/onboarding-video/make.py [tracking regroup invite]

Outputs
  convotrack/Onboarding/Media/onboarding_<name>.mp4                  (HEVC, 1080x2340, no audio)
  convotrack/Assets.xcassets/onboarding_<name>_poster.imageset/*.heic
  tools/onboarding-video/out/                                         (previews + QA report)

Portraits: drop arjun / meera / ananya / kabir (.png/.jpg/.heic, square-ish) into
docs/onboarding-screenshots/portraits/ and re-run; until then riders use the app's own
letter avatars.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from common import ROOT, OUT_W, OUT_H, render_clip, save_poster_heic  # noqa: E402
import clip_invite  # noqa: E402
import clip_regroup  # noqa: E402
import clip_tracking  # noqa: E402

MEDIA = ROOT / "convotrack" / "Onboarding" / "Media"
ASSETS = ROOT / "convotrack" / "Assets.xcassets"
OUT = Path(__file__).parent / "out"

CLIPS = {
    # name: (module, duration, poster time, loop dissolve, preview times)
    # Poster at 0.9 s: all four riders on the open map, just before Kabir starts dropping back.
    "tracking": (clip_tracking, 9.0, 0.9, 0.5, (0.0, 0.9, 3.5, 4.8, 6.5, 8.2, 8.75)),
    "regroup": (clip_regroup, 8.0, 6.2, 1.0, (0.0, 1.8, 3.8, 6.2, 7.3, 7.6)),
    "invite": (clip_invite, 8.0, 6.5, 0.5, (0.5, 1.4, 1.8, 2.6, 3.5, 4.6, 6.5, 7.75)),
}


def write_imageset(name: str, poster: Image.Image):
    d = ASSETS / f"onboarding_{name}_poster.imageset"
    d.mkdir(parents=True, exist_ok=True)
    fn = f"onboarding_{name}_poster.heic"
    save_poster_heic(poster, d / fn)
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": fn, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")


def main(names):
    MEDIA.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names:
        mod, dur, pt, diss, prev = CLIPS[name]
        print(f"rendering {name} ({dur}s)...", flush=True)
        poster, previews = render_clip(f"onboarding_{name}", dur, mod.frame, pt, MEDIA,
                                       dissolve=diss, preview_times=prev)
        write_imageset(name, poster)
        poster.save(OUT / f"{name}_poster.png")
        for t, img in previews.items():
            img.save(OUT / f"{name}_{t:.2f}.png")
        size = (MEDIA / f"onboarding_{name}.mp4").stat().st_size
        print(f"  -> {size / 1e6:.2f} MB", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] or list(CLIPS))
