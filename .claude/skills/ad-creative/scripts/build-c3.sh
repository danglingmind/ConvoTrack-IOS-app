#!/bin/zsh
# build-c3.sh — concept 3 "One tap. All alerted.": a real emergency alert, captured on a
# production ride (docs/onboarding-screenshots/15_emergency_alert.png, Arjun's screen, Kabir's
# emergency pin 190 m up the route). The banner on screen IS the feature, so the overlay is text
# only (--chip-style text). Needs arjun + kabir portraits (rider strip; Kabir's map marker is
# covered by his emergency pin, so it stays as captured).
set -e
SKILL="${0:A:h:h}"; REPO="${SKILL:h:h:h}"; cd "$REPO"
P=docs/onboarding-screenshots/portraits
pick() { for e in png jpg jpeg heic webp; do [[ -f "$P/$1.$e" ]] && { echo "$P/$1.$e"; return; }; done; echo "missing portrait: $P/$1.(png|jpg) — ask the user for it" >&2; exit 1; }
arjun=$(pick arjun); kabir=$(pick kabir)
OUT=design/ad-creatives/c3-emergency-alert; mkdir -p $OUT/shots
# Inner radii (source px) measured on 15_emergency_alert.png: strip Kabir 131,2161 r39 · strip Arjun (you) 474,2162 r40
swift "$SKILL/scripts/avatars.swift" docs/onboarding-screenshots/15_emergency_alert.png \
  $OUT/shots/15_emergency_avatars.png 131,2161,39,$kabir 474,2162,40,$arjun
common=(--slug c3-emergency-alert --shot $OUT/shots/15_emergency_avatars.png
  --h1 "One tap.|*All alerted.*" --eyebrow "Group ride safety"
  --chipk "Live feature" --chip "Emergency alerts" --chip-style text
  --scale xl --sat 13.3712,77.6792,1300)
"$SKILL/scripts/render.sh" $common --sub "Every rider sees who needs help, and where." --shift -60 --sizes feed,square
# Story: sub-line dropped so the phone can lift and keep the banner clear of the label.
"$SKILL/scripts/render.sh" $common --shift -140 --sizes story
