#!/bin/bash
# encode.sh <in.mov> <out.mp4>
#   simctl records at 100-120 fps VFR at full device res (~260 MB for 3 min).
#   30 fps + 588 px wide + CRF 22 lands ~7 MB with no visible loss.
FF=$(command -v ffmpeg || echo /opt/homebrew/bin/ffmpeg)
"$FF" -y -i "$1" -vf "fps=30,scale=588:-2" -c:v libx264 -crf 22 -preset slow \
      -pix_fmt yuv420p -movflags +faststart "$2" -loglevel error
ls -lh "$2"
