"""Shared drawing + encoding helpers for the onboarding background clips.

Spec: docs/onboarding-video-script.md. Every component here re-draws a real ConvoTrack view
from its SwiftUI / GoogleMapView source (sizes in pt, colours from ConvoTrackTheme.swift), so
the clips show UI the app actually renders. Working canvas is the 1206x2622 screenshot space
(3 px per pt); `k` arguments are px-per-pt for map markers drawn at map zoom.
"""
from __future__ import annotations

import math
import os
import subprocess
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SHOTS = ROOT / "docs" / "onboarding-screenshots"
PORTRAITS = SHOTS / "portraits"

W, H = 1206, 2622
OUT_W, OUT_H = 1080, 2340
FPS = 30
ZONE_TOP = int(H * 0.12)      # 315
ZONE_BOTTOM = int(H * 0.55)   # 1442
SS = 3                        # supersampling for vector sprites

# ConvoTrackTheme.swift
def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

LIME = hexc("caf300")
ON_LIME = hexc("171e00")
ON_PRIMARY_CONTAINER = hexc("596c00")
TERTIARY = hexc("62ff96")
SURFACE_DIM = hexc("131313")
SURF_HIGH = hexc("2a2a2a")
SURF_HIGHEST = hexc("353535")
SURF_VARIANT = hexc("353535")
ON_SURFACE = hexc("e5e2e1")
ON_SURFACE_VARIANT = hexc("c5c9ac")
SECONDARY_FIXED = hexc("e5e2e1")
OUTLINE = hexc("8f9378")
OUTLINE_VARIANT = hexc("444932")
MAP_BG = (19, 19, 19, 255)    # Google dark map style, sampled from the screenshots

RIDERS = {
    "arjun": "Arjun Rao",
    "meera": "Meera Iyer",
    "ananya": "Ananya Das",
    "kabir": "Kabir Shah",
}


def with_alpha(c, a):
    return (c[0], c[1], c[2], int(round(a * 255)) if isinstance(a, float) else a)


# ---------------------------------------------------------------- fonts

SFPRO = "/System/Library/Fonts/SFNS.ttf"
SFMONO = "/System/Library/Fonts/SFNSMono.ttf"
PRO_WEIGHTS = {"regular": 400, "medium": 510, "semibold": 590, "bold": 700, "heavy": 860, "black": 1000}
MONO_WEIGHTS = {"regular": 400, "medium": 500, "semibold": 600, "bold": 700, "heavy": 800, "black": 900}


@lru_cache(maxsize=None)
def pro(px: float, weight="regular"):
    f = ImageFont.truetype(SFPRO, max(1, int(round(px))))
    opsz = min(96, max(17, px / 3))  # optical size follows the pt size, not the px size
    f.set_variation_by_axes([100, opsz, 400, PRO_WEIGHTS[weight]])
    return f


@lru_cache(maxsize=None)
def mono(px: float, weight="regular"):
    f = ImageFont.truetype(SFMONO, max(1, int(round(px))))
    w = MONO_WEIGHTS[weight]
    f.set_variation_by_axes([w, w])
    return f


def text_width(font, s, tracking=0.0):
    if not tracking:
        return font.getlength(s)
    return sum(font.getlength(ch) for ch in s) + tracking * (len(s) - 1)


def draw_text(d: ImageDraw.ImageDraw, xy, s, font, fill, tracking=0.0, anchor="ls"):
    """Text with SwiftUI-style tracking. anchor: l/m/r + s(baseline)/m(middle)."""
    x, y = xy
    w = text_width(font, s, tracking)
    if anchor[0] == "m":
        x -= w / 2
    elif anchor[0] == "r":
        x -= w
    v = anchor[1]
    if not tracking:
        d.text((x, y), s, font=font, fill=fill, anchor="l" + v)
        return w
    for ch in s:
        d.text((x, y), ch, font=font, fill=fill, anchor="l" + v)
        x += font.getlength(ch) + tracking
    return w


def cap_middle(font):
    """Offset from baseline to the visual middle of capitals (for vertical centring)."""
    b = font.getbbox("H", anchor="ls")
    return (b[1] + b[3]) / 2


# ---------------------------------------------------------------- sprite helpers

