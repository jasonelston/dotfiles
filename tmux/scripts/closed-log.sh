#!/bin/sh
# Log a pane's state before killing it (prefix+x).
# Args: sess win cwd cmd pane_id window_panes
# Unique per close event: a whole-second timestamp collides when two panes are
# closed in the same second (closed-pick keys rows by field 1, so a collision
# would mark every same-second row reopened). Suffix the script PID — each
# prefix+x spawns a fresh sh, so $$ disambiguates same-second closes.
ts="$(date +%s)-$$"
sess="$1"; win="$2"; cwd="$3"; cmd="$4"; pane_id="$5"; window_panes="$6"

mkdir -p "$HOME/.tmux/scrollbacks"

if [ "$window_panes" = "1" ]; then kind="window"; else kind="pane"; fi

scroll="$HOME/.tmux/scrollbacks/${ts}-${pane_id#%}.txt"
tmux capture-pane -p -S -3000 -t "$pane_id" > "$scroll" 2>/dev/null

# Pin the specific Claude session that was in this pane (if any).
claude_session=$(sh "$HOME/.tmux/scripts/closed-claude-session.sh" "$pane_id" "$cmd")

# Format (TSV): ts status kind sess win cwd cmd scroll snapshot claude_session
printf '%s\topen\t%s\t%s\t%s\t%s\t%s\t%s\t\t%s\n' \
  "$ts" "$kind" "$sess" "$win" "$cwd" "$cmd" "$scroll" "$claude_session" \
  >> "$HOME/.tmux-closed.log"

tail -n 500 "$HOME/.tmux-closed.log" > "$HOME/.tmux-closed.log.tmp" \
  && mv "$HOME/.tmux-closed.log.tmp" "$HOME/.tmux-closed.log"
find "$HOME/.tmux/scrollbacks" -name '*.txt' -mtime +7 -delete 2>/dev/null
