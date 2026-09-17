#!/usr/bin/env python3
"""N-rider convoy tracks holding an exact along-road spacing.
usage: gen_tracks.py <route.json> <spacing_m> <n_riders> <resample_m> <run_m> <prefix>"""
import json, math, sys
def decode(p):
    pts=[];i=0;lat=0;lng=0
    while i<len(p):
        for who in (0,1):
            shift=0;r=0
            while True:
                b=ord(p[i])-63;i+=1
                r|=(b&0x1f)<<shift;shift+=5
                if b<0x20:break
            d=~(r>>1) if (r&1) else (r>>1)
            if who==0: lat+=d
            else: lng+=d
        pts.append((lat/1e5,lng/1e5))
    return pts
R=6371000.0
def hav(a,b):
    la1,lo1=map(math.radians,a);la2,lo2=map(math.radians,b)
    h=math.sin((la2-la1)/2)**2+math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2*R*math.asin(math.sqrt(h))
rj,sp,n,step,run,prefix = sys.argv[1],float(sys.argv[2]),int(sys.argv[3]),float(sys.argv[4]),float(sys.argv[5]),sys.argv[6]
START = float(sys.argv[7]) if len(sys.argv)>7 else 0.0
d=json.load(open(rj));leg=d['routes'][0]['legs'][0]
pts=[]
for st in leg['steps']:
    s=decode(st['polyline']['points'])
    if pts and s and s[0]==pts[-1]: s=s[1:]
    pts.extend(s)
cum=[0.0]
for i in range(1,len(pts)): cum.append(cum[-1]+hav(pts[i-1],pts[i]))
total=cum[-1]
def at(x):
    if x<=0: return pts[0]
    if x>=total: return pts[-1]
    lo,hi=0,len(cum)-1
    while lo<hi-1:
        m=(lo+hi)//2
        if cum[m]<=x: lo=m
        else: hi=m
    s2=cum[hi]-cum[lo];t=0 if s2==0 else (x-cum[lo])/s2
    return (pts[lo][0]+(pts[hi][0]-pts[lo][0])*t, pts[lo][1]+(pts[hi][1]-pts[lo][1])*t)
lead_off=sp*(n-1)
run=min(run, total-lead_off-START)
names=['L']+[f'R{i+2}' for i in range(n-1)]      # L is front, R2 next, R3 tail
offs =[lead_off-sp*i for i in range(n)]
trk={k:[] for k in names}
x=0.0
while x<=run:
    for k,o in zip(names,offs): trk[k].append(at(START+x+o))
    x+=step
for k in names:
    with open(f"{prefix}_{k}.txt","w") as f:
        for la,ln in trk[k]: f.write(f"{la:.6f},{ln:.6f}\n")
print(f"route {total/1000:.2f} km | start {START/1000:.2f} km | run {run/1000:.2f} km | {len(trk['L'])} waypoints each @ {step:.0f} m")
idx=range(0,len(trk['L']),max(1,len(trk['L'])//25))
for a,b in zip(names,names[1:]):
    g=[hav(trk[a][i],trk[b][i]) for i in idx]
    print(f"  {a}->{b}: straight-line {min(g):5.1f} – {max(g):5.1f} m   (along-road {sp:.0f} m)")
g=[hav(trk[names[0]][i],trk[names[-1]][i]) for i in idx]
print(f"  front->tail: {min(g):5.1f} – {max(g):5.1f} m  (along-road {lead_off:.0f} m)")
for k,o in zip(names,offs): print(f"  {k} starts {trk[k][0][0]:.6f},{trk[k][0][1]:.6f}  (route km {(START+o)/1000:.2f})")
print(f"  leader ends at route km {(START+run+lead_off)/1000:.2f} of {total/1000:.2f} -> margin {(total-START-run-lead_off):.0f} m")
for s in (11,14):
    print(f"  @ {s} m/s ({s*3.6:.0f} km/h): {run/s/60:.1f} min")
