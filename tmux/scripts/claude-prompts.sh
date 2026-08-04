#!/usr/bin/env bash
# prefix+h — show the manual prompts you typed in THIS pane's Claude session.
#
# Claude Code owns the data: every session is a JSONL transcript under
# ~/.claude/projects/<proj>/<sessionId>.jsonl. This reads it live — nothing is
# duplicated. The pane→session mapping reuses closed-claude-session.sh (find the
# claude descendant PID, read ~/.claude/sessions/<pid>.json).
#
# Prompts are shown in an fzf popup, oldest→newest, each with its clock time.
# The preview pane shows the full prompt; Enter copies the selected prompt to
# the clipboard; Esc closes.
#
# Args: pane_id  pane_current_command   (passed by the tmux binding)
set -euo pipefail
export PATH="$HOME/.fzf/bin:$HOME/.bin:/opt/homebrew/bin:$PATH"

pane_id="${1:-}"; cmd="${2:-}"
# tmux does NOT format-expand the shell-command in `display-popup -E`, so the
# bind's '#{pane_id}' / '#{pane_current_command}' would arrive as literal text.
# Resolve them from the popup's client instead (args are kept only as a
# standalone/test fallback).
case "$pane_id" in ''|'#{'*) pane_id="$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)";; esac
case "$cmd"     in ''|'#{'*) cmd="$(tmux display-message -p '#{pane_current_command}' 2>/dev/null || true)";; esac
here="$(cd "$(dirname "$0")" && pwd)"

note() { tmux display-message "claude-prompts: $1" 2>/dev/null || printf '%s\n' "$1"; }

# NB: no `… | head` here — under `set -o pipefail` a producer that keeps writing
# after head exits gets SIGPIPE (141), which `set -e` turns into a silent early
# exit (the popup just flashes). Capture fully, then take the first line.
sid="$(sh "$here/closed-claude-session.sh" "$pane_id" "$cmd" 2>/dev/null || true)"; sid="${sid%%$'\n'*}"
[ -n "$sid" ] || { note "no Claude session in this pane"; exit 0; }

transcript="$(find "$HOME/.claude/projects" -name "$sid.jsonl" -type f 2>/dev/null || true)"; transcript="${transcript%%$'\n'*}"
[ -n "$transcript" ] && [ -f "$transcript" ] || { note "no transcript for session ${sid%%-*}…"; exit 0; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

/usr/bin/python3 - "$transcript" "$tmp" <<'PY'
import sys, json, re, os, datetime
src, tmp = sys.argv[1], sys.argv[2]
rows, i = [], 0
for ln in open(src, encoding="utf-8", errors="replace"):
    try: o = json.loads(ln)
    except Exception: continue
    if o.get("type") != "user" or o.get("isMeta"): continue
    if o.get("promptSource") == "system": continue   # task-notifications & other injected turns
    c = o.get("message", {}).get("content")
    if isinstance(c, str):
        txt = c
    elif isinstance(c, list):
        txt = "\n".join(b.get("text", "") for b in c
                        if isinstance(b, dict) and b.get("type") == "text")
    else:
        txt = ""
    if not txt.strip():                       # tool_result-only user turns
        continue
    if "<local-command-stdout>" in txt:       # output of a ! command, not a prompt
        continue
    m = re.search(r"<command-name>(/[^<]+)</command-name>", txt)
    a = re.search(r"<command-args>([^<]*)</command-args>", txt)
    if m:                                      # slash command → "/foo args"
        txt = (m.group(1) + " " + (a.group(1).strip() if a else "")).strip()
    else:
        txt = re.sub(r"<[^>]+>", "", txt).strip()
    if not txt:
        continue
    i += 1
    hhmm = ""
    ts = o.get("timestamp")
    if ts:
        try:
            hhmm = datetime.datetime.fromisoformat(
                ts.replace("Z", "+00:00")).astimezone().strftime("%H:%M")
        except Exception:
            hhmm = ""
    idx = "%03d" % i
    with open(os.path.join(tmp, idx + ".txt"), "w", encoding="utf-8") as fh:
        fh.write(txt)
    oneline = " ".join(txt.split())
    rows.append("%s\t\033[2m%s\033[0m  %s" % (idx, hhmm or "  ·  ", oneline))
with open(os.path.join(tmp, "list.tsv"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows) + ("\n" if rows else ""))
PY

[ -s "$tmp/list.tsv" ] || { note "no manual prompts in this session yet"; exit 0; }

fzf --ansi --no-sort --reverse --delimiter='\t' --with-nth=2.. \
    --prompt='prompts> ' \
    --header="session ${sid%%-*}…  ·  enter: copy to clipboard  ·  esc: close" \
    --preview "cat $tmp/{1}.txt" --preview-window='down,45%,wrap' \
    --bind "enter:execute-silent(pbcopy < $tmp/{1}.txt)+abort" \
    < "$tmp/list.tsv" || true
