"""Video 1 - "Every rider. One map." (onboarding_tracking, 9.0 s). Spec section 3, Video 1.

Full-screen: the map and route run edge to edge and nothing is darkened in the clip; the app's
own gradient (sized to the copy) keeps the text readable. Kabir drops back into the area behind
the text, which is exactly the "even the ones you can't see" beat.

Plate: 01c (the long winding climb), with the route, pins, banner, chip strip and stats bar
removed and the route re-drawn as a vector along a trace of the real one.

Deviation from the shot table, on purpose: the camera follows "you" (Ananya) the way live
navigation does, instead of holding still. With a fixed camera every rider moves *up* the screen,
so the trailing rider could never slip *under* the 55% line without riding backwards. Following
the rider keeps one primary motion (the map) and lets Kabir drop out of view honestly by
easing off, then catch back up. 9 s (not 7) so his 230 px drop and recovery stay <= ~75 px/s (25 pt/s)
without him ever riding backwards.
"""
from __future__ import annotations

import math
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

from common import *

DUR = 9.0
K_MAP = 3.6                  # px per pt for markers (01c draws them at ~2.2; enlarged ~65% to read at onboarding size)
ARROW_SCALE = 1.65           # "you" arrow, enlarged to match
EDGE_K = 3.6                 # edge chip drawn at the same enlargement (34 pt avatar, 14 pt distance)
MPP = 0.40                   # metres per px along the route at this zoom (01c: 290 m ~ 720 px)
ANCHOR = (603.0, 1230.0)     # where the camera holds "you" on screen (47%)
VIEW_BOTTOM = 1530           # where the copy's gradient starts to cover the map (~58%, iPhone 17)

# Trace of the 01c route (world = screenshot coordinates), top (ahead) -> bottom (behind).
# Extended past both ends of the screenshot (gentle curves, plain map) so the full-height,
# scrolling frame never runs out of road.
TRACE = [(600, -420), (586, -300), (580, -150), (594, 0), (611, 120), (619, 230), (600, 340),
         (585, 430), (578, 450), (565, 500), (550, 550), (535, 600), (515, 650), (497, 700),
         (478, 750), (466, 785), (456, 820), (452, 860), (455, 900), (465, 950), (485, 1000),
         (500, 1032), (504, 1062), (492, 1100), (475, 1132), (461, 1165), (463, 1205),
         (482, 1240), (500, 1268), (522, 1300), (558, 1348), (586, 1398), (599, 1450),
         (601, 1500), (602, 1560), (603, 1620), (606, 1665), (609, 1705), (614, 1750),
         (620, 1800), (626, 1850), (628, 1900), (627, 1950), (628, 2000), (630, 2050),
         (628, 2100), (622, 2160), (618, 2230), (608, 2350), (591, 2480), (586, 2600),
         (600, 2720), (624, 2850), (640, 2980), (644, 3150)]

# 01c route look: ahead = lime core + olive edge; behind "you" = grey casing + green line.
AHEAD = [(8.5, (202, 243, 0)), (12.5, (90, 108, 0))]
BEHIND = [(3.5, (96, 170, 43)), (5.0, (40, 52, 60)), (22.0, (44, 44, 44))]

# Path is parameterised top->bottom; riding forward = decreasing s.
PATH = Path2D(TRACE)
S_A0 = float(np.argmin(np.abs(PATH.xy[:, 1] - 1620)))   # Ananya starts where 01c's arrow is
GAP = {"arjun": -600.0, "meera": -290.0, "ananya": 0.0, "kabir": 245.0}
WY0, WY1 = -460, 3200          # world canvas rows (screenshot rows 0..2621 sit inside)


def s_ananya(t):
    # 0.6 s settle, then ~75 px/s (25 pt/s) with 0.6 s ramps, stopped by 8.45 s
    return S_A0 - 544.0 * trapezoid(t, 0.6, 8.45, 0.6)


def kabir_lag(t):
    # eases off from 1.2 s to a stop at most (lag rate <= the group's speed, never backwards),
    # sits behind the copy, then rides harder to close the gap by 8.4 s
    return 230.0 * (trapezoid(t, 1.0, 4.6, 0.5) - trapezoid(t, 4.9, 8.45, 0.5))


def rider_s(key, t):
    s = s_ananya(t) + GAP[key]
    if key == "kabir":
        s += kabir_lag(t)
    return s


@lru_cache(maxsize=1)
def plate():
    src = Image.open(SHOTS / "01c_nav_all_four_visible.png").convert("RGBA")
    a = np.asarray(src).copy()
    a[:620] = MAP_BG
    a[2265:] = MAP_BG
    for x0, y0, x1, y1 in [(375, 815, 540, 990), (415, 1160, 585, 1345), (535, 1560, 670, 1695),
                           (490, 2045, 690, 2265), (0, 2180, 345, 2265)]:
        a[y0:y1, x0:x1] = MAP_BG
    world = np.empty((WY1 - WY0, W, 4), np.uint8)
    world[:] = MAP_BG
    world[-WY0:-WY0 + H] = a
    dist, _ = arcfield()
    world[dist < 40] = MAP_BG
    return Image.fromarray(world), dist