def ss_canvas(w, h):
    img = Image.new("RGBA", (int(math.ceil(w * SS)), int(math.ceil(h * SS))), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def ss_finish(img, w, h):
    return img.resize((int(math.ceil(w)), int(math.ceil(h))), Image.LANCZOS)


def paste(dst: Image.Image, sprite: Image.Image, x: float, y: float, opacity=1.0):
    """Alpha-composite `sprite` with its top-left at sub-pixel (x, y)."""
    if opacity <= 0.001:
        return
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    if fx > 1e-3 or fy > 1e-3:
        sw, sh = sprite.size
        sprite = sprite.transform((sw + 1, sh + 1), Image.AFFINE, (1, 0, -fx, 0, 1, -fy), resample=Image.BILINEAR)
    if opacity < 0.999:
        a = sprite.getchannel("A").point(lambda v: int(v * opacity))
        sprite = sprite.copy()
        sprite.putalpha(a)
    dst.alpha_composite(sprite, (ix, iy)) if ix >= 0 and iy >= 0 else _composite_clipped(dst, sprite, ix, iy)


def _composite_clipped(dst, sprite, ix, iy):
    sx, sy = max(0, -ix), max(0, -iy)
    if sx >= sprite.width or sy >= sprite.height:
        return
    dst.alpha_composite(sprite.crop((sx, sy, sprite.width, sprite.height)), (max(0, ix), max(0, iy)))


def paste_center(dst, sprite, cx, cy, opacity=1.0):
    paste(dst, sprite, cx - sprite.width / 2, cy - sprite.height / 2, opacity)


def shadow(sprite: Image.Image, radius: float, opacity: float, dy: float = 0, pad: int = None):
    """Return sprite with a soft black drop shadow (sprite grows by `pad` on each side)."""
    pad = int(pad if pad is not None else radius * 2 + abs(dy) + 2)
    w, h = sprite.size
    out = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    a = sprite.getchannel("A").point(lambda v: int(v * opacity))
    sh = Image.new("RGBA", sprite.size, (0, 0, 0, 255))
    sh.putalpha(a)
    tmp = Image.new("RGBA", out.size, (0, 0, 0, 0))
    tmp.alpha_composite(sh, (pad, pad + int(round(dy))))
    tmp = tmp.filter(ImageFilter.GaussianBlur(radius))
    out.alpha_composite(tmp)
    out.alpha_composite(sprite, (pad, pad))
    return out, pad


# ---------------------------------------------------------------- portraits

@lru_cache(maxsize=None)
def portrait(key: str):
    """User-supplied portrait from docs/onboarding-screenshots/portraits/<key>.*, else None.

    When absent, every component falls back to the app's own letter avatar, which is exactly
    what ConvoTrack draws for a rider without a profile photo.
    """
    if not PORTRAITS.is_dir():
        return None
    for p in sorted(PORTRAITS.iterdir()):
        if p.stem.lower() == key and p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp", ".heic"):
            if p.suffix.lower() == ".heic":
                import pillow_heif
                pillow_heif.register_heif_opener()
            img = Image.open(p).convert("RGB")
            s = min(img.size)
            l, t = (img.width - s) // 2, (img.height - s) // 2
            return img.crop((l, t, l + s, t + s))
    return None


def circle_avatar(key: str, d_px: float, fallback_fill, letter_font, letter_fill):
    """Aspect-filled portrait (or letter fallback) clipped to a circle, `d_px` across."""
    img, dr = ss_canvas(d_px, d_px)
    D = img.width
    p = portrait(key)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, D - 1, D - 1), fill=255)
    if p is not None:
        face = p.resize((D, D), Image.LANCZOS).convert("RGBA")
        face.putalpha(mask)
        img.alpha_composite(face)
    else:
        dr.ellipse((0, 0, D - 1, D - 1), fill=fallback_fill)
        f = letter_font_scaled(letter_font)
        letter = RIDERS[key][0]
        dr.text((D / 2, D / 2 - cap_middle(f) + 0), letter, font=f, fill=letter_fill, anchor="ms")
    return ss_finish(img, d_px, d_px)


def letter_font_scaled(spec):
    """spec = (family, px, weight) at 1x -> font at SS scale."""
    fam, px, wt = spec
    return (pro if fam == "pro" else mono)(px * SS, wt)


# ---------------------------------------------------------------- map markers (GoogleMapView.renderRiderIcon)

