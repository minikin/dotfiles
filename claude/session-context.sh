#!/bin/bash
# Claude Code SessionStart hook: tells the agent which jj workspace or git worktree it runs in
# (from where.sh). It runs on startup, resume, clear and compact, so the agent still knows
# after a compaction. Prints nothing outside a repo. Never fails.
# In a workspace or worktree it also titles the session <repo>/<workspace>, like /rename, so the
# tab and /resume show it without jwc. Claude Code applies sessionTitle on startup, resume and
# fork only. A session that already has a title (claude -n, /rename) keeps it.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fields=$(jq -r '(.cwd // "" | gsub("\n"; " ")), (.source // ""), (.session_title // "" | gsub("\n"; " "))' 2>/dev/null) || exit 0
{ IFS= read -r cwd; IFS= read -r source; IFS= read -r title; } <<<"$fields"
[[ -n $cwd ]] || exit 0
where=$("$here/where.sh" "$cwd" 2>/dev/null) || exit 0
{ IFS= read -r repo; IFS= read -r name; IFS= read -r root; IFS= read -r _; IFS= read -r kind; } <<<"$where"

if [[ $kind == jj ]]; then kind="jj workspace"; else kind="git worktree"; fi
if [[ -n $name ]]; then
  ctx="This session runs in the $kind \"$name\" of the repo \"$repo\", rooted at $root. Other agents can work in sibling workspaces of the same repo, so keep reads and edits inside this root. Call this location $repo/$name when you refer to it."
else
  ctx="This session runs in the main checkout of the repo \"$repo\", at $root. Agents in jj workspaces or git worktrees of this repo have their own directories."
fi
set_title=''
[[ -n $name && -z $title && $source =~ ^(startup|resume|fork)$ ]] && set_title=$repo/$name
jq -nc --arg ctx "$ctx" --arg title "$set_title" '{hookSpecificOutput: ({hookEventName: "SessionStart", additionalContext: $ctx}
  + (if $title != "" then {sessionTitle: $title} else {} end))}' 2>/dev/null
exit 0
