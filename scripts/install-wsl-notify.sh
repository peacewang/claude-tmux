#!/usr/bin/env bash
# One-shot installer for the WSL click-to-restore toast integration.
#
# Registers the claudetmux:// URL protocol (HKCU, no admin) so that clicking
# a toast notification launches restore.sh in WSL and attaches the target
# claude session as a popup on the host client.
#
# Run once:  bash scripts/install-wsl-notify.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) powershell.exe must be reachable from WSL (Windows PowerShell 5.1 is fine).
if ! command -v powershell.exe >/dev/null 2>&1; then
  echo "powershell.exe not found in PATH — not on WSL, or Windows PowerShell missing." >&2
  exit 1
fi

# 2) Absolute WSL path to restore.sh (lives in the same dir as this script).
restore_path="$(cd "$DIR" && pwd)/restore.sh"
if [ ! -f "$restore_path" ]; then
  echo "restore.sh not found next to this installer: $restore_path" >&2
  exit 1
fi

# 3) Register the protocol. register-protocol.ps1 is pure ASCII.
ps1="$(wslpath -w "$DIR/register-protocol.ps1")"
echo "Registering claudetmux:// -> $restore_path"
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$ps1" -RestoreScriptPath "$restore_path"

cat <<EOF

Done. Toast notifications now:
  - show app name "claude-tmux"
  - stay ~25s (duration=long), then land in Action Center (still clickable)
  - have a "restore" button that pops the target claude session on your host terminal

Test it from inside tmux:
  $DIR/notify.sh "myproject" "needs your input" claude-<session-name>

Re-run this script any time you move the repo (the registered path points here).
Uninstall: remove HKCU\Software\Classes\claudetmux (reg delete ... /f).
EOF
