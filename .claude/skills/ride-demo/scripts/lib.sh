#!/bin/bash
# Common helpers. Source this from every script: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SKD="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
# Fallback: if that did not land on this file's real directory (can happen when
# lib.sh is sourced from an odd cwd), locate it from the repo root instead.
if [ ! -f "$SKD/lib.sh" ]; then
  _R="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$_R" ] && [ -f "$_R/.claude/skills/ride-demo/scripts/lib.sh" ] \
    && SKD="$_R/.claude/skills/ride-demo/scripts"
fi
CONF="$SKD/devices.conf"
BUNDLE_ID="${BUNDLE_ID:-danglingmind.convotrack}"
CHROME=52          # Simulator window title-bar height in points (Point Accurate mode)

# Build the CGEvent click/drag helpers on first use.
ensure_bins() {
  [ -x "$SKD/tap" ]  || swiftc -O "$SKD/tap.swift"  -o "$SKD/tap"  2>/dev/null
  [ -x "$SKD/drag" ] || swiftc -O "$SKD/drag.swift" -o "$SKD/drag" 2>/dev/null
}

# devices.conf format, one per line:  KEY|UDID|WINDOW_TITLE_MATCH
udid_for()  { awk -F'|' -v k="$1" '$1==k{print $2}' "$CONF"; }
title_for() { awk -F'|' -v k="$1" '$1==k{print $3}' "$CONF"; }
keys()      { awk -F'|' '/^[^#]/{print $1}' "$CONF"; }

# Screen origin of a device window, in macOS points: "X Y"
winpos() {
  local n; n="$(title_for "$1")"
  osascript <<OSA 2>/dev/null
tell application "System Events" to tell process "Simulator"
  try
    set p to position of (first window whose title contains "$n")
    return ((item 1 of p) as string) & " " & (((item 2 of p) + $CHROME) as string)
  end try
end tell
OSA
}
