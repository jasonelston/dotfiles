#!/bin/sh
# fzf picker over the full close history (prefix+R).
log="$HOME/.tmux-closed.log"
build="$HOME/.tmux/scripts/closed-build-inner.sh"

if [ ! -s "$log" ]; then
  tmux display-message "no closed panes in history"
  exit 0
fi

pick=$(tail -r "$log" | awk -F'\t' '
  {
    cmd = ($7 == "" ? "<shell>" : $7)
    tag = "[" substr($2,1,4) "/" $3 "]"
    sid = ($10 == "" ? "" : " (claude:" substr($10,1,8) ")")
    printf "%s\t%s\t%s/%s\t%s%s\t%s\n", $1, tag, $4, $5, cmd, sid, $6
  }' | fzf-tmux -p 85% --with-nth=2..5 --delimiter='\t' \
       --header='reopen closed pane/window (esc cancels)')
[ -z "$pick" ] && exit 0

ts=$(printf '%s' "$pick" | cut -f1)
orig=$(awk -F'\t' -v ts="$ts" '$1 == ts' "$log" | tail -n 1)
kind=$(printf '%s' "$orig"           | cut -f3)
win=$(printf '%s' "$orig"            | cut -f5)
cwd=$(printf '%s' "$orig"            | cut -f6)
cmd=$(printf '%s' "$orig"            | cut -f7)
scroll=$(printf '%s' "$orig"         | cut -f8)
snapshot=$(printf '%s' "$orig"       | cut -f9)
claude_session=$(printf '%s' "$orig" | cut -f10)

awk -F'\t' -v ts="$ts" 'BEGIN{OFS=FS} $1==ts{$2="reopened"} {print}' "$log" \
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
