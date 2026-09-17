#!/bin/bash
# shot.sh <KEY> <outpath.png>  -- writes a 402x874 PNG (1 px == 1 device point)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
xcrun simctl io "$(udid_for "$1")" screenshot "$2" >/dev/null 2>&1
sips --resampleWidth 402 "$2" >/dev/null 2>&1
echo "$2"
