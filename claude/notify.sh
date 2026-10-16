#!/bin/bash
# Claude Code Notification and Stop hook: a desktop notification titled repo/workspace (from
# where.sh), the repo name in the main checkout, or the dir name outside a repo.
# Hooks have no controlling terminal, so instead of writing to /dev/tty this prints
# {"terminalSequence": ...} and Claude Code emits OSC 777 (Ghostty notification) plus a BEL.
# JW_NOTIFY=print prints "title|body" instead, for tests.
# Never fails: a broken notification must not break the session.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
input=$(cat 2>/dev/null)
fields=$(jq -r '
  def clean: gsub("[\n\t\r]"; " ") | gsub("[\u0000-\u001f\u007f]"; "") | gsub(";"; ",");
  (.cwd // "" | tostring | gsub("[\n\r]"; " ")),
  (.hook_event_name // "" | tostring | clean),
  (.message // "" | tostring | clean)
' <<<"$input" 2>/dev/null) || fields=''
{ IFS= read -r cwd; IFS= read -r event; IFS= read -r message; } <<<"$fields"

if [[ -n $cwd ]] && where=$("$here/where.sh" "$cwd" 2>/dev/null); then
  { IFS= read -r repo; IFS= read -r name; } <<<"$where"
  title=$repo${name:+/$name}
else
  title=${cwd%"${cwd##*[!/]}"}   # strip trailing slashes
  title=${title##*/}
fi
title=$(printf '%s' "$title" | tr -d '\000-\037\177' | tr ';' ',')

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
