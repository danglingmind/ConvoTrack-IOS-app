#!/bin/zsh
# Renders header.html to App Store product page header PNGs (21:9, 3840x1646, no alpha).
set -e
cd "${0:A:h}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for variant in text clean; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1920,823 --force-device-scale-factor=2 \
    --default-background-color=FF060C12 \
    --screenshot="$PWD/header-$variant.raw.png" "file://$PWD/header.html#$variant" >/dev/null 2>&1
  # Flatten to RGB (Apple rejects alpha channels) and enforce exact size.
  sips -s format jpeg -s formatOptions 100 "header-$variant.raw.png" --out "header-$variant.tmp.jpg" >/dev/null
  sips -s format png "header-$variant.tmp.jpg" --out "header-$variant.png" >/dev/null
  rm "header-$variant.raw.png" "header-$variant.tmp.jpg"
  sips -g pixelWidth -g pixelHeight -g hasAlpha "header-$variant.png" | tail -3
done