def rider_marker(key: str, k: float, dist_text: str | None, opacity=1.0):
    """Returns (sprite, anchor_x, anchor_y): anchor is the circle centre (the coordinate)."""
    size = 32 * k
    name = RIDERS[key].split()[0].upper()
    name_f = mono(8 * k * SS, "black")
    dist_f = mono(9 * k * SS, "semibold")
    ns_w = name_f.getlength(name) / SS
    ds_w = dist_f.getlength(dist_text) / SS if dist_text else 0
    name_band = 20 * k
    dist_band = 16 * k if dist_text else 0
    cw = max(size + 8 * k, ns_w + 8 * k, ds_w + 8 * k)
    ch = name_band + size + dist_band
    img, d = ss_canvas(cw, ch)
    S = SS
    cx = cw / 2
    # avatar / letter fallback
    av = circle_avatar(key, size * S, (31, 31, 31, 255), ("pro", size * 0.32 * S, "bold"), (255, 255, 255, 255))
    img.alpha_composite(av, (int(round((cx - size / 2) * S)), int(round(name_band * S))))
    # lime ring, inset 1.25pt, width 1.25pt
    inset, lw = 1.25 * k, 1.25 * k
    r0 = ((cx - size / 2 + inset) * S, (name_band + inset) * S, (cx + size / 2 - inset) * S, (name_band + size - inset) * S)
    d.ellipse(r0, outline=LIME, width=max(1, int(round(lw * S))))
    # name label above
    asc_n = name_f.getbbox(name, anchor="ls")
    nh = (asc_n[3] - asc_n[1]) / S
    ny_mid = name_band / 2
    pad_x, pad_y = 4 * k, 2 * k
    d.rounded_rectangle(((cx - ns_w / 2 - pad_x) * S, (ny_mid - nh / 2 - pad_y - 1.5 * k) * S,
                         (cx + ns_w / 2 + pad_x) * S, (ny_mid + nh / 2 + pad_y + 1.5 * k) * S),
                        radius=6 * k * S, fill=(26, 26, 26, 191))
    d.text((cx * S, ny_mid * S - cap_middle(name_f)), name, font=name_f, fill=(255, 255, 255, 255), anchor="ms")
    if dist_text:
        b = dist_f.getbbox(dist_text, anchor="ls")
        dh = (b[3] - b[1]) / S
        dy_mid = name_band + size + dist_band / 2 + 1 * k
        d.rounded_rectangle(((cx - ds_w / 2 - pad_x) * S, (dy_mid - dh / 2 - pad_y - 1.5 * k) * S,
                             (cx + ds_w / 2 + pad_x) * S, (dy_mid + dh / 2 + pad_y + 1.5 * k) * S),
                            radius=6 * k * S, fill=(26, 26, 26, 191))
        d.text((cx * S, dy_mid * S - cap_middle(dist_f)), dist_text, font=dist_f, fill=LIME, anchor="ms")
    spr = ss_finish(img, cw, ch)
    spr, pad = shadow(spr, 3, 0.35, dy=1)
    return spr, pad + cw / 2, pad + name_band + size / 2


def fmt_marker_distance(m):
    return f"{int(round(m / 10.0)) * 10} m"


# ---------------------------------------------------------------- the "you" arrow, lifted from 01c

@lru_cache(maxsize=None)
def you_arrow():
    """Google nav chevron (lime fill, white outline) cut from 01c, pointing up. Centre = sprite centre."""
    src = Image.open(SHOTS / "01c_nav_all_four_visible.png").convert("RGB").crop((540, 1565, 666, 1680))
    a = np.asarray(src).astype(int)
    white = (a.min(axis=2) > 200)
    m = Image.fromarray((white * 255).astype(np.uint8))
    # flood the outside from a corner; whatever is not outside is the arrow (outline + fill)
    filled = m.copy()
    ImageDraw.floodfill(filled, (0, 0), 128)
    ImageDraw.floodfill(filled, (src.width - 1, 0), 128)
    ImageDraw.floodfill(filled, (0, src.height - 1), 128)
    ImageDraw.floodfill(filled, (src.width - 1, src.height - 1), 128)
    f = np.asarray(filled)
    alpha = np.where(f == 128, 0, 255).astype(np.uint8)
    alpha_img = Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(0.6))
    rgba = src.convert("RGBA")
    rgba.putalpha(alpha_img)
    bbox = alpha_img.point(lambda v: 255 if v > 40 else 0).getbbox()
    rgba = rgba.crop(bbox)
    spr, _ = shadow(rgba, 4, 0.45, dy=2)
    return spr


def arrow_sprite(heading_deg: float, scale=1.0):
    """heading: 0 = up, clockwise positive."""
    spr = you_arrow()
    if scale != 1.0:
        spr = spr.resize((int(spr.width * scale), int(spr.height * scale)), Image.LANCZOS)
    return spr.rotate(-heading_deg, resample=Image.BICUBIC, expand=True)


# ---------------------------------------------------------------- route geometry

