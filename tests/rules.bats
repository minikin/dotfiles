#!/usr/bin/env bats
# agents/AGENTS.md and the files that load it: claude/CLAUDE.md, agy/GEMINI.md, ~/.codex/AGENTS.md.

load helpers

setup() {
  fake_home
}

SHARED() { echo "$REPO_ROOT/agents/AGENTS.md"; }
MARKER='Shared rules marker: agents-rules-3f9c2a71'

@test "rules: the shared file carries its marker exactly once" {
  run grep -c -F "$MARKER" "$(SHARED)"
  [ "$output" = "1" ]
}

@test "rules: no other rule file carries the marker, so a retained copy cannot fake the import check" {
  local f
  for f in "$REPO_ROOT"/claude/*.md "$REPO_ROOT"/agy/*.md "$REPO_ROOT"/CLAUDE.md; do
    [[ -f $f ]] || continue
    ! grep -q -F "$MARKER" "$f" || false
  done
}

@test "rules: the shared file names no tool-only feature outside the Codex section" {
  run sed '/^## Codex only/,$d' "$(SHARED)"
  [[ $output != *AskUserQuestion* ]] || false
  [[ $output != *'@['* ]] || false
}

@test "rules: the shared file stays under Codex's 32 KiB project doc limit" {
  local size
  size=$(wc -c <"$(SHARED)")
  (( size < 32768 )) || false
}