@lru_cache(maxsize=1)
def arcfield():
    return PATH.field((0, WY0, W, WY1))


@lru_cache(maxsize=1)
def google_logo():
    src = Image.open(SHOTS / "01c_nav_all_four_visible.png").convert("RGB").crop((12, 2186, 335, 2260))
    a = np.asarray(src).astype(np.float32)
    lum = a.max(axis=2)
    alpha = np.clip((lum - 19) / (236 - 19) * 1.15, 0, 1)
    rgb = np.where(alpha[..., None] > 0.02, np.clip((a - 19 * (1 - alpha[..., None])) / np.maximum(alpha[..., None], 1e-3), 0, 255), 0)
    img = Image.fromarray(np.dstack([rgb, alpha * 255]).astype(np.uint8))
    return img.crop(img.getbbox())


# ---------------------------------------------------------------- overlays (screen space, 3 px/pt)

def leaderboard_card(key, highlighted, is_me):
    first, last = RIDERS[key].split()
    f_first, f_last, f_you = pro(33 * SS, "bold"), pro(30 * SS, "regular"), mono(18 * SS, "black")
    w_text = max(f_first.getlength(first) / SS + ((4 * 3 + f_you.getlength("YOU") / SS + 6 * 3) if is_me else 0),
                 f_last.getlength(last) / SS)
    av = 78
    w = 30 + av + 21 + w_text + 30
    h = 126
    img, d = ss_canvas(w, h)
    S = SS
    bg = with_alpha(LIME, 31) if highlighted else with_alpha(SURF_HIGH, 224)
    d.rounded_rectangle((0, 0, w * S - 1, h * S - 1), radius=30 * S, fill=bg,
                        outline=LIME if highlighted else with_alpha(OUTLINE_VARIANT, 77),
                        width=int((4.5 if highlighted else 3) * S))
    avatar = circle_avatar(key, av * S, SURF_VARIANT, ("pro", 33 * S, "bold"),
                           LIME if highlighted else ON_SURFACE)
    img.alpha_composite(avatar, (30 * S, int((h - av) / 2 * S)))
    d.ellipse((30 * S, (h - av) / 2 * S, (30 + av) * S, ((h + av) / 2) * S),
              outline=LIME if highlighted else with_alpha(OUTLINE_VARIANT, 102),
              width=int((6 if highlighted else 3) * S))
    tx = (30 + av + 21) * S
    base1 = (h / 2 - 3) * S
    d.text((tx, base1), first, font=f_first, fill=ON_SURFACE, anchor="ls")
    if is_me:
        bx = tx + f_first.getlength(first) + 12 * S
        bw = f_you.getlength("YOU") + 18 * S
        bh = 30 * S
        by = base1 + cap_middle(f_first) - bh / 2
        d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=bh / 2, fill=LIME)
        d.text((bx + bw / 2, by + bh / 2 - cap_middle(f_you)), "YOU", font=f_you, fill=ON_LIME, anchor="ms")
    d.text((tx, base1 + 36 * S), last, font=f_last, fill=ON_SURFACE_VARIANT, anchor="ls")
    return ss_finish(img, w, h)


@lru_cache(maxsize=1)
def count_pill():
    src = Image.open(SHOTS / "01c_nav_all_four_visible.png").convert("RGBA").crop((1014, 484, 1148, 576))
    m = Image.new("L", (src.width * 4, src.height * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, m.width - 1, m.height - 1), radius=m.height / 2, fill=255)
    src.putalpha(m.resize(src.size, Image.LANCZOS))
    return src