class Path2D:
    """Catmull-Rom through control points, resampled at ~1 px arc length."""

    def __init__(self, pts):
        pts = np.asarray(pts, float)
        P = np.vstack([pts[0], pts, pts[-1]])
        out = []
        for i in range(1, len(P) - 2):
            p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            n = max(2, int(np.linalg.norm(p2 - p1)))
            t = np.linspace(0, 1, n, endpoint=False)[:, None]
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
        out.append(pts[-1:])
        dense = np.vstack(out)
        seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(seg)])
        self.length = s[-1]
        self.s = np.arange(0, self.length, 1.0)
        self.xy = np.stack([np.interp(self.s, s, dense[:, 0]), np.interp(self.s, s, dense[:, 1])], 1)

    def at(self, s):
        s = float(np.clip(s, 0, self.length - 1))
        return float(np.interp(s, self.s, self.xy[:, 0])), float(np.interp(s, self.s, self.xy[:, 1]))

    def heading(self, s, span=12):
        x0, y0 = self.at(s - span)
        x1, y1 = self.at(s + span)
        return math.degrees(math.atan2(x1 - x0, -(y1 - y0)))

    def field(self, box, reach=70):
        """Distance + arc-length of the nearest path point for every pixel in box=(x0,y0,x1,y1).
        Pixels farther than `reach` from the path get distance 1e4."""
        x0, y0, x1, y1 = box
        P, S = self.xy, self.s
        dist = np.full((y1 - y0, x1 - x0), 1e4)
        arc = np.zeros((y1 - y0, x1 - x0))
        xs = np.arange(x0, x1, dtype=float)
        for by in range(y0, y1, 64):
            ys = np.arange(by, min(by + 64, y1), dtype=float)
            sel = np.where((P[:, 1] > ys[0] - reach) & (P[:, 1] < ys[-1] + reach))[0]
            if not len(sel):
                continue
            px_min, px_max = P[sel, 0].min() - reach, P[sel, 0].max() + reach
            cols = np.where((xs >= px_min) & (xs <= px_max))[0]
            if not len(cols):
                continue
            gx = xs[cols][None, :, None]
            gy = ys[:, None, None]
            best = np.full((len(ys), len(cols)), 1e8)
            barg = np.zeros((len(ys), len(cols)), int)
            for i in range(0, len(sel), 48):
                idx = sel[i:i + 48]
                dd = (gx - P[idx, 0]) ** 2 + (gy - P[idx, 1]) ** 2
                j = dd.argmin(-1)
                m = np.take_along_axis(dd, j[..., None], -1)[..., 0]
                b = m < best
                best[b] = m[b]
                barg[b] = idx[j][b]
            r0 = by - y0
            dist[r0:r0 + len(ys), cols - 0 + (0)] = np.sqrt(best)
            arc[r0:r0 + len(ys), cols] = S[barg]
        return dist, arc


def route_layer(dist, arc, split_s, ahead_profile, behind_profile):
    """RGBA route image from a distance field. Profiles: list of (radius, rgb) bands, inner first;
    the outermost band's edge is anti-aliased over 1.2 px."""
    h, w = dist.shape
    out = np.zeros((h, w, 4), float)
    for prof, sel in ((ahead_profile, arc >= split_s), (behind_profile, arc < split_s)):
        if not sel.any():
            continue
        # paint outer to inner so the inner bands win
        for radius, rgb in reversed(prof):
            cov = np.clip((radius + 0.6 - dist) / 1.2, 0, 1) * sel
            a = cov[..., None]
            out[..., :3] = out[..., :3] * (1 - a) + np.array(rgb, float) * a
            out[..., 3] = np.maximum(out[..., 3], cov)
    out[..., :3] = np.where(out[..., 3:4] > 0, out[..., :3], 0)
    return Image.fromarray(np.dstack([out[..., :3], out[..., 3] * 255]).astype(np.uint8))


# ---------------------------------------------------------------- easing

def clamp01(x):
    return max(0.0, min(1.0, x))


def ease_in_out_cubic(x):
    x = clamp01(x)
    return 4 * x ** 3 if x < 0.5 else 1 - (-2 * x + 2) ** 3 / 2


def smoothstep(a, b, x):
    t = clamp01((x - a) / (b - a)) if b != a else float(x >= b)
    return t * t * (3 - 2 * t)


def trapezoid(t, t0, t1, ramp):
    """Normalised position 0..1 of a move from t0 to t1 with linear-velocity ramps."""
    if t <= t0:
        return 0.0
    if t >= t1:
        return 1.0
    T = t1 - t0
    v = 1.0 / (T - ramp)
    u = t - t0
    if u < ramp:
        return 0.5 * v / ramp * u * u
    if u > T - ramp:
        r = T - u
        return 1 - 0.5 * v / ramp * r * r
    return 0.5 * v * ramp + v * (u - ramp)


