#!/usr/bin/env bash
# Click callback for the claudetmux:// protocol (registered by install-wsl-notify.sh).
#
# Invoked by Windows when the user clicks the toast's "restore" action:
#   wsl.exe -e bash -lc "<this script> claudetmux://<session>/..."
#
# Pops the target claude session up on the host terminal (mirrors prefix+a) AND
# brings the Windows Terminal window to the foreground so the popup is visible.
#
# The wsl.exe-spawned shell is NOT inside tmux ($TMUX is empty).
#
# NOTE on -c: `tmux display-popup -c <client>` on tmux 3.6b under WSL closes the
# popup instantly when the target client differs from the invoking client. We
# instead set $TMUX to the host client's identity (socket,server-pid,client-pid)
# and call display-popup WITHOUT -c.
#
# NOTE on the wsl.exe console window: toast-action protocol activation can only
# launch wsl.exe directly (hidden launchers like wscript/powershell aren't
# started by toast activation). So wsl.exe gets a brief console window. We fire
# display-popup in the background and exit ASAP so that window only flashes.
#
# Best-effort: logs to /tmp/claude-tmux-restore.log, never blocks the caller.
set -uo pipefail

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> /tmp/claude-tmux-restore.log 2>/dev/null || true; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

url="${1:-}"
# claudetmux://claude-abcd1234/  ->  strip scheme, then strip trailing path
rest="${url#claudetmux://}"
session="${rest%%/*}"

if [ -z "$session" ]; then
  log "no session in url: '$url'"
  exit 0
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  log "session gone: $session"
  exit 0
fi

# Locate the host client's PID (a client not currently showing a claude-* session).
host_pid="$(tmux list-clients -F '#{client_pid} #{session_name}' 2>/dev/null \
            | grep -v ' claude-' | awk '{print $1}' | head -1)"
if [ -z "$host_pid" ]; then
  log "no host client pid for session=$session"
  exit 0
fi

# Rebind the invoking client identity to the host client (see NOTE on -c).
server_pid="$(tmux display-message -p '#{pid}' 2>/dev/null)"
socket="$(tmux display-message -p '#{socket_path}' 2>/dev/null)"
export TMUX="$socket,$server_pid,$host_pid"

# Bring the host terminal window to the foreground so the popup is visible.
# BACKGROUND + delayed: activate-wt.ps1 sleeps ~1.5s so it runs AFTER wsl.exe
# (this process) exits — while wsl.exe runs, Windows Terminal's MainWindowHandle
# points at a wsl.exe-path helper window; after wsl.exe exits it returns to the
# real "Ubuntu-22.04" terminal window. nohup/disown so we don't block on it.
if command -v powershell.exe >/dev/null 2>&1 && [ -f "$DIR/activate-wt.ps1" ]; then
  nohup powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden \
    -File "$(wslpath -w "$DIR/activate-wt.ps1")" >/dev/null 2>&1 &
  disown
fi

# Fire display-popup in the background and exit immediately: the popup is owned
# by the tmux SERVER (bound to the host client), and -E's attach runs in the
# popup pty under the server — neither depends on this process tree, so they
# survive after wsl.exe quits (which makes its console window only flash).
log "popup host_pid=$host_pid -> $session; activating WT"
tmux display-popup -B -w 100% -h 100% -E "tmux attach-session -t '$session'" 2>>/tmp/claude-tmux-restore.log &
disown
sleep 0.5        # let the tmux client deliver the command to the server
log "exited, popup delegated to server"
