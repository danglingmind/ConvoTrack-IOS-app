#!/bin/bash
# focus.sh <KEY>  -- raise that device's Simulator window
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
N="$(title_for "$1")"
osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1
osascript -e "tell application \"System Events\" to tell process \"Simulator\"
 repeat with w in windows
  if (title of w) contains \"$N\" then perform action \"AXRaise\" of w
 end repeat
end tell" >/dev/null 2>&1
