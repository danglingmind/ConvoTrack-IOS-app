#!/bin/bash
# record.sh <out.mov> [KEY]
#   Records ONE device. Recording more than one at a time saturates the GPU/media
#   engine and drops >50% of frames — measured. See reference/troubleshooting.md.
#   HEVC (simctl's default) uses the hardware media engine; do NOT force h264.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
K="${2:-L}"
nohup xcrun simctl io "$(udid_for "$K")" recordVideo --codec=hevc --force "$1" >/dev/null 2>&1 &
echo $! > "$1.pid"
echo "recording $K -> $1 (pid $(cat "$1.pid"))"
