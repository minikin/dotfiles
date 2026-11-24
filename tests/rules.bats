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

@test "rules: every Codex launch prefix is the one the agy guard requires" {
  local vars prefix f
  vars=$(sed -n 's/^typeset -ga CODEX_VARS=(\(.*\))$/\1/p' "$REPO_ROOT/agy/guard-agents.zsh")
  [[ $vars == *CODEX_API_KEY* ]] || false
  prefix="env -u ${vars// / -u } codex"
  for f in agents/AGENTS.md agy/GEMINI.md zsh/jj.zsh bin/agent-preflight docs/guides/agent-rules.md; do
    grep -qF -- "$prefix" "$REPO_ROOT/$f" || { echo "$f has no '$prefix'"; return 1; }
    if grep -nE -- '-u OPENAI_API_KEY -u CODEX_HOME' "$REPO_ROOT/$f"; then echo "$f has the old prefix"; return 1; fi
  done
}

# codex_prefix: the prefix agy's guard requires, from its CODEX_VARS.
codex_prefix() {
  local vars
  vars=$(sed -n 's/^typeset -ga CODEX_VARS=(\(.*\))$/\1/p' "$REPO_ROOT/agy/guard-agents.zsh")
  echo "env -u ${vars// / -u }"
}

@test "rules: each Codex launch in the scripts and the Markdown code starts with that prefix" {
  local files
  files=(agents/AGENTS.md agy/GEMINI.md zsh/jj.zsh bin/agent-preflight README.md CONTRIBUTING.md SETUP_PROMPT.md AGENTS.md)
  while IFS= read -r f; do files+=("$f"); done < <(cd "$REPO_ROOT" && find docs -name '*.md')
  cd "$REPO_ROOT"
  run python3 -I tests/codex_launches.py "$(codex_prefix)" "${files[@]}"
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "rules: the launch check catches a prefix removed from one launch, continued lines included" {
  local p
  p=$(codex_prefix)
  sed "s/^$p codex exec/codex exec/" "$REPO_ROOT/docs/guides/agent-rules.md" > agent-rules.md
  sed "s/$p \\\\\$/\\\\/" "$REPO_ROOT/zsh/jj.zsh" > jj.zsh
  printf '| Codex | `%s codex -p <repo>` |\n| Codex | `codex -s read-only -a never` |\n' "$p" > table.md
  run python3 -I "$REPO_ROOT/tests/codex_launches.py" "$p" agent-rules.md jj.zsh table.md
  [ "$status" -eq 1 ]
  [[ $output == *"agent-rules.md:"*": codex exec --ephemeral"* ]] || false
  [[ $output == *'jj.zsh:'*': (cd "$d" && codex exec -s read-only'* ]] || false
  [[ $output == *"table.md:2: codex -s read-only -a never"* ]] || false
  [[ $output != *"table.md:1"* ]] || false
}
