#!/usr/bin/env bash
# Status-bar widget: list running Claude sessions as colored state dots.
# Wired into tmux via:  set -g status-right '#(.../statusbar.sh)'
#
# Output uses tmux's own #[...] style codes (NOT raw ANSI) so colours render
# correctly inside status-right. State colours mirror the picker:
#   waiting  -> yellow ●   (needs you: permission / question)
#   idle     -> green  ●   (turn finished, your move)
#   working  -> red    ●   (busy, leave it)
#   unknown  -> grey   ●   (no hook fired yet)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"

# Rows: rank<TAB>dot<TAB>name   (rank hidden, only used for sorting)
emit_rows() {
  local s state dot rank path name
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    state=$(tmux show-options -qv -t "$s" @claude_state 2>/dev/null)
    case "$state" in
      waiting) dot='#[fg=colour3]●#[default]'; rank=0 ;;   # yellow
      idle)    dot='#[fg=colour2]●#[default]'; rank=1 ;;   # green
      working) dot='#[fg=colour1]●#[default]'; rank=3 ;;   # red
      *)       dot='#[fg=colour8]●#[default]'; rank=2 ;;   # grey
    esac
    path=$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)
    name="${path##*/}"                                  # last path component
    [ -z "$name" ] && name="${s#"$prefix"}"
    printf '%s\t%s\t%s\n' "$rank" "$dot" "$name"
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" || true)
}

# Sort by rank (attention-needed first), then emit "dot name  " pairs.
emit_rows | sort -t$'\t' -k1,1n | while IFS=$'\t' read -r _ dot name; do
  printf '%s %s  ' "$dot" "$name"
done
