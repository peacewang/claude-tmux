#!/usr/bin/env bash
# Fire a desktop notification from WSL. Best-effort: never fails the caller.
# Usage: notify.sh <summary> [body]
#
# Dispatcher (first that works wins):
#   1. wsl-notify-send.exe  — native Windows toast, no D-Bus needed (preferred)
#   2. notify-send          — Linux route, only if a D-Bus notification daemon runs
#   3. terminal bell \a     — last resort; flashes taskbar if terminal is set to
set -uo pipefail

summary="${1:-Claude}"
body="${2:-}"
if [ -n "$body" ]; then msg="$summary  $body"; else msg="$summary"; fi

# 1) wsl-notify-send.exe (check PATH, then ~/bin for hook contexts w/o full PATH)
wns=""
if command -v wsl-notify-send.exe >/dev/null 2>&1; then
  wns="wsl-notify-send.exe"
elif [ -x "$HOME/bin/wsl-notify-send.exe" ]; then
  wns="$HOME/bin/wsl-notify-send.exe"
fi
if [ -n "$wns" ]; then
  "$wns" --category claude-manager "$msg" >/dev/null 2>&1 && exit 0
fi

# 2) Linux notify-send (needs a running D-Bus notification daemon)
if command -v notify-send >/dev/null 2>&1; then
  notify-send "$summary" "$body" >/dev/null 2>&1 && exit 0
fi

# 3) Terminal bell
printf '\a'
