#!/bin/bash
# stop_record.sh <out.mov>   SIGINT only — SIGKILL leaves an unreadable mp4.
for p in $(pgrep -f recordVideo); do kill -INT $p; done
sleep 5
[ -f "$1" ] && ls -lh "$1"
