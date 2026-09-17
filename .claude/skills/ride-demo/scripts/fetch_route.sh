#!/bin/bash
# fetch_route.sh "<origin>" "<destination>" <out.json>
#   Fetch the SAME route the app will draw, so generated GPS tracks can't diverge from it.
KEY="${GOOGLE_MAPS_KEY:-$(grep -o 'AIza[A-Za-z0-9_-]*' "$(dirname "${BASH_SOURCE[0]}")/../../../../convotrack/Services/GoogleMapsConfig.swift" | head -1)}"
O=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1")
D=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[2]))" "$2")
curl -s "https://maps.googleapis.com/maps/api/directions/json?origin=$O&destination=$D&mode=driving&key=$KEY" -o "$3"
python3 - "$3" <<'PY'
import json,sys,math
d=json.load(open(sys.argv[1]))
print("status:",d.get('status'))
if d.get('status')!='OK': raise SystemExit(1)
l=d['routes'][0]['legs'][0]
print(" ",l['start_address'][:55],"->",l['end_address'][:40])
print("  dist:",l['distance']['text']," dur:",l['duration']['text'])
def dec(p):
    pts=[];i=0;la=0;ln=0
    while i<len(p):
        for w in (0,1):
            sh=0;r=0
            while True:
                b=ord(p[i])-63;i+=1;r|=(b&0x1f)<<sh;sh+=5
                if b<0x20:break
            v=~(r>>1) if (r&1) else (r>>1)
            if w==0: la+=v
            else: ln+=v
        pts.append((la/1e5,ln/1e5))
    return pts
pts=[]
for st in l['steps']:
    s=dec(st['polyline']['points'])
    if pts and s and s[0]==pts[-1]: s=s[1:]
    pts.extend(s)
def br(a,b):
    a1,o1=map(math.radians,a);a2,o2=map(math.radians,b);dl=o2-o1
    return math.degrees(math.atan2(math.sin(dl)*math.cos(a2),math.cos(a1)*math.sin(a2)-math.sin(a1)*math.cos(a2)*math.cos(dl)))
t=sum(abs((br(pts[i],pts[i+1])-br(pts[i-1],pts[i])+180)%360-180) for i in range(1,len(pts)-1))
km=l['distance']['value']/1000
print(f"  curvature: {t/km:.0f} deg/km   (>800 = great demo, ~200 = dull highway)")
PY
