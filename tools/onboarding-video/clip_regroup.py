"""Video 2 - "Nobody gets left behind." (onboarding_regroup, 8.0 s). Spec section 3, Video 2.

Plate: 05 (regroup called near the Nandi Hills hairpin), with 06 supplying the map under the
banner (same camera, banner not shown there). The regroup banner and the Scenic Stop pin are
lifted from 05 as layers; the rider markers are re-drawn from GoogleMapView.renderRiderIcon.

Deviation: the spec's "pins fan back out to their 0.0 s positions" (7.0-7.5) would make every
rider ride backwards at 300+ px/s. Instead the banner slides away and the 1.0 s loop dissolve
carries the pack back to the start, so no rider ever moves in a way the app couldn't show.
"""
from __future__ import annotations

import math
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

from common import *
from clip_tracking import google_logo

DUR = 8.0
K_MAP = 3.6      # 05 draws rider circles at ~90 px (2.8); enlarged ~30%
ARROW_SCALE = 1.65   # same as screen 1
MPP = 0.7
VIEW_BOTTOM = 1530   # where the copy's gradient starts to cover the scene (iPhone 17)

# Behind (bottom-left, the road already ridden) -> hairpin -> ahead (lime, up-left).
CTRL = [(-30, 1424), (0, 1421), (50, 1411), (100, 1400), (150, 1387), (200, 1368), (250, 1347),
        (300, 1336), (350, 1314), (400, 1296), (450, 1281), (500, 1266), (535, 1254), (552, 1240),
        (540, 1222), (505, 1212), (484, 1195), (480, 1165), (468, 1140), (440, 1130), (400, 1128),
        (350, 1128), (322, 1118), (298, 1092), (272, 1062), (250, 1042), (234, 1015), (225, 985),
        (218, 962), (200, 948), (175, 940), (150, 925), (120, 906), (95, 896), (60, 889),
        (30, 886), (-30, 882)]

AHEAD = [(13.0, (202, 243, 0)), (19.0, (90, 108, 0))]
BEHIND = [(5.0, (88, 100, 32)), (6.5, (60, 68, 22))]


@lru_cache(maxsize=1)
def path():
    """Snap the hand-placed control points onto the drawn route (lime / olive pixels)."""
    a = np.asarray(Image.open(SHOTS / "05_regroup_banner_other_rider.png").convert("RGB")).astype(int)
    lime = (abs(a[..., 0] - 202) < 30) & (abs(a[..., 1] - 243) < 30) & (a[..., 2] < 40)
    olive = (abs(a[..., 0] - 88) < 14) & (abs(a[..., 1] - 100) < 14) & (abs(a[..., 2] - 32) < 14)
    out = []
    for i, (x, y) in enumerate(CTRL):
        mask = lime if i >= 15 else olive
        r = 26 if i >= 15 else 12
        x0, x1, y0, y1 = max(0, x - r), min(W, x + r), max(0, y - r), min(H, y + r)
        ys, xs = np.nonzero(mask[y0:y1, x0:x1])
        if 0 <= x < W and len(xs) > (60 if i >= 15 else 12) and not (13 <= i <= 18):
            out.append((float(np.mean(xs) + x0), float(np.mean(ys) + y0)))
        else:
            out.append((float(x), float(y)))
    return Path2D(out)


def s_stop():
    p = path()
    return float(p.s[np.argmin(np.hypot(p.xy[:, 0] - 552, p.xy[:, 1] - 1240))])


BASE = {"arjun": -140.0, "meera": -235.0, "ananya": -325.0, "kabir": -460.0}
FINAL = {"arjun": -40.0, "meera": -130.0, "ananya": -220.0, "kabir": -310.0}
# Kabir trails far back and is already riding harder to close the gap.
V0 = {"arjun": 25.0, "meera": 25.0, "ananya": 25.0, "kabir": 45.0}
T_CALL, T_STOP = 2.2, 5.6


def offset(key, t):
    """Position relative to the stop. Cruise at V0, then a monotone Hermite ease into the cluster."""
    if t <= T_CALL:
        return BASE[key] + V0[key] * t
    p0 = BASE[key] + V0[key] * T_CALL
    p1 = FINAL[key]
    T = T_STOP - T_CALL
    u = clamp01((t - T_CALL) / T)
    m0 = V0[key] * T
    h00, h10, h01 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2
    return h00 * p0 + h10 * m0 + h01 * p1


