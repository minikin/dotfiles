#!/bin/bash
# Claude Code SessionStart hook: tells the agent which jj workspace or git worktree it runs in
# (from where.sh). It runs on startup, resume, clear and compact, so the agent still knows
# after a compaction. Prints nothing outside a repo. Never fails.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cwd=$(jq -r '.cwd // empty' 2>/dev/null) || exit 0
[[ -n $cwd ]] || exit 0
where=$("$here/where.sh" "$cwd" 2>/dev/null) || exit 0
{ IFS= read -r repo; IFS= read -r name; IFS= read -r root; IFS= read -r _; IFS= read -r kind; } <<<"$where"

if [[ $kind == jj ]]; then kind="jj workspace"; else kind="git worktree"; fi
if [[ -n $name ]]; then
  ctx="This session runs in the $kind \"$name\" of the repo \"$repo\", rooted at $root. Other agents can work in sibling workspaces of the same repo, so keep reads and edits inside this root. Call this location $repo/$name when you refer to it."
else
  ctx="This session runs in the main checkout of the repo \"$repo\", at $root. Agents in jj workspaces or git worktrees of this repo have their own directories."
fi
jq -nc --arg ctx "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}' 2>/dev/null
exit 0
