"""Fetch a seamless Google Static Maps mosaic (hybrid: satellite + roads + labels) around part of the route,
stitch it with ffmpeg, and project the route into mosaic pixels.

Writes ../header-video/assets/map.jpg and ../header-video/assets/route-px.json.
"""
import json, math, pathlib, subprocess
from staticmap import url, fetch

ZOOM = 18
MAPTYPE = "hybrid"
TILE = 640            # requested size (scale 1 px); Google returns 1280 at scale=2
CROP = 40             # scale-1 px trimmed from each side (logo, "Map data" strip)
STEP = TILE - 2 * CROP  # 560 scale-1 px per stitched tile -> 1120 output px
S_FROM, S_TO = 700, 2000          # route metres the riders cover
PAD_EW_M, PAD_NS_M = 900, 520     # camera margin around them

here = pathlib.Path(__file__).parent
out_dir = here.parent / "header-video" / "assets"
tiles_dir = here / f"tiles-{MAPTYPE}"
out_dir.mkdir(parents=True, exist_ok=True)
tiles_dir.mkdir(exist_ok=True)

route = json.loads((here / "route.json").read_text())
pts, cum = route["points"], route["cum"]

world = 256 * 2 ** ZOOM
def to_px(lat, lng):
    x = (lng + 180) / 360 * world
    s = math.sin(math.radians(lat))
    y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * world
    return x, y
def to_ll(x, y):
    lng = x / world * 360 - 180
    n = math.pi - 2 * math.pi * y / world
    return math.degrees(math.atan(math.sinh(n))), lng

seg = [p for p, c in zip(pts, cum) if S_FROM <= c <= S_TO]
lat0 = sum(p[0] for p in seg) / len(seg)
m_per_px = 156543.03392 * math.cos(math.radians(lat0)) / 2 ** ZOOM
xs, ys = zip(*(to_px(*p) for p in seg))
x0 = min(xs) - PAD_EW_M / m_per_px; x1 = max(xs) + PAD_EW_M / m_per_px
y0 = min(ys) - PAD_NS_M / m_per_px; y1 = max(ys) + PAD_NS_M / m_per_px
cols = math.ceil((x1 - x0) / STEP); rows = math.ceil((y1 - y0) / STEP)
ox = round(x0); oy = round(y0)   # integer world origin keeps every tile pixel-aligned
print(f"{cols}x{rows} tiles, {cols*STEP*2}x{rows*STEP*2} px, {m_per_px/2:.3f} m/px at scale 2")

for r in range(rows):
    for c in range(cols):
        f = tiles_dir / f"t_{r:02d}_{c:02d}.png"
        if f.exists():
            continue
        cx = ox + c * STEP + STEP // 2; cy = oy + r * STEP + STEP // 2
        lat, lng = to_ll(cx, cy)
        fetch(url(lat, lng, ZOOM, TILE, maptype=MAPTYPE), f)

# Crop each tile to its centre 1120 px and stack the grid.
inputs, filters, labels = [], [], []
for r in range(rows):
    for c in range(cols):
        i = r * cols + c
        inputs += ["-i", str(tiles_dir / f"t_{r:02d}_{c:02d}.png")]
        filters.append(f"[{i}:v]crop={STEP*2}:{STEP*2}:{CROP*2}:{CROP*2}[c{i}]")
        labels.append(f"[c{i}]")
layout = "|".join(f"{c*STEP*2}_{r*STEP*2}" for r in range(rows) for c in range(cols))
fc = ";".join(filters) + ";" + "".join(labels) + f"xstack=inputs={rows*cols}:layout={layout}[out]"
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", fc,
                "-map", "[out]", "-q:v", "2", str(out_dir / "map.jpg")], check=True)

# Route in mosaic pixels (scale 2), with cumulative metres for placing riders.
route_px = [[round((x - ox) * 2, 1), round((y - oy) * 2, 1)] for x, y in (to_px(*p) for p in pts)]
(out_dir / "route-px.json").write_text(json.dumps({
    "width": cols * STEP * 2, "height": rows * STEP * 2,
    "metresPerPx": round(m_per_px / 2, 4), "points": route_px, "cum": cum,
}))
print("wrote", out_dir / "map.jpg")
