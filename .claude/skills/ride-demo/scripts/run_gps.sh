#!/bin/bash
# run_gps.sh <track_prefix> [speed_mps]
#   Drives every device along its track. --distance=2 is the whole reason the
#   motion looks smooth: it emits a fix every 2 m instead of every 1 s.
#   speed 10 m/s (36 km/h) for hairpins, 14 (50 km/h) for open road.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SP="${2:-10}"
for K in $(keys); do
  nohup xcrun simctl location "$(udid_for "$K")" start --speed=$SP --distance=2 - < "$1_$K.txt" >/dev/null 2>&1 &
done
sleep 1
echo "GPS running at ${SP} m/s ($(python3 -c "print(int($SP*3.6))") km/h)."
echo "WAIT 15 s before recording — the streams can't start on the same instant and the"
echo "gap needs to settle, otherwise the take opens on a converging spacing."
