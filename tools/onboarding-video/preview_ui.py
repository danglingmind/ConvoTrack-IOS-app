"""Approximate the native OnboardingFlowView chrome over a clip frame, for review only
(scrim, eyebrow/headline/body, page dots, Continue, pause + Skip). Output is 1080x2340.

    preview_ui.py <frame.png> <page 0|1|2> <out.png>
"""
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, __import__("os").path.dirname(__file__))
from common import LIME, ON_LIME, ON_SURFACE, ON_SURFACE_VARIANT, SURF_HIGH, SURFACE_DIM, mono, pro  # noqa

PAGES = [
    ("LIVE TRACKING", ["Every rider. One", "map."], ["See where your whole pack is, second by", "second — even the ones you can't see."]),
    ("REGROUP", ["Nobody gets left", "behind."], ["Call a regroup and every phone knows", "where to wait. One tap for emergencies."]),
    ("ONE LINK", ["One link. Everyone's", "in."], ["Share a link. They're on the map. No", "group chat chaos."]),
]
STOPS = [(0.0, 0.0), (0.38, 0.0), (0.60, 0.88), (0.78, 0.97), (1.0, 1.0)]


def compose(frame: Image.Image, page: int) -> Image.Image:
    W, H = 1080, 2340
    k = W / 390.0          # px per pt on a 390-pt-wide phone at this export size
    img = frame.convert("RGBA").resize((W, H))
    scrim = Image.new("RGBA", (W, H))
    sd = ImageDraw.Draw(scrim)
    for y in range(H):
        f = y / H
        for (x0, a0), (x1, a1) in zip(STOPS, STOPS[1:]):
            if x0 <= f <= x1:
                a = a0 + (a1 - a0) * (f - x0) / (x1 - x0)
                break
        sd.line([(0, y), (W, y)], fill=SURFACE_DIM[:3] + (int(a * 255),))
    img.alpha_composite(scrim)
    d = ImageDraw.Draw(img)
    eyebrow, head, body = PAGES[page]
    # footer from the bottom: 34pt home-indicator inset, 16 pad, 56 button, 18, 8 dots, 20 pad
    y_btn = H - (34 + 16 + 56) * k
    d.rounded_rectangle((24 * k, y_btn, W - 24 * k, y_btn + 56 * k), radius=12 * k, fill=LIME)
    d.text((W / 2, y_btn + 28 * k), "Continue", font=pro(17 * k, "semibold"), fill=ON_LIME, anchor="mm")
    y_dots = y_btn - 18 * k - 8 * k
    x = (W - (22 + 3 * 8 + 3 * 8) * k) / 2
    for i in range(4):
        w = (22 if i == page else 8) * k
        d.rounded_rectangle((x, y_dots, x + w, y_dots + 8 * k), radius=4 * k,
                            fill=ON_SURFACE if i == page else ON_SURFACE_VARIANT[:3] + (115,))
        x += w + 8 * k
    y = y_dots - 20 * k
    fb = pro(17 * k, "regular")
    for line in reversed(body):
        d.text((24 * k, y), line, font=fb, fill=ON_SURFACE_VARIANT, anchor="ls")
        y -= 22 * k
    y -= 12 * k
    fh = pro(34 * k, "bold")
    for line in reversed(head):
        d.text((24 * k, y), line, font=fh, fill=ON_SURFACE, anchor="ls")
        y -= 41 * k
    y -= 2 * k
    d.text((24 * k, y), eyebrow, font=mono(12 * k, "bold"), fill=ON_SURFACE_VARIANT, anchor="ls")
    # top bar: pause + Skip
    top = 59 * k + 8 * k
    d.ellipse((16 * k, top, 60 * k, top + 44 * k), fill=SURF_HIGH[:3] + (179,))
    d.rectangle((33 * k, top + 15 * k, 36 * k, top + 29 * k), fill=ON_SURFACE)
    d.rectangle((40 * k, top + 15 * k, 43 * k, top + 29 * k), fill=ON_SURFACE)
    sk = pro(17 * k, "semibold")
    sw = sk.getlength("Skip") + 32 * k
    d.rounded_rectangle((W - 16 * k - sw, top, W - 16 * k, top + 44 * k), radius=22 * k, fill=SURF_HIGH[:3] + (179,))
    d.text((W - 16 * k - sw / 2, top + 22 * k), "Skip", font=sk, fill=ON_SURFACE, anchor="mm")
    return img.convert("RGB")


if __name__ == "__main__":
    compose(Image.open(sys.argv[1]), int(sys.argv[2])).save(sys.argv[3])
