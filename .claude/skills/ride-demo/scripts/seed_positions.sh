#!/bin/bash
# seed_positions.sh <track_prefix>
#   Places every device on the FIRST waypoint of its track.
#   Do this BEFORE tapping Start Ride: it's what stops a bogus GROUP SPLIT
#   firing (and being latched into max_group_split_meters forever).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for K in $(keys); do
  F="$1_$K.txt"; [ -f "$F" ] || { echo "missing $F" >&2; exit 1; }
  P=$(head -1 "$F")
  xcrun simctl location "$(udid_for "$K")" set "$P"
  echo "$K seeded at $P"
done
