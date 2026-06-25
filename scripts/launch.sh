#!/usr/bin/env bash
# Launch (or re-attach to) a Claude session for a directory, shown in a popup.
# Args: <dir> [origin-window-id]   (both expanded by run-shell in the binding)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

path="${1:-$PWD}"
window="${2:-}"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
cmd="$(get_tmux_option @claude_command 'claude')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

session="${prefix}$(session_hash "$path")"

if [[ "$(tmux display-message -p '#S')" == "$prefix"* ]]; then
  tmux display-message '🫪 Popup window already open'
  exit 0
fi

# Inherit the provider env (ANTHROPIC_*, CLAUDE_PROVIDER) from the session that
# owns the launching window — i.e. the terminal where `sp` was run. Mirrored onto
# tmux sessions by ~/.claude/switch-provider.sh (the `sp` command). We inject these
# INLINE so claude reads them at process start (creating the session and setting
# env afterwards would be too late).
provider_args=()
if [ -n "$window" ]; then
  origin_session="$(tmux display-message -t "$window" -p '#{session_name}' 2>/dev/null)" || origin_session=""
  if [ -n "$origin_session" ]; then
    for v in ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL \
             ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
             ANTHROPIC_DEFAULT_OPUS_MODEL CLAUDE_PROVIDER; do
      line="$(tmux show-environment -t "$origin_session" "$v" 2>/dev/null)" || continue
      case "$line" in
        *=*) provider_args+=("$v=${line#*=}") ;;   # set: "VAR=value"
        # "-VAR" (unset) or anything else: skip -> simply absent in the new session
      esac
    done
  fi
fi

# Only a freshly created session starts claude; an existing one keeps whatever
# provider it was first launched with (shared-per-directory behaviour).
if ! tmux has-session -t "$session" 2>/dev/null; then
  if [ "${#provider_args[@]}" -gt 0 ]; then
    env_prefix=""
    for a in "${provider_args[@]}"; do
      env_prefix+=" $(printf '%q' "$a")"   # %q safely quotes token values
    done
    tmux new-session -d -s "$session" -c "$path" "env${env_prefix} $cmd"
  else
    tmux new-session -d -s "$session" -c "$path" "$cmd"
  fi
fi

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

# The popup attaches to this session; turn its status line OFF so the popup
# doesn't draw a second status bar (the host client's bar already shows the
# claude dots). Keeps the popup clean: full coverage, one status bar.
tmux set-option -t "$session" status off

# -B = borderless; w/h 100% fills the pane area (host status bar stays visible below).
tmux display-popup -B -w "$w" -h "$h" -E "tmux attach-session -t $session"
