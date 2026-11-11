"""Fetch Google Static Maps in ConvoTrack's dark map style (GoogleMapView.applyDarkStyle, labels off)."""
import json, re, sys, urllib.parse, urllib.request, pathlib

KEY = re.search(r'AIza[0-9A-Za-z_-]+',
    pathlib.Path('/Users/ricky/Workspace/convoy/convotrack/Services/GoogleMapsConfig.swift').read_text()).group(0)
STYLE = [
    "element:geometry|color:0x11191D",
    "element:labels|visibility:off",
    "feature:poi.park|element:geometry|color:0x17271F",
    "feature:landscape.natural|element:geometry|color:0x17271F",
    "feature:road|element:geometry|color:0x252E33",
    "feature:road|element:geometry.stroke|color:0x0C1215",
    "feature:road.highway|element:geometry|color:0x38434A",
    "feature:transit|visibility:off",
    "feature:water|element:geometry|color:0x0B1418",
]

def url(lat, lng, zoom, size=640, extra=(), maptype="roadmap"):
    # The app's dark style only applies to the road map; hybrid is Google's own satellite + roads + labels.
    style = STYLE if maptype == "roadmap" else []
    q = [("center", f"{lat:.7f},{lng:.7f}"), ("zoom", str(zoom)), ("size", f"{size}x{size}"),
         ("scale", "2"), ("maptype", maptype)] + [("style", s) for s in style] + list(extra) + [("key", KEY)]
    return "https://maps.googleapis.com/maps/api/staticmap?" + urllib.parse.urlencode(q)

def fetch(u, out):
    with urllib.request.urlopen(u) as r:
        pathlib.Path(out).write_bytes(r.read())

if __name__ == "__main__":
    lat, lng, zoom, out = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    extra = []
    for p in sys.argv[5:]:
        extra.append(("path", "color:0xCDEF1Eff|weight:4|enc:" + p))
    fetch(url(lat, lng, zoom, extra=extra), out)
