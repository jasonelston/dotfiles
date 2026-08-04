#!/bin/sh
# Pop the next "open" entry off the close-stack (prefix+t).
log="$HOME/.tmux-closed.log"
build="$HOME/.tmux/scripts/closed-build-inner.sh"

if [ ! -s "$log" ]; then
  tmux display-message "no closed panes in history"
  exit 0
fi

target_lineno=$(awk -F'\t' '$2=="open"{ln=NR} END{print ln+0}' "$log")
if [ "$target_lineno" = "0" ]; then
  tmux display-message "no more closed panes to restore (stack empty)"
  exit 0
fi

line=$(sed -n "${target_lineno}p" "$log")
kind=$(printf '%s' "$line"           | cut -f3)
win=$(printf '%s' "$line"            | cut -f5)
cwd=$(printf '%s' "$line"            | cut -f6)
cmd=$(printf '%s' "$line"            | cut -f7)
scroll=$(printf '%s' "$line"         | cut -f8)
snapshot=$(printf '%s' "$line"       | cut -f9)
claude_session=$(printf '%s' "$line" | cut -f10)

# Mark as reopened (walk-back semantics)
awk -F'\t' -v ln="$target_lineno" 'BEGIN{OFS=FS} NR==ln{$2="reopened"} {print}' "$log" \
  > "${log}.tmp" && mv "${log}.tmp" "$log"

if [ -n "$snapshot" ] && [ -s "$snapshot" ]; then
  layout=$(awk -F'\t' '$1=="LAYOUT"{print $2; exit}' "$snapshot")
  window_name=$(awk -F'\t' '$1=="WINDOW_NAME"{print $2; exit}' "$snapshot")

  pane_file=$(mktemp)
  awk -F'\t' '$1=="PANE"{printf "%s\t%s\t%s\t%s\n", $2, $3, $4, $5}' "$snapshot" > "$pane_file"

  win_id=""
  while IFS="$(printf '\t')" read pcwd pcmd pscroll psession; do
    inner=$(sh "$build" "$pcwd" "$pcmd" "$pscroll" "$psession")
    if [ -z "$win_id" ]; then
      win_id=$(tmux new-window -P -F '#{window_id}' -n "$window_name" -c "$pcwd" "$inner")
    else
      tmux split-window -t "$win_id" -c "$pcwd" "$inner"
    fi
  done < "$pane_file"
  rm -f "$pane_file"

  if [ -n "$layout" ] && [ -n "$win_id" ]; then
    tmux select-layout -t "$win_id" "$layout" 2>/dev/null
  fi
else
  inner=$(sh "$build" "$cwd" "$cmd" "$scroll" "$claude_session")
  if [ "$kind" = "window" ]; then
    tmux new-window -n "$win" -c "$cwd" "$inner"
  else
    tmux split-window -c "$cwd" "$inner"
  fi
fi
