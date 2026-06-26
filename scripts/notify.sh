#!/usr/bin/env bash
# Fire a desktop notification. Best-effort: never fails the caller.
# Usage: notify.sh <summary> [body] [session]
#
# Dispatcher (first that works wins):
#   1. powershell.exe + notify.ps1  — WSL native toast, click-to-restore (recommended)
#   2. wsl-notify-send.exe          — WSL toast fallback (no click action)
#   3. terminal-notifier            — macOS native, -activate iTerm2 + -sound (recommended)
#   4. osascript                    — macOS built-in fallback (no extra install)
#   5. notify-send                  — Linux route, only if a D-Bus notification daemon runs
#   6. terminal bell \a             — last resort
set -uo pipefail

summary="${1:-Claude}"
body="${2:-}"
session="${3:-}"                                        # tmux session name (for click-to-attach)
if [ -n "$body" ]; then msg="$summary  $body"; else msg="$summary"; fi
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# XML-escape &, <, > so project names / bodies with these stay well-formed.
xml_escape() {
  local s="${1}"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# 1) PowerShell native toast (WSL) — app name "claude-tmux", click-to-restore.
#    Chinese/emoji live in a UTF-8 XML temp file; notify.ps1 reads it with
#    -Encoding UTF8 so PowerShell 5.1 decodes it correctly on zh-CN Windows.
#    Falls through to wsl-notify-send if PowerShell or notify.ps1 is missing.
if command -v powershell.exe >/dev/null 2>&1 && [ -f "$DIR/notify.ps1" ]; then
  tmp_xml="$(mktemp /tmp/claude-tmux-toast.XXXXXX.xml)"
  esc_sum="$(xml_escape "$summary")"
  esc_body="$(xml_escape "$body")"
  if [ -n "$session" ]; then
    url="claudetmux://$(xml_escape "$session")"
    toast_open="<toast duration=\"long\" activationType=\"protocol\" launch=\"$url\">"
    actions_block="  <actions>
    <action activationType=\"protocol\" arguments=\"$url\" content=\"恢复会话\"/>
  </actions>"
  else
    toast_open="<toast duration=\"long\">"
    actions_block=""
  fi
  {
    printf '%s\n' "$toast_open"
    printf '  <visual>\n'
    printf '    <binding template="ToastGeneric">\n'
    printf '      <text>claude-tmux</text>\n'
    printf '      <text>%s</text>\n' "$esc_sum"
    [ -n "$esc_body" ] && printf '      <text>%s</text>\n' "$esc_body"
    printf '    </binding>\n'
    printf '  </visual>\n'
    [ -n "$actions_block" ] && printf '%s\n' "$actions_block"
    printf '</toast>\n'
  } > "$tmp_xml"
  if powershell.exe -NoProfile -ExecutionPolicy Bypass \
       -File "$(wslpath -w "$DIR/notify.ps1")" \
       -XmlPath "$(wslpath -w "$tmp_xml")" >/dev/null 2>&1; then
    rm -f "$tmp_xml"
    exit 0
  fi
  rm -f "$tmp_xml"
fi

# 2) wsl-notify-send.exe (check PATH, then ~/bin for hook contexts w/o full PATH)
wns=""
if command -v wsl-notify-send.exe >/dev/null 2>&1; then
  wns="wsl-notify-send.exe"
elif [ -x "$HOME/bin/wsl-notify-send.exe" ]; then
  wns="$HOME/bin/wsl-notify-send.exe"
fi
if [ -n "$wns" ]; then
  "$wns" --appId claude-tmux --category claude-tmux "$msg" >/dev/null 2>&1 && exit 0
fi

# 3) macOS terminal-notifier — click restores the popup on the host client
if command -v terminal-notifier >/dev/null 2>&1; then
  if [ -n "$session" ] && command -v osascript >/dev/null 2>&1; then
    # Write a one-shot bash script: activate iTerm2, find host client, display popup
    tmp_sh=$(mktemp /tmp/claude-tmux-notify.XXXXXX.sh)
    cat > "$tmp_sh" << SHEOF
#!/bin/bash
osascript -e 'tell application "iTerm2" to activate'
client=\$(/usr/local/bin/tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null | grep -v 'claude-' | head -1 | awk '{print \$1}')
if [ -n "\$client" ]; then
  /usr/local/bin/tmux display-popup -c "\$client" -B -w 100% -h 100% -E '/usr/local/bin/tmux attach-session -t ${session}'
fi
SHEOF
    chmod +x "$tmp_sh"
    terminal-notifier -title "$summary" -message "$body" \
      -activate com.googlecode.iterm2 -sound default \
      -execute "bash \"$tmp_sh\" ; rm -f \"$tmp_sh\"" >/dev/null 2>&1 && exit 0
    rm -f "$tmp_sh" 2>/dev/null
  fi
  terminal-notifier -title "$summary" -message "$body" \
    -activate com.googlecode.iterm2 -sound default >/dev/null 2>&1 && exit 0
fi

# 4) macOS osascript — built-in fallback, no extra install
if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$body\" with title \"$summary\"" >/dev/null 2>&1 && exit 0
fi

# 5) Linux notify-send (needs a running D-Bus notification daemon)
if command -v notify-send >/dev/null 2>&1; then
  notify-send "$summary" "$body" >/dev/null 2>&1 && exit 0
fi

# 6) Terminal bell
printf '\a'
