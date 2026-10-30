#!/bin/zsh
# build-c2.sh — concept 2 "Nobody gets left behind": the real group-split alert, captured on a
# production ride (docs/onboarding-screenshots/14_group_split_alert.png, leader's screen, Kabir
# 5.1 km back). The alert card on the screen IS the feature, so the overlay is text only
# (--chip-style text): no feature card, marker or leader line. Needs arjun + kabir portraits
# (avatars only show in the story crop: Kabir's edge chip and the bottom rider strip).
set -e
SKILL="${0:A:h:h}"; REPO="${SKILL:h:h:h}"; cd "$REPO"
P=docs/onboarding-screenshots/portraits
pick() { for e in png jpg jpeg heic webp; do [[ -f "$P/$1.$e" ]] && { echo "$P/$1.$e"; return; }; done; echo "missing portrait: $P/$1.(png|jpg) — ask the user for it" >&2; exit 1; }
arjun=$(pick arjun); kabir=$(pick kabir)
OUT=design/ad-creatives/c2-live-ride-map; mkdir -p $OUT/shots
# Inner radii (source px) measured on 14_group_split_alert.png:
#   strip Arjun (you, leader) 132,2162 r38 · strip Kabir 425,2162 r42 · Kabir edge chip 138,1683 r46
swift "$SKILL/scripts/avatars.swift" docs/onboarding-screenshots/14_group_split_alert.png \
  $OUT/shots/14_split_avatars.png 132,2162,38,$arjun 425,2162,42,$kabir 138,1683,46,$kabir
common=(--slug c2-live-ride-map --shot $OUT/shots/14_split_avatars.png
  --h1 "Nobody gets|*left behind.*" --eyebrow "Group ride tracking"
  --chipk "Live feature" --chip "Group split alerts" --chip-style text
  --scale xl --sat 13.3712,77.6792,1300)
"$SKILL/scripts/render.sh" $common --sub "Know the moment someone drops back." --shift -60 --sizes feed,square
# Story: sub-line dropped so the phone can lift and keep the alert clear of the label.
"$SKILL/scripts/render.sh" $common --shift -140 --sizes story