@lru_cache(maxsize=1)
def plate():
    """Clean, full-height map: 05's map with its UI removed, inpainted where buttons and the old
    route were, mirrored above (rows < 620 hold 05's nav banner + chip strip) and faded to plain
    map below (rows > 2265 hold its stats bar)."""
    import cv2
    a5 = np.asarray(Image.open(SHOTS / "05_regroup_banner_other_rider.png").convert("RGB")).copy()
    a6 = np.asarray(Image.open(SHOTS / "06_regroup_pin_riders_gathering.png").convert("RGB"))
    a5[620:830] = a6[620:830]                      # clean map under the regroup banner

    # The lime buttons glow onto the map: that glow adds red+green but never blue, so the blue
    # channel is the true map value there. (Roads are excluded: they are green-dominant.)
    r, g, b = (a5[..., i].astype(int) for i in range(3))
    glow = (r - b > 3) & (g - b > 3) & (abs(r - g) < 40)
    glow[:1850] = False
    glow[2265:] = False
    a5[glow] = np.stack([b, b, b], -1)[glow].astype(np.uint8)

    mask = np.zeros((H, W), np.uint8)
    dist, _ = path().field((0, 0, W, H))
    mask[dist < 36] = 255                          # the old route (redrawn later)
    for x0, y0, x1, y1 in [(375, 1120, 705, 1395), (528, 1028, 680, 1250),
                           (320, 1975, 890, 2250), (0, 2180, 345, 2265)]:
        mask[y0:y1, x0:x1] = 255                   # pins, labels, RESUME / MARK AS ARRIVED, logo
    mask[:620] = 0
    mask[2265:] = 0
    mask = cv2.dilate(mask, np.ones((9, 9), np.uint8))
    a5 = cv2.inpaint(a5, mask, 6, cv2.INPAINT_TELEA)

    out = np.empty_like(a5)
    out[620:2265] = a5[620:2265]
    # above: reflect back and forth through the clean rows 620..1020 (never reaching the inpainted pin area)
    d = 620 - np.arange(620)
    m = d % 800
    m = np.where(m > 400, 800 - m, m)
    out[:620] = a5[620 + m]
    # below: plain map, with the last ~200 rows fading into it
    out[2265:] = MAP_BG[:3]
    f = np.clip((2265 - np.arange(2065, 2265)) / 200.0, 0, 1)[:, None, None]
    out[2065:2265] = (out[2065:2265] * f + np.array(MAP_BG[:3]) * (1 - f)).astype(np.uint8)
    return Image.fromarray(np.dstack([out, np.full(out.shape[:2], 255, np.uint8)]))


@lru_cache(maxsize=1)
def field():
    return path().field((0, 0, W, H))


