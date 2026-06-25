#!/usr/bin/env bash
# Record a Claude Code session's state on its tmux session, for the picker.
# Wire this into Claude Code hooks (see README):  state.sh <working|waiting|idle>
#
# Claude Code hooks inherit the Claude process environment, so $TMUX_PANE is set
# whenever Claude runs inside tmux. Outside tmux this is a no-op.
#
# Additionally fires a desktop toast (via notify.sh) when the session transitions
# to a "needs you" state — but ONLY if no client is currently viewing the session
# (session_attached == 0), so a session you're actively in never spams you.
[ -z "$TMUX_PANE" ] && exit 0

session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
[ -z "$session" ] && exit 0

new="${1:-idle}"
old=$(tmux show-options -qv -t "$session" @claude_state 2>/dev/null)

tmux set-option -t "$session" @claude_state "$new"
tmux set-option -t "$session" @claude_state_at "$(date +%s)"

# --- Decide whether this transition warrants a push notification -----------
#   waiting                 -> always (permission/question can't be missed)
#   working -> idle         -> just finished a chunk (other idle transitions
#                              are suppressed to avoid noise on repeated Stop)
#   anything else           -> silent
notify=0
case "$new" in
  waiting) notify=1 ;;
  idle)    [ "$old" = working ] && notify=1 ;;
esac
[ "$notify" = 1 ] || exit 0

# --- Gate: skip if a client is currently viewing this session --------------
# (popup open / attached == you're in it; the TUI already shows the prompt)
attached=$(tmux display-message -p -t "$session" '#{session_attached}' 2>/dev/null)
[ "${attached:-0}" -gt 0 ] && exit 0

# --- Compose message and fire (best-effort, never block the hook) ----------
path=$(tmux display-message -p -t "$session" '#{pane_current_path}' 2>/dev/null)
name="${path##*/}"
[ -z "$name" ] && name="${session#claude-}"

case "$new" in
  waiting) title="$name"       body="需要你的输入" ;;
  idle)    title="$name"       body="本轮已完成" ;;
  *)       title="Claude Code" body="$name" ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Best-effort — errors swallowed, never block on failure.
# NOTE: WSL wsl-notify-send.exe may mangle non-ASCII on non-UTF-8 Windows locale;
#       macOS terminal-notifier / osascript handle UTF-8 natively.
"$DIR/notify.sh" "$title" "$body" "$session" >/dev/null 2>&1
exit 0
