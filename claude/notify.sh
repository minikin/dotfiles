#!/bin/bash
# Claude Code Notification and Stop hook: a desktop notification titled with the workspace
# dir name (the jj workspace name, or the repo name in the main checkout).
# Hooks have no controlling terminal, so instead of writing to /dev/tty this prints
# {"terminalSequence": ...} and Claude Code emits OSC 777 (Ghostty notification) plus a BEL.
# JW_NOTIFY=print prints "title|body" instead, for tests.
# Never fails: a broken notification must not break the session.

input=$(cat 2>/dev/null)
fields=$(jq -r '
  def clean: gsub("[\n\t\r]"; " ") | gsub("[\u0000-\u001f\u007f]"; "") | gsub(";"; ",");
  (.cwd // "" | tostring | sub("/+$"; "") | split("/") | last // "" | clean),
  (.hook_event_name // "" | tostring | clean),
  (.message // "" | tostring | clean)
' <<<"$input" 2>/dev/null) || fields=''
{ IFS= read -r title; IFS= read -r event; IFS= read -r message; } <<<"$fields"

[[ -n $title ]] || title="Claude Code"
case $event in
  Stop) body="done" ;;
  *) body=${message:-waiting for input} ;;
esac

if [[ ${JW_NOTIFY:-} == print ]]; then
  printf '%s|%s\n' "$title" "$body"
else
  seq=$(printf '\033]777;notify;%s;%s\007\007' "$title" "$body")
  jq -nc --arg seq "$seq" '{terminalSequence: $seq}' 2>/dev/null
fi
exit 0
