#!/bin/bash
# setup_sims.sh [n_riders] [--fresh]
#   Boots N simulators, installs the app, pre-grants location, arranges windows
#   in Point Accurate mode (so 1 screenshot px == 1 device point), and writes devices.conf.
#   --fresh  erases each sim first (needed to clear cached Google OAuth cookies
#            so you can sign in with a DIFFERENT account -- see reference/troubleshooting.md)
set -e
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
N="${1:-3}"; FRESH=""; [ "$2" = "--fresh" ] && FRESH=1
PROJ="$(cd "$SKD/../../../.." && pwd)"
RT=com.apple.CoreSimulator.SimRuntime.iOS-26-2
APP="$SKD/.build/Build/Products/Debug-iphonesimulator/convotrack.app"

# All devices are iPhone 17-class => identical 402x874 pt geometry => ONE coordinate table.
ROSTER_KEY=(L R2 R3); ROSTER_NAME=("iPhone 17 Pro" "iPhone 17" "Rider3")
ROSTER_MATCH=("iPhone 17 Pro" "iPhone 17 –" "Rider3")

if [ ! -d "$APP" ]; then
  echo "building app (first run only)…"
  xcodebuild -project "$PROJ/convotrack.xcodeproj" -scheme convotrack -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$SKD/.build" build 2>&1 | tail -2
fi

: > "$CONF"
for i in $(seq 0 $((N-1))); do
  K="${ROSTER_KEY[$i]}"; NAME="${ROSTER_NAME[$i]}"
  U=$(xcrun simctl list devices | grep -F "$NAME (" | grep -oE "[0-9A-F-]{36}" | head -1)
  if [ -z "$U" ]; then
    U=$(xcrun simctl create "$NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17 $RT)
    echo "created $NAME"
  fi
  if [ -n "$FRESH" ]; then xcrun simctl shutdown "$U" 2>/dev/null || true; xcrun simctl erase "$U"; echo "erased $NAME"; fi
  xcrun simctl boot "$U" 2>/dev/null || true
  xcrun simctl bootstatus "$U" -b >/dev/null 2>&1
  xcrun simctl install "$U" "$APP"
  xcrun simctl privacy "$U" grant location-always "$BUNDLE_ID"     # no permission dialogs mid-run
  xcrun simctl launch "$U" "$BUNDLE_ID" >/dev/null
  echo "$K|$U|${ROSTER_MATCH[$i]}" >> "$CONF"
  echo "ready: $K = $NAME ($U)"
done
open -a Simulator; sleep 2
"$SKD/arrange_windows.sh" "$N"
echo; echo "devices.conf:"; cat "$CONF"
