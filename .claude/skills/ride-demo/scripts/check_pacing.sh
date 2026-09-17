#!/bin/bash
# check_pacing.sh <video>
#   Proves whether a take is smooth. A good take: 0 gaps >50 ms.
#   A saturated machine shows hundreds of 100-460 ms gaps = the "snappy" look.
FP=$(command -v ffprobe || echo /opt/homebrew/bin/ffprobe)
"$FP" -v error -select_streams v:0 -show_entries frame=best_effort_timestamp_time -of csv=p=0 "$1" 2>/dev/null | sed 's/,$//' > /tmp/_pts.txt
python3 - <<'PY'
import statistics
t=sorted(float(x) for x in open('/tmp/_pts.txt') if x.strip())
d=[(t[i]-t[i-1])*1000 for i in range(1,len(t))]; d=[x for x in d if x>0]
print(f"{len(t)} frames / {t[-1]-t[0]:.1f}s = {len(t)/(t[-1]-t[0]):.1f} fps")
print(f"gap ms: median {statistics.median(d):.1f}  p99 {sorted(d)[int(len(d)*.99)-1]:.1f}  max {max(d):.1f}")
n=len([x for x in d if x>50])
print(f"gaps >50ms: {n}   -> {'OK, smooth' if n==0 else 'STUTTER: too much load, record fewer devices'}")
PY
