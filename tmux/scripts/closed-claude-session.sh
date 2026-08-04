#!/bin/sh
# Resolve the EXACT Claude session ID for a tmux pane.
# Strategy: find the claude descendant process of the pane's shell, then read
# ~/.claude/sessions/<pid>.json (which Claude maintains per-process).
# This works even when multiple claude panes share the same cwd.
#
# Args: pane_id cmd
# Output: session UUID, or empty if not Claude / no session file found.
pane_id="$1"; cmd="$2"

# Quick filter: only proceed if cmd looks like Claude (version string;
# the separator changed from . to _ in Claude Code 2.1.2xx)
case "$cmd" in
  [0-9]*[._][0-9]*[._][0-9]*) ;;
  *) exit 0 ;;
esac

pane_pid=$(tmux display-message -p -t "$pane_id" '#{pane_pid}' 2>/dev/null)
[ -z "$pane_pid" ] && exit 0

# Build a list of all descendant PIDs of pane_pid (BFS up to 3 levels deep).
# Using `ps -eo pid,ppid` rather than `pgrep -P` (which is unreliable on macOS).
all_procs=$(ps -eo pid=,ppid= 2>/dev/null)
descendants_of() {
  parent="$1"
  printf '%s\n' "$all_procs" | awk -v p="$parent" '$2==p{print $1}'
}

candidates="$pane_pid"
frontier="$pane_pid"
for _depth in 1 2 3; do
  next=""
  for cpid in $frontier; do
    kids=$(descendants_of "$cpid")
    next="$next $kids"
    candidates="$candidates $kids"
  done
  [ -z "$(echo $next | tr -d ' ')" ] && break
  frontier="$next"
done

for pid in $candidates; do
  [ -z "$pid" ] && continue
  meta="$HOME/.claude/sessions/$pid.json"
  if [ -f "$meta" ]; then
    sid=$(sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$meta" | head -n 1)
    if [ -n "$sid" ]; then
      printf '%s\n' "$sid"
      exit 0
    fi
  fi
done

exit 0
