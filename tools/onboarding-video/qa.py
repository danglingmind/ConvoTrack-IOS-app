"""Section 5 checklist, measured on the *encoded* clips (decoded back through ffmpeg).

    tools/onboarding-video/.venv/bin/python tools/onboarding-video/qa.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "convotrack" / "Onboarding" / "Media"
W, H = 1080, 2340
NAMES = ["tracking", "regroup", "invite"]

# OnboardingFlowView scrim: clear to 38%, surfaceDim @ 0.88 at 60%, 0.97 at 78%, 1.0 at 100%
STOPS = [(0.0, 0.0), (0.38, 0.0), (0.60, 0.88), (0.78, 0.97), (1.0, 1.0)]
SURFACE_DIM = np.array([0x13, 0x13, 0x13], np.float32)
BODY = np.array([0xC5, 0xC9, 0xAC], np.float32)        # onSurfaceVariant (body copy)


def frames(path):
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         stdout=subprocess.PIPE)
    n = W * H * 3
    while True:
        b = p.stdout.read(n)
        if len(b) < n:
            break
        yield np.frombuffer(b, np.uint8).reshape(H, W, 3)
    p.wait()


def srgb_lin(c):
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def rel_lum(rgb):
    l = srgb_lin(rgb.astype(np.float32))
    return l[..., 0] * 0.2126 + l[..., 1] * 0.7152 + l[..., 2] * 0.0722


def contrast(a, b):
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def scrim_alpha(y_frac):
    xs, ys = zip(*STOPS)
    return np.interp(y_frac, xs, ys)


def check(name):
    path = MEDIA / f"onboarding_{name}.mp4"
    y = np.arange(H) / H
    a = scrim_alpha(y)[:, None, None].astype(np.float32)
    band = slice(int(H * 0.55), H)
    lime_px, worst_bg, prev_tiles, flashes = 0, 0.0, None, []
    first = last = None
    for i, f in enumerate(frames(path)):
        if first is None:
            first = f
        last = f
        lower = f[band].astype(np.int32)
        r, g, b = lower[..., 0], lower[..., 1], lower[..., 2]
        lime_px = max(lime_px, int(((g > 150) & (r > 110) & (b < 0.45 * g) & (g > r)).sum()))
        comp = f[band].astype(np.float32) * (1 - a[band]) + SURFACE_DIM * a[band]
        worst_bg = max(worst_bg, float(rel_lum(comp).max()))
        # flash test (WCAG 2.3.1 general flash): a "flash" is a pair of opposing changes of
        # >= 0.1 relative luminance (darker state < 0.8) over an area ~25% of a 10 deg field,
        # i.e. ~270x290 px tiles here. Fail = more than 3 flashes in any 1 s.
        L = rel_lum(f[::6, ::6])
        th, tw = 49, 45
        tiles = L[: (L.shape[0] // th) * th, : (L.shape[1] // tw) * tw]
        tiles = tiles.reshape(tiles.shape[0] // th, th, tiles.shape[1] // tw, tw).mean((1, 3))
        if prev_tiles is not None:
            d = tiles - prev_tiles
            dark = np.minimum(tiles, prev_tiles)
            flashes.append(np.where((np.abs(d) >= 0.1) & (dark < 0.8), np.sign(d), 0))
        prev_tiles = tiles
    seam = float(np.abs(first.astype(int) - last.astype(int)).mean())
    size = path.stat().st_size
    cr = contrast(float(rel_lum(BODY[None, None])[0, 0]), worst_bg)
    # per tile: opposing transitions inside any 30-frame window
    worst = 0
    stack = np.stack(flashes) if flashes else np.zeros((1, 1, 1))
    for i in range(len(stack)):
        win = stack[i:i + 30]
        for idx in np.ndindex(win.shape[1:]):
            seq = [v for v in win[(slice(None),) + idx] if v != 0]
            runs = (1 + sum(1 for a_, b_ in zip(seq, seq[1:]) if a_ != b_)) if seq else 0
            worst = max(worst, runs // 2)   # a flash = one up + one down
    return {
        "size_MB": round(size / 1e6, 3),
        "lime_px_below_55pct (max/frame)": lime_px,
        "body_contrast_vs_brightest": round(cr, 1),
        "max_flashes_per_s": worst,
        "seam_mean_abs_diff": round(seam, 2),
    }


# Full-screen pages (no darkening in the clip): the app's copy gradient, as laid out on an
# iPhone 17 (874 pt tall) at the default text size, measured from simulator screenshots.
# (pt from top, opacity of surfaceDim)
# Copy gradient: peak 0.5, clear 100 pt above the copy (copy box starts ~562 pt).
COPY_SCRIM_PEAK = 0.5
# Pages whose headline wraps to two lines have a copy block ~49 pt taller (bottom-anchored), so the
# eyebrow/headline and the gradient start that much higher. Measured from simulator screenshots.
EXTRA_PT = {"tracking": 0, "regroup": 49, "invite": 49}


def scrim_points(extra):
    top = 462 - extra                     # gradient top; copy box starts 100 pt below it
    text = 157 + extra
    lead = 100
    stops = [(0, 0), (top, 0), (top + 50, 0.15), (top + lead, 0.5), (top + lead + 0.35 * text, 0.8),
             (top + lead + 0.7 * text, 0.95), (top + lead + text, 1.0), (874, 1.0)]
    return [(y, v * COPY_SCRIM_PEAK) for y, v in stops]
# Under it, the app's video treatment: teal tint at 55% + vignette (OnboardingFlowView).
VIDEO_TINT = np.array([0.03, 0.13, 0.16], np.float32) * 255
VIDEO_TINT_ALPHA = 0.55
VIGNETTE = (0.38, 140, 560, 0.55)      # centre y (fraction), start / end radius pt, max opacity
# text regions in pt, colour, required ratio (WCAG: 4.5 normal text, 3.0 large/bold >= 24 pt)
def copy_text(extra):
    return [("eyebrow", 581 - extra, 599 - extra, BODY, 4.5),
            ("headline", 612 - extra, 660, np.array([0xE5, 0xE2, 0xE1], np.float32), 3.0),
            ("body", 666, 722, BODY, 4.5)]


FULL_SCREEN = {"tracking", "regroup", "invite"}


def check_full(name):
    path = MEDIA / f"onboarding_{name}.mp4"
    extra = EXTRA_PT[name]
    COPY_TEXT = copy_text(extra)
    pt = np.arange(H) * 874.0 / H
    xs, ys = zip(*scrim_points(extra))
    a = np.interp(pt, xs, ys)[:, None, None].astype(np.float32)
    cy, r0v, r1v, vmax = VIGNETTE
    px = np.arange(W) * 402.0 / W
    rr = np.hypot(px[None, :] - 201, pt[:, None] - 874 * cy)
    vig = (np.clip((rr - r0v) / (r1v - r0v), 0, 1) * vmax)[..., None].astype(np.float32)
    worst = {k: 0.0 for k, *_ in COPY_TEXT}
    first = last = None
    prev_tiles, flashes = None, []
    for f in frames(path):
        first = f if first is None else first
        last = f
        comp = f.astype(np.float32) * (1 - VIDEO_TINT_ALPHA) + VIDEO_TINT * VIDEO_TINT_ALPHA
        comp = comp * (1 - vig) + SURFACE_DIM * vig
        comp = comp * (1 - a) + SURFACE_DIM * a
        L = rel_lum(comp[:, 72:1008])          # 24 pt side margins: where the copy actually is
        for k, y0, y1, *_ in COPY_TEXT:
            r0, r1 = int(y0 / 874 * H), int(y1 / 874 * H)
            worst[k] = max(worst[k], float(L[r0:r1].max()))
        Lt = rel_lum(f[::6, ::6])
        th, tw = 49, 45
        tiles = Lt[: (Lt.shape[0] // th) * th, : (Lt.shape[1] // tw) * tw]
        tiles = tiles.reshape(tiles.shape[0] // th, th, tiles.shape[1] // tw, tw).mean((1, 3))
        if prev_tiles is not None:
            d = tiles - prev_tiles
            flashes.append(np.where((np.abs(d) >= 0.1) & (np.minimum(tiles, prev_tiles) < 0.8), np.sign(d), 0))
        prev_tiles = tiles
    out = {"size_MB": round(path.stat().st_size / 1e6, 3)}
    ok = out["size_MB"] <= 1.5
    for k, y0, y1, col, need in COPY_TEXT:
        cr = contrast(float(rel_lum(col[None, None])[0, 0]), worst[k])
        out[f"{k}_contrast(min {need})"] = round(cr, 1)
        ok &= cr >= need
    stack = np.stack(flashes)
    w = 0
    for i in range(len(stack)):
        win = stack[i:i + 30]
        for idx in np.ndindex(win.shape[1:]):
            seq = [v for v in win[(slice(None),) + idx] if v != 0]
            runs = (1 + sum(1 for a_, b_ in zip(seq, seq[1:]) if a_ != b_)) if seq else 0
            w = max(w, runs // 2)
    out["max_flashes_per_s"] = w
    out["seam_mean_abs_diff"] = round(float(np.abs(first.astype(int) - last.astype(int)).mean()), 2)
    ok &= w <= 3 and out["seam_mean_abs_diff"] < 1.0
    return out, ok


if __name__ == "__main__":
    ok = True
    for n in sys.argv[1:] or NAMES:
        if n in FULL_SCREEN:
            r, good = check_full(n)
            print(n, "(full-screen)", r)
            ok &= good
            continue
        r = check(n)
        print(n, r)
        ok &= r["size_MB"] <= 1.5 and r["lime_px_below_55pct (max/frame)"] == 0 and r["body_contrast_vs_brightest"] >= 4.5 \
            and r["max_flashes_per_s"] <= 3 and r["seam_mean_abs_diff"] < 1.0
    print("PASS" if ok else "CHECK FAILURES ABOVE")