@lru_cache(maxsize=1)
def chip_strip():
    cards = [leaderboard_card("arjun", True, False), leaderboard_card("meera", False, False),
             leaderboard_card("ananya", True, True)]
    strip = Image.new("RGBA", (W, 140), (0, 0, 0, 0))
    x = 58
    for c in cards:
        strip.alpha_composite(c, (int(x), 7))
        x += c.width + 30
    pill = count_pill()
    strip.alpha_composite(pill, (W - 58 - pill.width, 7 + (126 - pill.height) // 2))
    return strip


def edge_chip(key, meters):
    size = 34 * EDGE_K
    fpx = 14 * EDGE_K
    f = mono(fpx * SS, "medium")
    txt = f"{int(round(meters / 10.0)) * 10}m"
    tw = f.getlength(txt) / SS
    w = max(size, tw) + 20
    h = size + 3 * EDGE_K + fpx * 1.2
    img, d = ss_canvas(w, h)
    S = SS
    cx = w / 2
    av = circle_avatar(key, size * S, SURF_VARIANT, ("pro", size * 0.4 * S, "bold"), ON_SURFACE)
    avl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    avl.alpha_composite(av, (int((cx - size / 2) * S), 0))
    ImageDraw.Draw(avl).ellipse(((cx - size / 2) * S, 0, (cx + size / 2) * S, size * S), outline=TERTIARY, width=int(2 * EDGE_K * S))
    avs = ss_finish(avl, w, h)
    avs, pad = shadow(avs, 4 * 3 / 2, 0.55, dy=3)
    # distance text with the two shadows from EdgeChip (no plate)
    tl = Image.new("RGBA", avs.size, (0, 0, 0, 0))
    td = ImageDraw.Draw(tl)
    ty = pad + size + 3 * EDGE_K + fpx * 0.86
    td.text((avs.width / 2, ty), txt, font=mono(fpx, "medium"), fill=(0, 0, 0, 255), anchor="ms")
    from PIL import ImageFilter
    sh = tl.filter(ImageFilter.GaussianBlur(4.5))
    sh2 = tl.filter(ImageFilter.GaussianBlur(1.5))
    out = Image.new("RGBA", avs.size, (0, 0, 0, 0))
    for layer, op in ((sh, 0.85), (sh2, 0.6)):
        a = layer.getchannel("A").point(lambda v: int(min(255, v * op * 1.6)))
        layer = layer.copy(); layer.putalpha(a)
        out.alpha_composite(layer)
    out.alpha_composite(avs)
    ImageDraw.Draw(out).text((avs.width / 2, ty), txt, font=mono(fpx, "medium"), fill=ON_SURFACE, anchor="ms")
    return out, pad + size / 2


# ---------------------------------------------------------------- frame

_marker_cache = {}


def marker(key, text):
    k = (key, text)
    if k not in _marker_cache:
        _marker_cache[k] = rider_marker(key, K_MAP, text)
    return _marker_cache[k]


def frame(t: float) -> Image.Image:
    base, _ = plate()
    dist, arc = arcfield()
    sA = s_ananya(t)
    world = base.copy()
    world.alpha_composite(_route(dist, arc, sA))
    ax, ay = PATH.at(sA)
    # riders (draw trailing first so the leader sits on top)
    for key in ("kabir", "meera", "arjun"):
        s = rider_s(key, t)
        x, y = PATH.at(s)
        m = abs(s - sA) * MPP
        spr, axo, ayo = marker(key, fmt_marker_distance(m))
        paste(world, spr, x - axo, y - WY0 - ayo)
    arrow = arrow_sprite(_heading(sA), ARROW_SCALE)
    paste_center(world, arrow, ax, ay - WY0)

    # camera: hold "you" at ANCHOR (world image row r is world y r + WY0)
    cx, cy = ANCHOR[0] - ax, ANCHOR[1] - ay
    screen = Image.new("RGBA", (W, H), MAP_BG)
    shifted = world.transform((W, H), Image.AFFINE, (1, 0, -cx, 0, 1, -(cy + WY0)), resample=Image.BILINEAR,
                              fillcolor=MAP_BG)
    screen.alpha_composite(shifted)

    # Google Maps logo: bottom-left of the map that stays clear of the copy's gradient
    logo = google_logo()
    screen.alpha_composite(logo, (28, VIEW_BOTTOM - 70 - logo.height))

    # (No rider chip strip: on a background clip it read as tappable UI next to Skip.
    # The four pins + Kabir's edge chip carry "every rider".)

    # Kabir drops in behind the copy -> edge chip at the bottom of the open map, above him
    sK = rider_s("kabir", t)
    kx, ky = PATH.at(sK)
    ky_screen = ky + cy
    vis = smoothstep(VIEW_BOTTOM + 70, VIEW_BOTTOM + 130, ky_screen)
    if vis > 0.01:
        chip, cyo = edge_chip("kabir", abs(sK - sA) * MPP)
        paste(screen, chip, kx + cx - chip.width / 2, VIEW_BOTTOM - 150 - cyo, opacity=vis)

    # Full-screen: nothing darkened here. Readability comes from the app's copy gradient.
    return screen.convert("RGB")


def _route(dist, arc, sA):
    # arc grows downward (behind); traveled = arc > sA
    return route_layer(dist, -arc, -sA, AHEAD, BEHIND)


def _heading(s):
    # riding forward = towards smaller s
    x0, y0 = PATH.at(s + 14)
    x1, y1 = PATH.at(s - 14)
    return math.degrees(math.atan2(x1 - x0, -(y1 - y0)))


if __name__ == "__main__":
    import sys
    from pathlib import Path
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("out")
    for tt in [float(x) for x in sys.argv[2:]] or [0.0, 3.0]:
        frame(tt).save(out / f"tracking_{tt:.1f}.png")
