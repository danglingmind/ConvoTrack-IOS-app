#!/bin/zsh
# qa.sh <dir> — verifies every <slug>-<size>.png: exact pixel size, no alpha, < 30 MB (Meta limit).
setopt null_glob
dir="$1"; ok=1
for f in "$dir"/*-feed.png "$dir"/*-square.png "$dir"/*-story.png; do
  [[ -f "$f" ]] || continue
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}'); h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
  a=$(sips -g hasAlpha "$f" | awk '/hasAlpha/{print $2}'); kb=$(( $(stat -f%z "$f") / 1024 ))
  case "$f" in *-feed.png) ew=1080; eh=1350;; *-square.png) ew=1080; eh=1080;; *-story.png) ew=1080; eh=1920;; esac
  s="ok"; [[ "$w" != "$ew" || "$h" != "$eh" ]] && { s="WRONG SIZE"; ok=0; }
  [[ "$a" != "no" ]] && { s="$s HAS ALPHA"; ok=0; }; (( kb > 30000 )) && { s="$s TOO BIG"; ok=0; }
  printf "%-34s %sx%s alpha=%s %sKB  %s\n" "${f:t}" "$w" "$h" "$a" "$kb" "$s"
done
(( ok )) || exit 1
