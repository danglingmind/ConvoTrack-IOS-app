#!/bin/zsh
# render.sh <out.png> <shot.png> <bg.png> "<line1>" "<line2>" [extra query, e.g. "v=b&chipk=..."]  -> 1290x2796 RGB PNG
set -e; P=${0:A:h}
enc(){ python3 -I -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
url="file://$P/template.html?shot=$(enc file://${2:A})&bg=$(enc file://${3:A})&logo=$(enc file://$P/../ride-walkthrough/logo.png)&l1=$(enc "$4")&l2=$(enc "$5")&${6:-v=a}"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=1290,2796 --force-device-scale-factor=1 --default-background-color=FF090B0D --virtual-time-budget=4000 --screenshot=$P/.raw.png "$url" >/dev/null 2>&1
sips -s format jpeg -s formatOptions 95 $P/.raw.png --out $P/.raw.jpg >/dev/null; sips -s format png $P/.raw.jpg --out "$1" >/dev/null; rm $P/.raw.png $P/.raw.jpg
