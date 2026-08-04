#!/bin/sh
# Capture a whole window's state (all panes + layout) before killing (prefix+&).
# Args: sess win_index   (index, not name — names aren't unique; see tmux.conf)
sess="$1"; win="$2"
# Unique per close event: whole-second timestamp alone collides when two windows
# are closed in the same second (closed-pick keys rows by field 1), so suffix the
# script PID. Each prefix+& spawns a fresh sh, so $$ disambiguates same-second closes.
ts="$(date +%s)-$$"

mkdir -p "$HOME/.tmux/snapshots" "$HOME/.tmux/scrollbacks"
snapshot="$HOME/.tmux/snapshots/${ts}.tsv"

layout=$(tmux display-message -p -t "${sess}:${win}" '#{window_layout}')
window_name=$(tmux display-message -p -t "${sess}:${win}" '#{window_name}')

printf 'LAYOUT\t%s\n' "$layout" > "$snapshot"
printf 'WINDOW_NAME\t%s\n' "$window_name" >> "$snapshot"

# One PANE row per pane (pane_index order)
# Columns: PANE cwd cmd scroll claude_session
tmux list-panes -t "${sess}:${win}" -F '#{pane_index}|#{pane_id}|#{pane_current_path}|#{pane_current_command}' \
  | sort -n -t'|' -k1 \
  | while IFS='|' read pidx pid pcwd pcmd; do
      pscroll="$HOME/.tmux/scrollbacks/${ts}-${pid#%}.txt"
      tmux capture-pane -p -S -3000 -t "$pid" > "$pscroll" 2>/dev/null
      psession=$(sh "$HOME/.tmux/scripts/closed-claude-session.sh" "$pid" "$pcmd")
      printf 'PANE\t%s\t%s\t%s\t%s\n' "$pcwd" "$pcmd" "$pscroll" "$psession" >> "$snapshot"
    done

first_cwd=$(awk -F'\t' '$1=="PANE"{print $2; exit}' "$snapshot")
first_cmd=$(awk -F'\t' '$1=="PANE"{print $3; exit}' "$snapshot")

# Main log entry — kind=window, snapshot points to per-pane file.
# Store window_name (not the index) in the name field: it drives the fzf-picker
# display and the reopened window's name. Reopen reads the name from the snapshot
# (WINDOW_NAME row), so this is for display/parity. Targeting above used the index.
# claude_session field left blank (per-pane sessions live in snapshot).
printf '%s\topen\twindow\t%s\t%s\t%s\t%s\t\t%s\t\n' \
  "$ts" "$sess" "$window_name" "$first_cwd" "$first_cmd" "$snapshot" \
  >> "$HOME/.tmux-closed.log"

tail -n 500 "$HOME/.tmux-closed.log" > "$HOME/.tmux-closed.log.tmp" \
  && mv "$HOME/.tmux-closed.log.tmp" "$HOME/.tmux-closed.log"
find "$HOME/.tmux/snapshots" -name '*.tsv' -mtime +7 -delete 2>/dev/null

tmux kill-window -t "${sess}:${win}"
