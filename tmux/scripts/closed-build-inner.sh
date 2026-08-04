#!/bin/sh
# Print the shell command to run inside a reopened pane/window.
# Args: cwd cmd scroll_file [claude_session_id]
# Behavior:
#   - If a Claude session ID was pinned, resume that exact session.
#   - Else if cmd looks like Claude (no pinned ID), fall back to --continue.
#   - Else if scrollback exists, dump it then drop to interactive shell.
#   - Else just drop to interactive shell.
cwd="$1"; cmd="$2"; scroll="$3"; claude_session="$4"
shell="${SHELL:-/bin/zsh}"

if [ -n "$claude_session" ]; then
  printf 'claude --resume %s\n' "$claude_session"
  exit 0
fi

case "$cmd" in
  [0-9]*[._][0-9]*[._][0-9]*)
    printf 'claude --continue\n'
    exit 0
    ;;
esac

if [ -s "$scroll" ]; then
  printf 'printf "\\033[2m── recovered scrollback (cmd was: %%s) ──\\033[0m\\n" "%s"; cat "%s"; printf "\\033[2m── end of recovered scrollback ──\\033[0m\\n"; exec %s\n' "$cmd" "$scroll" "$shell"
else
  printf 'exec %s\n' "$shell"
fi
