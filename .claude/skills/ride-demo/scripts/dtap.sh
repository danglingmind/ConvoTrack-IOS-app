#!/bin/bash
# dtap.sh <KEY> <ptX> <ptY>   -- tap in device POINTS (402x874 on iPhone 17/17 Pro)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; ensure_bins
read WX WY <<< "$(winpos "$1")"
[ -z "$WX" ] && { echo "ERROR: no window for '$1' (is the Simulator open?)" >&2; exit 1; }
"$SKD/tap" $((WX+$2)) $((WY+$3)); echo "tap $1 ($2,$3)"
