#!/bin/bash
# dswipe.sh <KEY> <x1> <y1> <x2> <y2> [steps] [holdMs]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; ensure_bins
read WX WY <<< "$(winpos "$1")"
[ -z "$WX" ] && { echo "ERROR: no window for '$1'" >&2; exit 1; }
"$SKD/drag" $((WX+$2)) $((WY+$3)) $((WX+$4)) $((WY+$5)) ${6:-25} ${7:-40}; echo "swipe $1 ($2,$3)->($4,$5)"
