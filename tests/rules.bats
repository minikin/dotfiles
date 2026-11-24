#!/usr/bin/env bats
# agents/AGENTS.md and the files that load it: claude/CLAUDE.md, agy/GEMINI.md, ~/.codex/AGENTS.md.
# The repo's own AGENTS.md and the CLAUDE.md that imports it.

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
  for f in "$REPO_ROOT"/claude/*.md "$REPO_ROOT"/agy/*.md "$REPO_ROOT"/CLAUDE.md "$REPO_ROOT"/AGENTS.md; do
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

@test "rules: claude/CLAUDE.md imports the shared file by a path relative to itself" {
  run grep -x '@../agents/AGENTS.md' "$REPO_ROOT/claude/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/claude/../agents/AGENTS.md" ]
}

@test "rules: agy's rules with the shared file included stay under agy's 24,000-byte cap" {
  local size
  size=$(cat "$REPO_ROOT/agy/GEMINI.md" "$(SHARED)" | wc -c)
  (( size < 24000 )) || false
}

@test "rules: agy/GEMINI.md includes the shared file by a home path, since agy resolves relative includes next to the link" {
  run grep -xE '@\[[^]]+\]\(~/\.config/dotfiles/AGENTS\.md\)' "$REPO_ROOT/agy/GEMINI.md"
  [ "$status" -eq 0 ]
}

@test "rules: push to main, merge, tag and publish are OK-gated in the shared file and banned only in agy's part" {
  ! grep -qE 'Never (push to main|merge)' "$(SHARED)" || false
  grep -qF 'Push to main, merge, tag or publish only when I ask for that exact action.' "$(SHARED)"
  grep -qF 'Never push to main. Never merge, tag or publish.' "$REPO_ROOT/agy/GEMINI.md"
}

@test "rules: the repo's CLAUDE.md imports the repo's AGENTS.md and holds no rules of its own" {
  run grep -x '@AGENTS.md' "$REPO_ROOT/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/AGENTS.md" ]
  run grep -cE '^(- |## )' "$REPO_ROOT/CLAUDE.md"
  [ "$output" = "0" ]
}

@test "rules: the repo's AGENTS.md has no @ imports, which Codex and agy would not resolve" {
  run grep -nE '^@' "$REPO_ROOT/AGENTS.md"
  [ "$status" -eq 1 ]
}

@test "rules: the shared file and the repo's AGENTS.md together stay under Codex's 32 KiB project doc limit" {
  local size
  size=$(cat "$(SHARED)" "$REPO_ROOT/AGENTS.md" | wc -c)
  (( size < 32768 )) || false
}
