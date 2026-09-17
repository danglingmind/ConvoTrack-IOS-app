#!/bin/bash
# arrange_windows.sh  -- bezels OFF + Point Accurate + tile side by side.
# Point Accurate makes window content exactly 402x874 pt, which is what makes
# screenshot pixels == tap coordinates. Re-run after any reboot: origins move.
#
# NOTE: two passes on purpose. `repeat with w in windows` yields INDEX-based
# references, so AXRaise reorders the list and a later `set position of w` would
# move the wrong window. Menu items act on the frontmost window (needs raising),
# so raise+menu first, then position by title in a second pass.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
XS=(15 425 835)

for K in $(keys); do
  T="$(title_for "$K")"
  osascript <<OSA >/dev/null 2>&1
tell application "Simulator" to activate
delay 0.2
tell application "System Events" to tell process "Simulator"
  set tgt to first window whose title contains "$T"
  perform action "AXRaise" of tgt
  delay 0.4
  set wm to menu 1 of menu bar item "Window" of menu bar 1
  if (value of attribute "AXMenuItemMarkChar" of menu item "Show Device Bezels" of wm) as string is "✓" then
    click menu item "Show Device Bezels" of wm
    delay 0.25
  end if
  click menu item "Point Accurate" of wm
  delay 0.35
end tell
OSA
done

i=0
for K in $(keys); do
  T="$(title_for "$K")"; X=${XS[$i]}
  osascript -e "tell application \"System Events\" to tell process \"Simulator\" to set position of (first window whose title contains \"$T\") to {$X, 40}" >/dev/null 2>&1
  i=$((i+1))
done
sleep 0.5
for K in $(keys); do echo "  $K origin=$(winpos "$K")  size=$(osascript -e "tell application \"System Events\" to tell process \"Simulator\" to get size of (first window whose title contains \"$(title_for "$K")\")" 2>/dev/null)"; done
