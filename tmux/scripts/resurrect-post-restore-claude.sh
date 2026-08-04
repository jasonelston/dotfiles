#!/bin/sh
# tmux-resurrect post-restore hook.
# Reads the sidecar written by resurrect-post-save-claude.sh and reattaches
# the right Claude session in each pane that had one. Wired via
# @resurrect-hook-post-restore-all in tmux.conf.
# Signal the sesh-combined-picker that this restore just churned every
# #{window_id}, so its next run remaps grouping/order by signature. Independent
# of the claude-pane sidecar below, so drop it before that early-exit.
picker_state="${XDG_STATE_HOME:-$HOME/.local/state}/sesh-combined-picker"
[ -d "$picker_state" ] && : > "$picker_state/.restore-pending"

sidecar="$HOME/.tmux/claude-pane-sessions.tsv"
[ ! -s "$sidecar" ] && exit 0

# Give the restored shells a moment to be ready for input.
sleep 1

while IFS="$(printf '\t')" read sess widx pidx cwd sid; do
  [ -z "$sid" ] && continue
  target="${sess}:${widx}.${pidx}"

  # Skip panes that don't exist (resurrect may have dropped them).
  tmux list-panes -t "$target" >/dev/null 2>&1 || continue

  # Skip if Claude's session metadata file no longer exists (rare:
  # session-file deleted between save and restore). We don't fail loudly —
  # the pane just stays at a shell prompt.
  meta_dir="$HOME/.claude/projects/$(printf '%s' "$cwd" | sed 's|[^a-zA-Z0-9]|-|g')"
  if [ -d "$meta_dir" ] && [ ! -f "$meta_dir/$sid.jsonl" ]; then
    continue
  fi

  # Clear any pending shell input, then launch claude with the pinned session.
  tmux send-keys -t "$target" C-u
  tmux send-keys -t "$target" "claude --resume $sid" Enter
done < "$sidecar"
