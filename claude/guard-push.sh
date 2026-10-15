#!/bin/bash
# Claude Code PreToolUse hook (matcher Bash): agents in a jj workspace must not push.
# Exit 2 blocks the tool call and Claude Code shows stderr to Claude.
# A workspace is a dir whose .jj/repo is a file pointing at the main checkout's store.
# The main checkout (.jj/repo is a dir) and non-jj dirs may push.
# The match is a plain regex on the command line, so `echo git push` is blocked too, and
# `git -C dir push` or a push hidden in a script is not caught.

input=$(cat 2>/dev/null)
fields=$(jq -r '(.cwd // "" | tostring | gsub("\n"; " ")), (.tool_input.command // "" | tostring | gsub("\n"; ";"))' \
  <<<"$input" 2>/dev/null) || exit 0
{ IFS= read -r cwd; IFS= read -r cmd; } <<<"$fields"

push_re='(^|[;&|[:space:]])(jj[[:space:]]+git|git)[[:space:]]+push([[:space:]]|$)'
[[ $cmd =~ $push_re ]] || exit 0

d=$cwd
while [[ -n $d && ! -e $d/.jj ]]; do
  [[ $d == */* ]] || break
  d=${d%/*}
done
if [[ -n $d && -f $d/.jj/repo ]]; then
  echo "blocked: agents in jj workspaces do not push; the user pushes from the main checkout with jpush/jland" >&2
  exit 2
fi
exit 0
