#!/bin/sh
# tmux-resurrect post-save hook.
# Snapshots per-pane Claude session IDs to a sidecar so the post-restore hook
# can reattach the EXACT session that was in each pane (not just the most
# recent in cwd). Wired via @resurrect-hook-post-save-all in tmux.conf —
# tmux-resurrect fires only post-save-layout / post-save-all on save (there is
# no pre-save-all hook), so this snapshot must run on post-save-all.
sidecar="$HOME/.tmux/claude-pane-sessions.tsv"
mkdir -p "$HOME/.tmux"
: > "$sidecar"

tmux list-panes -a -F '#{session_name}|#{window_index}|#{pane_index}|#{pane_id}|#{pane_current_path}|#{pane_current_command}' \
  | while IFS='|' read sess widx pidx pid cwd cmd; do
      sid=$(sh "$HOME/.tmux/scripts/closed-claude-session.sh" "$pid" "$cmd")
      if [ -n "$sid" ]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$sess" "$widx" "$pidx" "$cwd" "$sid" >> "$sidecar"
      fi
    done
