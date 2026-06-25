#!/usr/bin/env bash
# Fire a desktop notification. Best-effort: never fails the caller.
# Usage: notify.sh <summary> [body]
#
# Dispatcher (first that works wins):
#   1. wsl-notify-send.exe  — Windows toast, no D-Bus needed (WSL)
#   2. terminal-notifier    — macOS native, -activate iTerm2 + -sound (recommended)
#   3. osascript            — macOS built-in fallback (no extra install)
#   4. notify-send          — Linux route, only if a D-Bus notification daemon runs
#   5. terminal bell \a     — last resort
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

# 2) macOS terminal-notifier — click activates iTerm2, -sound makes it unmissable
if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier -title "$summary" -message "$body" \
    -activate com.googlecode.iterm2 -sound default >/dev/null 2>&1 && exit 0
fi

# 3) macOS osascript — built-in fallback, no extra install
if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$body\" with title \"$summary\"" >/dev/null 2>&1 && exit 0
fi

# 4) Linux notify-send (needs a running D-Bus notification daemon)
if command -v notify-send >/dev/null 2>&1; then
  notify-send "$summary" "$body" >/dev/null 2>&1 && exit 0
fi

# 5) Terminal bell
printf '\a'