def spring(t, t0, duration=0.55, damping=0.88):
    """Critically-ish damped spring 0->1 (damping >= 0.85 per spec: overshoot well under 4 px)."""
    if t <= t0:
        return 0.0
    u = (t - t0) / duration
    if u >= 1.6:
        return 1.0
    w = 2 * math.pi * 1.0
    z = damping
    wd = w * math.sqrt(1 - z * z)
    x = 1 - math.exp(-z * w * u) * (math.cos(wd * u) + z * w / wd * math.sin(wd * u))
    return x


# ---------------------------------------------------------------- frame post-processing + encode

def bottom_band(frame: Image.Image) -> Image.Image:
    """Darken + fully desaturate the 55-100% band so nothing lime competes with the Continue
    button and the native copy always sits on a dark plate (spec 1.2 / 1.4)."""
    a = np.asarray(frame.convert("RGB")).astype(np.float32)
    y = np.arange(H, dtype=np.float32)[:, None]
    # 100% at 1412 -> 50% at the 55% line -> 30% by 1560: anything still crossing the line
    # (a trailing rider's label) is dark enough that body copy holds 4.5:1 even at 55%.
    gain = np.interp(y, [ZONE_BOTTOM - 30, ZONE_BOTTOM, ZONE_BOTTOM + 118], [1.0, 0.5, 0.3]).astype(np.float32)
    lum = (a @ np.array([0.2126, 0.7152, 0.0722], np.float32))[..., None]
    sat = np.clip((ZONE_BOTTOM - y) / 50.0, 0, 1)[..., None]     # grey by the 55% line
    a = (lum + (a - lum) * sat) * gain[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def top_fade(frame: Image.Image, to=SURFACE_DIM, start=0, end=300, strength=0.85):
    """Gentle top darkening under the pause / Skip buttons (top 12% holds no action)."""
    a = np.asarray(frame.convert("RGB")).astype(np.float32)
    y = np.arange(H, dtype=np.float32)[:, None, None]
    t = np.clip((end - y) / max(1, end - start), 0, 1) * strength
    a = a * (1 - t) + np.array(to[:3], np.float32) * t
    return Image.fromarray(a.astype(np.uint8))


class Encoder:
    """Pipes RGB frames at 1206x2622 into ffmpeg -> HEVC 1080x2340, no audio, Rec.709 tagged."""

    def __init__(self, path: Path, crf=30):
        self.path = path
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
            "-an",
            "-vf", f"scale={OUT_W}:{OUT_H}:flags=lanczos:out_color_matrix=bt709:out_range=tv,fps={FPS}",
            "-c:v", "libx265", "-crf", str(crf), "-preset", "slow", "-tag:v", "hvc1", "-pix_fmt", "yuv420p",
            "-x265-params", "log-level=error:colorprim=bt709:transfer=bt709:colormatrix=bt709:range=limited",
            "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
            "-movflags", "+faststart",
            str(path),
        ]
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    def write(self, img: Image.Image):
        self.p.stdin.write(img.convert("RGB").tobytes())

    def close(self):
        self.p.stdin.close()
        if self.p.wait() != 0:
            raise RuntimeError(f"ffmpeg failed for {self.path}")


def render_clip(name: str, duration: float, frame_fn, poster_t: float, out_dir: Path,
                dissolve: float = 0.5, crf=26, preview_times=()):
    """frame_fn(t) -> RGB Image (already post-processed). Bakes the loop dissolve so the last
    frame equals frame 0, encodes, and writes the poster (HEIC, 1080x2340) + preview PNGs."""
    out_dir.mkdir(parents=True, exist_ok=True)
    n = int(round(duration * FPS))
    nd = int(round(dissolve * FPS))
    first = frame_fn(0.0)
    enc = Encoder(out_dir / f"{name}.mp4", crf=crf)
    previews = {}
    for i in range(n):
        t = i / FPS
        img = first if i == 0 else frame_fn(t)
        j = i - (n - nd)
        if j >= 0:
            img = Image.blend(img, first, (j + 1) / nd)
        enc.write(img)
        for pt in preview_times:
            if abs(t - pt) < 0.5 / FPS:
                previews[pt] = img
    enc.close()
    poster = frame_fn(poster_t).resize((OUT_W, OUT_H), Image.LANCZOS)
    return poster, previews


def save_poster_heic(img: Image.Image, path: Path):
    import pillow_heif
    pillow_heif.register_heif_opener()
    img.convert("RGB").save(path, format="HEIF", quality=80)
