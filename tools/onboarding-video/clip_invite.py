"""Video 3 - "One link. Everyone's in." (onboarding_invite, 8.0 s). Spec section 3, Video 3.

The lobby (RideLobbyView) re-set from its SwiftUI source: FloatingStatPill row, rosterSection
header (lifted pixels from 11b, link + QR buttons), ParticipantRiderRow per rider. Drawn at a
zoomed-out camera (k px/pt) so the photo strip, pills and a four-rider roster all fit inside
the 12-55% action zone. The destination photo + its "Photo: Kavya Hegde - Google" credit come
straight from 08.

STATUS follows the app's real tally (RideLobbyViewModel.readyStatusText): Solo -> 0/1 ready ->
All ready -> 1/2 ready ... so it reads honestly as each rider lands WAITING and then readies up.
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

from common import *

DUR = 8.0
K = 2.2                       # px per pt (zoomed out from the screenshot's 3.0)
COL_W = 402 * K               # one iPhone-width column
COL_X = (W - COL_W) / 2
PHOTO_H = 560
PILLS_Y = 420

ARRIVALS = [("meera", 2.30), ("kabir", 3.20), ("ananya", 4.10)]
READY_DELAY = 0.4


# ---------------------------------------------------------------- state

def roster_state(t):
    """[(key, arrival_progress 0..1, ready_mix 0..1)] in roster order."""
    rows = [("arjun", 1.0, 1.0)]
    for key, ta in ARRIVALS:
        if t >= ta:
            prog = spring(t, ta, duration=0.5, damping=0.9)
            ready = smoothstep(ta + READY_DELAY, ta + READY_DELAY + 0.2, t)  # .easeInOut(0.2)
            rows.append((key, prog, ready))
    return rows


def tally(t):
    others = [(k, ta) for k, ta in ARRIVALS if t >= ta]
    ready = sum(1 for k, ta in others if t >= ta + READY_DELAY + 0.1)
    total = len(others)
    if total == 0:
        return "Solo", False
    return ("All ready", True) if ready == total else (f"{ready}/{total} ready", False)


# ---------------------------------------------------------------- components

@lru_cache(maxsize=None)
def stat_pill(label, value, unit=None, dot=None):
    S = SS
    f_label = mono(12 * K * S, "bold")
    f_val = mono(15 * K * S, "bold")
    f_unit = pro(11 * K * S, "medium")
    dot_w = (7 + 4) * K if dot else 0
    vw = f_val.getlength(value) / S + (4 * K + f_unit.getlength(unit) / S if unit else 0) + dot_w
    w = 12 * K * 2 + max(f_label.getlength(label) / S, vw)
    h = 56 * K
    img, d = ss_canvas(w, h)
    d.rounded_rectangle((0, 0, w * S - 1, h * S - 1), radius=10 * K * S, fill=with_alpha(SURF_HIGH, 179),
                        outline=with_alpha(OUTLINE, 51), width=max(1, int(K * S)))
    x = 12 * K * S
    d.text((x, (10 + 11.5) * K * S), label, font=f_label, fill=ON_SURFACE_VARIANT, anchor="ls")
    base = (10 + 14.3 + 4 + 14.5) * K * S
    col = ON_SURFACE
    if dot:
        col = dot
        r = 3.5 * K * S
        cy = base + cap_middle(f_val) - 1 * K * S
        d.ellipse((x, cy - r, x + 2 * r, cy + r), fill=dot)
        x += 11 * K * S
    d.text((x, base), value, font=f_val, fill=col, anchor="ls")
    if unit:
        x += f_val.getlength(value) + 4 * K * S
        d.text((x, base), unit, font=f_unit, fill=ON_SURFACE_VARIANT, anchor="ls")
    return ss_finish(img, w, h)


def pills_row(t):
    n_riders = 1 + sum(1 for _, ta in ARRIVALS if t >= ta + 0.15)
    status, all_ready = tally(t)
    pills = [stat_pill("DISTANCE", "3", "km"), stat_pill("RIDERS", str(n_riders)),
             stat_pill("STATUS", status, None, LIME if all_ready else SECONDARY_FIXED),
             stat_pill("CODE", "DTPSDT")]
    row = Image.new("RGBA", (int(COL_W), int(56 * K) + 2), (0, 0, 0, 0))
    x = 20 * K
    for p in pills:
        row.alpha_composite(p, (int(round(x)), 0)) if x + p.width <= row.width else \
            row.alpha_composite(p.crop((0, 0, max(0, row.width - int(round(x))), p.height)), (int(round(x)), 0))
        x += p.width + 8 * K
    return row


@lru_cache(maxsize=1)
def roster_header():
    """'SQUAD ROSTER  * LIVE  [link] [qr]' - text re-set, buttons lifted from 11b."""
    S = SS
    src = Image.open(SHOTS / "11b_lobby_4_riders_full_roster.png").convert("RGBA")
    def button(x0):
        b = src.crop((x0, 851, x0 + 134, 987))
        m = Image.new("L", (b.width * 4, b.height * 4), 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, m.width - 1, m.height - 1), radius=14 * 4 * 3, fill=255)
        b.putalpha(m.resize(b.size, Image.LANCZOS))
        sc = K / 3.0
        return b.resize((int(b.width * sc), int(b.height * sc)), Image.LANCZOS)
    link, qr = button(857), button(1013)
    w, h = COL_W - 40 * K, max(link.height, 30)
    img, d = ss_canvas(w, h)
    f = mono(12 * K * S, "bold")
    mid = h / 2 * S
    draw_text(d, (0, mid - cap_middle(f)), "SQUAD ROSTER", f, LIME, tracking=4 * K * S, anchor="ls")
    title_w = text_width(f, "SQUAD ROSTER", 4 * K * S) / S
    btns_w = link.width + 8 * K + qr.width
    f9 = mono(9 * K * S, "bold")
    live_w = (6 + 4) * K + text_width(f9, "LIVE", 2 * K * S) / S
    lx = title_w + ((w - btns_w) - title_w - live_w) / 2
    r = 3 * K
    d.ellipse((lx * S, mid - r * S, (lx + 2 * r) * S, mid + r * S), fill=LIME)
    draw_text(d, ((lx + 10 * K) * S, mid - cap_middle(f9)), "LIVE", f9, LIME, tracking=2 * K * S, anchor="ls")
    out = ss_finish(img, w, h)
    out.alpha_composite(link, (int(w - btns_w), (h - link.height) // 2))
    out.alpha_composite(qr, (int(w - qr.width), (h - qr.height) // 2))
    return out, (w - btns_w + link.width / 2, h / 2)


@lru_cache(maxsize=None)
def rider_row(key, ready: bool):
    S = SS
    leader = key == "arjun"
    w, h = COL_W - 40 * K, 80 * K
    img, d = ss_canvas(w, h)
    accent = LIME if ready else OUTLINE
    badge_bg, badge_fg = (LIME, ON_PRIMARY_CONTAINER) if ready else (SURF_VARIANT, ON_SURFACE_VARIANT)
    d.rounded_rectangle((0, 0, w * S - 1, h * S - 1), radius=12 * K * S, fill=with_alpha(SURF_HIGH, 179),
                        outline=accent, width=max(1, int(1 * K * S)))
    d.rounded_rectangle((0, 0, 4 * K * S, h * S - 1), radius=2 * K * S, fill=accent)
    # avatar + presence dot (riders arrive connected)
    av = 48 * K
    ax, ay = 16 * K, 16 * K
    a = circle_avatar(key, av * S, SURF_VARIANT, ("pro", 24 * K * S, "semibold"), ON_SURFACE)
    img.alpha_composite(a, (int(ax * S), int(ay * S)))
    dr = 7 * K
    dcx, dcy = ax + av - dr, ay + av - dr
    d.ellipse(((dcx - dr - 2 * K) * S, (dcy - dr - 2 * K) * S, (dcx + dr + 2 * K) * S, (dcy + dr + 2 * K) * S), fill=SURFACE_DIM)
    d.ellipse(((dcx - dr) * S, (dcy - dr) * S, (dcx + dr) * S, (dcy + dr) * S), fill=TERTIARY)
    # name / LEADER / role
    tx = (ax + av + 16 * K) * S
    f_name = pro(18 * K * S, "medium")
    f_role = mono(10 * K * S, "bold")
    name_base = (h / 2 - 2 * K) * S
    d.text((tx, name_base), RIDERS[key], font=f_name, fill=ON_SURFACE, anchor="ls")
    if leader:
        f_b = mono(8 * K * S, "bold")
        bx = tx + f_name.getlength(RIDERS[key]) + 6 * K * S
        bw = text_width(f_b, "LEADER", 1 * K * S) + 10 * K * S
        bh = (8 + 4) * K * S + 2 * K * S
        by = name_base + cap_middle(f_name) - bh / 2
        d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=bh / 2, fill=LIME)
        draw_text(d, (bx + 5 * K * S, by + bh / 2 - cap_middle(f_b)), "LEADER", f_b, ON_LIME, tracking=1 * K * S)
    draw_text(d, (tx, name_base + 18 * K * S), "RIDE LEADER" if leader else "FORMATION RIDER", f_role,
              ON_SURFACE_VARIANT, tracking=1 * K * S)
    # status badge
    f_b = mono(12 * K * S, "bold")
    label = "READY" if ready else "WAITING"
    bw = text_width(f_b, label, 1 * K * S) + 24 * K * S
    bh = (12 * 1.2 + 12) * K * S
    bx = w * S - 16 * K * S - bw
    by = h / 2 * S - bh / 2
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=bh / 2, fill=badge_bg)
    draw_text(d, (bx + bw / 2, h / 2 * S - cap_middle(f_b)), label, f_b, badge_fg, tracking=1 * K * S, anchor="ms")
    return ss_finish(img, w, h)


@lru_cache(maxsize=1)
def photo_strip():
    src = Image.open(SHOTS / "08_lobby_leader.png").convert("RGB")
    strip = src.crop((0, 330, W, 330 + PHOTO_H)).convert("RGBA")
    a = np.asarray(strip).astype(np.float32)
    # the lobby's own fade into the page (LinearGradient surfaceDim -> clear, bottom -> top)
    y = np.arange(PHOTO_H, dtype=np.float32)[:, None, None]
    t = np.clip((y - (PHOTO_H - 240)) / 240.0, 0, 1) ** 1.2
    a[..., :3] = a[..., :3] * (1 - t) + np.array(SURFACE_DIM[:3], np.float32) * t
    strip = Image.fromarray(a.astype(np.uint8))
    # licence credit, lifted from the same shot and kept legible above the fade
    cred = src.crop((740, 975, 1160, 1010))
    c = np.asarray(cred).astype(np.float32)
    alpha = np.clip((c.max(axis=2) - 60) / 140.0, 0, 1)
    credit = Image.fromarray(np.dstack([np.full_like(c, 225), alpha * 255]).astype(np.uint8))
    credit = credit.crop(credit.getbbox())
    # just below the top bar's Skip button, right-aligned to the column like the lobby's credit
    strip.alpha_composite(credit, (int(COL_X + COL_W - 20 * K - credit.width), PILLS_Y - 14 - credit.height))
    return strip


@lru_cache(maxsize=1)
def link_bubble():
    """Neutral message bubble carrying the convotrack.in link card (content from 09's preview)."""
    S = SS
    src = Image.open(SHOTS / "09_share_sheet.png").convert("RGBA")
    icon = src.crop((100, 1540, 292, 1732))
    m = Image.new("L", (icon.width * 4, icon.height * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, m.width - 1, m.height - 1), radius=44 * 4, fill=255)
    icon.putalpha(m.resize(icon.size, Image.LANCZOS))
    sc = K / 3.0
    icon = icon.resize((int(icon.width * sc), int(icon.height * sc)), Image.LANCZOS)
    f1 = pro(17 * K * S, "semibold")
    f2 = pro(15 * K * S, "regular")
    t1, t2 = "Ride together. Never lose the pack.", "convotrack.in"
    pad = 14 * K
    w = pad + icon.width + 12 * K + f1.getlength(t1) / S + pad
    h = pad * 2 + icon.height
    img, d = ss_canvas(w, h)
    d.rounded_rectangle((0, 0, w * S - 1, h * S - 1), radius=20 * K * S, fill=(44, 44, 46, 245),
                        outline=(255, 255, 255, 22), width=int(K * S))
    tx = (pad + icon.width + 12 * K) * S
    d.text((tx, (h / 2 - 3 * K) * S), t1, font=f1, fill=(245, 245, 245, 255), anchor="ls")
    d.text((tx, (h / 2 + 17 * K) * S), t2, font=f2, fill=(150, 150, 152, 255), anchor="ls")
    out = ss_finish(img, w, h)
    out.alpha_composite(icon, (int(pad), int(pad)))
    out, p = shadow(out, 12, 0.5, dy=6)
    return out


# ---------------------------------------------------------------- frame

def frame(t: float) -> Image.Image:
    img = Image.new("RGBA", (W, H), SURFACE_DIM)
    img.alpha_composite(photo_strip(), (0, 0))
    img.alpha_composite(pills_row(t), (int(COL_X), PILLS_Y))

    header, link_c = roster_header()
    hx, hy = COL_X + 20 * K, PILLS_Y + 56 * K + 14 * K
    img.alpha_composite(header, (int(hx), int(hy)))
    lcx, lcy = hx + link_c[0], hy + link_c[1]

    rows_y = hy + header.height + 14 * K
    pitch = (80 + 12) * K
    for i, (key, prog, ready) in enumerate(roster_state(t)):
        y = rows_y + i * pitch
        x = COL_X + 20 * K + (1 - prog) * 260
        op = clamp01(prog * 1.6)
        if ready >= 0.999:
            paste(img, rider_row(key, True), x, y, op)
        else:
            paste(img, rider_row(key, False), x, y, op)
            if ready > 0:
                paste(img, rider_row(key, True), x, y, op * ready)

    # 1.0-1.4 s: tap ring on the link button (one soft ring, no flash)
    u = (t - 1.0) / 0.45
    if 0 < u < 1:
        r = 30 * K * (1 + 0.5 * ease_in_out_cubic(u))
        ring, rd = ss_canvas(2 * r + 8, 2 * r + 8)
        c = ring.width / 2
        rd.ellipse((c - r * SS, c - r * SS, c + r * SS, c + r * SS), outline=with_alpha(ON_SURFACE, int(200 * (1 - u))), width=int(2.5 * SS))
        paste_center(img, ss_finish(ring, 2 * r + 8, 2 * r + 8), lcx, lcy)

    # 1.15-2.2 s: the link lifts off the button and floats out of frame right
    if 1.15 <= t <= 2.25:
        b = link_bubble()
        grow = ease_in_out_cubic((t - 1.15) / 0.45)
        fly = ease_in_out_cubic((t - 1.55) / 0.65) ** 1.6
        sc = 0.35 + 0.65 * grow
        bw, bh = max(1, int(b.width * sc)), max(1, int(b.height * sc))
        bs = b.resize((bw, bh), Image.LANCZOS)
        cx = lcx - 180 + 180 * (1 - grow) + (W + 120 - (lcx - 180) + b.width / 2) * fly
        cy = lcy - 40 - 150 * grow
        paste(img, bs, cx - bw / 2, cy - bh / 2, opacity=clamp01(grow * 1.5))

    # Full-screen: nothing darkened here. The app tints/dims the clip and lays the copy gradient.
    return img.convert("RGB")


if __name__ == "__main__":
    import sys
    from pathlib import Path
    out = Path(sys.argv[1])
    for tt in [float(x) for x in sys.argv[2:]]:
        frame(tt).save(out / f"invite_{tt:.1f}.png")
