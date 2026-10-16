#!/bin/bash
# Claude Code PreToolUse hook (matcher Bash): agents in a jj workspace or git worktree must not push.
# Exit 2 blocks the tool call and Claude Code shows stderr to Claude.
# where.sh decides: a non-empty workspace name means a jj workspace or a git worktree, also
# Claude Code's own .claude/worktrees/<name>. The main checkout and non-repo dirs may push.
# The match is a plain regex on the command line. Global options between the words count
# (git -C dir push, jj -R . git push), `echo git push` is blocked too, and a push hidden in a
# script is not caught here: the pre-push hook jw installs catches git ones.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
input=$(cat 2>/dev/null)
fields=$(jq -r '(.cwd // "" | tostring | gsub("\n"; " ")), (.tool_input.command // "" | tostring | gsub("\n"; ";"))' \
  <<<"$input" 2>/dev/null) || exit 0
{ IFS= read -r cwd; IFS= read -r cmd; } <<<"$fields"

opts='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'   # -C dir, --no-pager
push_re="(^|[;&|[:space:]])(jj${opts}[[:space:]]+git|git)${opts}[[:space:]]+push([[:space:]]|\$)"
[[ $cmd =~ $push_re ]] || exit 0

[[ -n $cwd ]] && where=$("$here/where.sh" "$cwd" 2>/dev/null) || exit 0
{ IFS= read -r _; IFS= read -r name; } <<<"$where"
if [[ -n $name ]]; then
  echo "blocked: agents in jj workspaces and git worktrees do not push; the user pushes from the main checkout with jpush/jland" >&2
  exit 2
fi
exit 0
