#!/bin/zsh
# build-c1b.sh — concept 1 variant B with rider portraits. Needs arjun/meera/ananya portraits in
# docs/onboarding-screenshots/portraits/ (.png or .jpg). Composites them into a copy of the real
# screenshot exactly where the app draws rider photos, then renders all three sizes.
set -e
SKILL="${0:A:h:h}"; REPO="${SKILL:h:h:h}"; cd "$REPO"
P=docs/onboarding-screenshots/portraits
pick() { for e in png jpg jpeg heic webp; do [[ -f "$P/$1.$e" ]] && { echo "$P/$1.$e"; return; }; done; echo "missing portrait: $P/$1.(png|jpg)" >&2; exit 1; }
arjun=$(pick arjun); meera=$(pick meera); ananya=$(pick ananya)
OUT=design/ad-creatives/c1b-rider-card; mkdir -p $OUT/shots
# Inner radii (source px, inside the lime ring) measured on 01_nav_hero_all_riders_ahead.png:
#   map markers  Arjun 387,666 r29 · Meera 484,927 r32 · Ananya 546,1222 r36
#   top strip    Arjun 128,531 r33 (lime ring) · Meera 408,531 r38 · Ananya 703,531 r38
swift "$SKILL/scripts/avatars.swift" docs/onboarding-screenshots/01_nav_hero_all_riders_ahead.png \
  $OUT/shots/01_nav_hero_avatars.png \
  387,666,29,$arjun 484,927,32,$meera 546,1222,36,$ananya \
  128,531,33,$arjun 408,531,38,$meera 703,531,38,$ananya
"$SKILL/scripts/render.sh" --slug c1b-rider-card --shot $OUT/shots/01_nav_hero_avatars.png \
  --h1 "Where did|*everyone go?*" --eyebrow "Group ride tracking" --sub "See every rider live, on one map." \
  --chipk "Live gap" --chip "Gap to every rider" --rider "Meera,M,280 m" --rider-img $meera \
  --scale xl --sat 13.3712,77.6792,1300 --pin 0.4013,0.3535
