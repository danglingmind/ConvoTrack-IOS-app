#!/bin/zsh
# render.sh --slug <name> --shot <screenshot.png> --h1 "Never lose|*the pack.*" [--eyebrow ..] [--sub ..]
#           [--chip ..] [--chipk ..] [--chip-icon people|gap|alert|link|flag] [--pin fx,fy]
#           [--rider "Name,I,280 m"] [--rider-img portrait.png] [--pin-r 0.031]   (radius of the pinned marker, fraction of screenshot width; leader stops there)
#           [--look dark|sat] [--sat lat,lon,spanMetres | --bg <image>] [--scale std|xl]
#           [--layout stack|split] [--tilt -5] [--shift px] [--chip-dx px] [--chip-dy px]
#           [--sizes feed,square,story]
# Renders assets/template.html in headless Chrome and writes flattened, exact-size PNGs to
# design/ad-creatives/<slug>/<slug>-<size>.png (plus hires @2x copies in hires/).
# --sat renders a real Apple Maps satellite background per size (2x, cached in <slug>/bg/).
set -e
SKILL="${0:A:h:h}"
REPO="${SKILL:h:h:h}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
sizes="feed,square,story"; layout="stack"; tilt=""; eyebrow=""; sub=""; chip=""; chipk=""
look="dark"; scale="std"; pin=""; sat=""; bg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) slug="$2"; shift 2;; --shot) shot="$2"; shift 2;; --h1) h1="$2"; shift 2;;
    --eyebrow) eyebrow="$2"; shift 2;; --sub) sub="$2"; shift 2;; --chip) chip="$2"; shift 2;;
    --chipk) chipk="$2"; shift 2;; --layout) layout="$2"; shift 2;; --tilt) tilt="$2"; shift 2;;
    --sizes) sizes="$2"; shift 2;; --chip-icon) chipi="$2"; shift 2;;
    --shift) shift_px="$2"; shift 2;; --chip-dx) chipdx="$2"; shift 2;; --chip-dy) chipdy="$2"; shift 2;;
    --look) look="$2"; shift 2;; --scale) scale="$2"; shift 2;; --pin) pin="$2"; shift 2;;
    --sat) sat="$2"; look="sat"; shift 2;; --bg) bg="$2"; look="sat"; shift 2;;
    --pin-r) pinr="$2"; shift 2;; --rider) rider="$2"; chipi="rider"; shift 2;; --rider-img) riderimg="$2"; shift 2;;
    --chip-style) chipstyle="$2"; shift 2;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done
[[ -z "$slug" || -z "$shot" || -z "$h1" ]] && { echo "need --slug --shot --h1" >&2; exit 2; }
[[ -f "$shot" ]] || { echo "screenshot not found: $shot" >&2; exit 2; }
out="$REPO/design/ad-creatives/$slug"; mkdir -p "$out/hires"
enc() { python3 -I -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
for size in ${(s:,:)sizes}; do
  case $size in feed) W=1080; H=1350;; square) W=1080; H=1080;; story) W=1080; H=1920;; *) echo "bad size $size" >&2; exit 2;; esac
  bgfile="$bg"
  if [[ -n "$sat" ]]; then
    # Cache key includes the coordinates so a new location re-renders.
    mkdir -p "$out/bg"; bgfile="$out/bg/sat-${size}-${sat//,/_}.png"
    if [[ ! -f "$bgfile" ]]; then
      lat=${${(s:,:)sat}[1]}; lon=${${(s:,:)sat}[2]}; span=${${(s:,:)sat}[3]}
      # Taller canvases keep the same metres-per-pixel: scale the span by the canvas height.
      sspan=$(( span * H / 1350.0 ))
      swift "$SKILL/scripts/satellite.swift" $lat $lon $sspan $((W*2)) $((H*2)) "$bgfile" >/dev/null
    fi
  fi
  url="file://$SKILL/assets/template.html?size=$size&layout=$layout&look=$look&scale=$scale&shot=$(enc "file://${shot:A}")&h1=$(enc "$h1")&eyebrow=$(enc "$eyebrow")&sub=$(enc "$sub")&chip=$(enc "$chip")&chipk=$(enc "$chipk")&tilt=$(enc "$tilt")&chipi=${chipi:-people}&shift=${shift_px:-0}&chipdx=${chipdx:-0}&chipdy=${chipdy:-0}&pin=$(enc "$pin")"
  [[ -n "$bgfile" ]] && url="$url&bg=$(enc "file://${bgfile:A}")"
  [[ -n "$pinr" ]] && url="$url&pinr=$pinr"; [[ -n "$rider" ]] && url="$url&rider=$(enc "$rider")"
  [[ -n "$riderimg" ]] && url="$url&riderimg=$(enc "file://${riderimg:A}")"
  [[ -n "$chipstyle" ]] && url="$url&chipstyle=$chipstyle"
  raw="$out/hires/$slug-$size.raw.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=$W,$H \
    --force-device-scale-factor=2 --default-background-color=FF090B0D \
    --virtual-time-budget=4000 --screenshot="$raw" "$url" >/dev/null 2>&1
  # Flatten to RGB (alpha is rejected by ad/app stores): PNG -> JPEG -> PNG, then exact size.
  sips -s format jpeg -s formatOptions 100 "$raw" --out "$raw.jpg" >/dev/null
  sips -s format png "$raw.jpg" --out "$out/hires/$slug-$size@2x.png" >/dev/null
  sips -z $H $W "$out/hires/$slug-$size@2x.png" --out "$out/$slug-$size.png" >/dev/null
  rm -f "$raw" "$raw.jpg"
done
"$SKILL/scripts/qa.sh" "$out"