@lru_cache(maxsize=1)
def banner():
    box = (58, 638, 1148, 813)
    a5 = np.asarray(Image.open(SHOTS / "05_regroup_banner_other_rider.png").convert("RGB").crop(box)).astype(np.float32)
    a6 = np.asarray(Image.open(SHOTS / "06_regroup_pin_riders_gathering.png").convert("RGB").crop(box)).astype(np.float32)
    # The card is translucent (~90% of the map shows through, measured against 06's clean map),
    # so subtract the hill roads it was photographed over; it now sits over plain map.
    a5 -= 0.9 * np.clip(a6 - MAP_BG[0], 0, None)
    src = Image.fromarray(np.clip(a5, 0, 255).astype(np.uint8)).convert("RGBA")
    m = Image.new("L", (src.width * 4, src.height * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((2, 2, m.width - 3, m.height - 3), radius=40 * 4, fill=255)
    src.putalpha(m.resize(src.size, Image.LANCZOS))
    spr, pad = shadow(src, 10, 0.45, dy=4)
    return spr, pad


@lru_cache(maxsize=1)
def stop_pin():
    """Scenic Stop RegroupPin: circle + tail cut from 05, label re-set in the app's style.
    Returns (sprite, tip_x, tip_y) where tip = the stop's coordinate (bottom of the tail)."""
    src = Image.open(SHOTS / "05_regroup_banner_other_rider.png").convert("RGBA").crop((530, 1032, 675, 1186))
    cx, cy, r = 602 - 530, 1105 - 1032, 65
    m = Image.new("L", (src.width * 4, src.height * 4), 0)
    md = ImageDraw.Draw(m)
    md.ellipse(((cx - r) * 4, (cy - r) * 4, (cx + r) * 4, (cy + r) * 4), fill=255)
    md.polygon([((cx - 14) * 4, (cy + r - 6) * 4), ((cx + 14) * 4, (cy + r - 6) * 4), (cx * 4, (1182 - 1032) * 4)], fill=255)
    src.putalpha(m.resize(src.size, Image.LANCZOS))
    k = 3.1
    f = mono(7 * k * SS, "black")
    label = "SCENIC STOP"
    tw = text_width(f, label, 0.5 * k * SS) / SS
    lw, lh = tw + 12 * k, 7 * k + 4 * k + 4
    w = max(src.width, lw) + 4
    h = src.height + 2 * k + lh
    img, d = ss_canvas(w, h)
    img.alpha_composite(src.resize((src.width * SS, src.height * SS), Image.LANCZOS), (int((w - src.width) / 2 * SS), 0))
    lx, ly = (w - lw) / 2, src.height + 2 * k
    d.rounded_rectangle((lx * SS, ly * SS, (lx + lw) * SS, (ly + lh) * SS), radius=lh / 2 * SS, fill=with_alpha(SURF_HIGH, 235))
    draw_text(d, (w / 2 * SS, (ly + lh / 2) * SS - cap_middle(f)), label, f, ON_SURFACE, tracking=0.5 * k * SS, anchor="ms")
    spr = ss_finish(img, w, h)
    spr, pad = shadow(spr, 4, 0.35, dy=2)
    return spr, pad + w / 2, pad + src.height - 4


_markers = {}


def marker(key, text):
    if (key, text) not in _markers:
        _markers[(key, text)] = rider_marker(key, K_MAP, text)
    return _markers[(key, text)]


def frame(t: float) -> Image.Image:
    p = path()
    S0 = s_stop()
    dist, arc = field()
    sA = S0 + offset("ananya", t)
    img = plate().copy()
    img.alpha_composite(route_layer(dist, arc, sA, AHEAD, BEHIND))

    # Scenic Stop pin: 1.4-2.2 scale 0.8->1.0 + fade, anchored at its tail
    sp, tipx, tipy = stop_pin()
    stop_xy = (602.0, 1182.0)
    a = smoothstep(1.4, 2.1, t)
    sc = 0.8 + 0.2 * ease_in_out_cubic((t - 1.4) / 0.8)

    # one soft ring pulse, 1 Hz, sky blue (RegroupPin SCENIC accent)
    def pulse(layer):
        u = (t - 1.9) / 1.0
        if 0 < u < 1:
            r = 67 + 70 * ease_in_out_cubic(u)
            al = 0.45 * (1 - u)
            ring, rd = ss_canvas(2 * r + 8, 2 * r + 8)
            c = ring.width / 2
            rd.ellipse((c - r * SS, c - r * SS, c + r * SS, c + r * SS), outline=(3, 155, 229, int(255 * al)), width=4 * SS)
            ring = ss_finish(ring, 2 * r + 8, 2 * r + 8)
            paste_center(layer, ring, 602, 1105)

    # riders: trailing first
    for key in ("kabir", "meera", "arjun"):
        s = S0 + offset(key, t)
        x, y = p.at(s)
        m = abs(s - sA) * MPP
        spr, ax, ay = marker(key, fmt_marker_distance(m))
        paste(img, spr, x - ax, y - ay)
    ax_, ay_ = p.at(sA)
    x0, y0 = p.at(sA - 12)
    x1, y1 = p.at(sA + 12)
    paste_center(img, arrow_sprite(math.degrees(math.atan2(x1 - x0, -(y1 - y0))), ARROW_SCALE), ax_, ay_)

    if a > 0:
        pulse(img)
        spr = sp if sc >= 0.999 else sp.resize((max(1, int(sp.width * sc)), max(1, int(sp.height * sc))), Image.LANCZOS)
        paste(img, spr, stop_xy[0] - tipx * sc, stop_xy[1] - tipy * sc, opacity=a)

    logo = google_logo()
    img.alpha_composite(logo, (W - 28 - logo.width, VIEW_BOTTOM - 110 - logo.height))

    # regroup banner: springs down from above into ~14% at 1.4 s, slides back up 7.0-7.5 s
    bspr, bpad = banner()
    target = int(H * 0.14) - bpad
    start = -bspr.height
    down = spring(t, 1.4, duration=0.6, damping=0.9)
    up = ease_in_out_cubic((t - 7.0) / 0.5)
    y = start + (target - start) * down
    y = y + (start - y) * up
    if down > 0 and up < 1:
        paste(img, bspr, (W - bspr.width) / 2, y)

    return img.convert("RGB")


if __name__ == "__main__":
    import sys
    from pathlib import Path
    out = Path(sys.argv[1])
    for tt in [float(x) for x in sys.argv[2:]]:
        frame(tt).save(out / f"regroup_{tt:.1f}.png")
