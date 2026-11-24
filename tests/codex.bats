#!/usr/bin/env bats
# codex/repo-profile.example.toml, the Codex profile template jwx points to, and
# codex/check-profile.sh, which jwx and agent-preflight use to check a profile.

load helpers

setup() {
  fake_home
}

TEMPLATE() { echo "$REPO_ROOT/codex/repo-profile.example.toml"; }

# toml_get <file> <python expression on the parsed table t>
toml_get() {
  python3 -I -c 'import sys, tomllib; t = tomllib.load(open(sys.argv[1], "rb")); print(eval(sys.argv[2]))' "$1" "$2"
}

@test "codex: the template is workspace-write with the main checkout's .jj and .git as placeholder roots" {
  python3 -I -c 'import tomllib' 2>/dev/null || skip "python3 without tomllib"
  [ "$(toml_get "$(TEMPLATE)" 't["sandbox_mode"]')" = workspace-write ]
  [ "$(toml_get "$(TEMPLATE)" 't["approval_policy"]')" = on-request ]
  [ "$(toml_get "$(TEMPLATE)" '"\n".join(t["sandbox_workspace_write"]["writable_roots"])')" = $'/path/to/<repo>/.jj\n/path/to/<repo>/.git' ]
}

@test "codex: the template names no model, MCP server or real path" {
  run grep -E '^[[:space:]]*(model|\[mcp_servers)' "$(TEMPLATE)"
  [ "$status" -eq 1 ]
  run grep -E '/(Users|home)/' "$(TEMPLATE)"
  [ "$status" -eq 1 ]
}

@test "codex: jwx's missing-profile hint names the template that exists" {
  grep -qF 'codex/repo-profile.example.toml' "$REPO_ROOT/zsh/jj.zsh"
  [ -f "$(TEMPLATE)" ]
}

check() {
  python3 -I -c 'import tomllib' 2>/dev/null || skip "python3 without tomllib"
  run "$REPO_ROOT/codex/check-profile.sh" "$@"
}

# profile <toml>: write $BATS_TEST_TMPDIR/p.toml
profile() { printf '%s\n' "$1" > "$BATS_TEST_TMPDIR/p.toml"; }

@test "check-profile: the template with its paths set passes, untouched it fails on both roots" {
  sed 's|/path/to/<repo>|/r/app|g' "$(TEMPLATE)" > "$BATS_TEST_TMPDIR/p.toml"
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  check "$BATS_TEST_TMPDIR/p.toml" /r/app/
  [ "$status" -eq 0 ]
  check "$(TEMPLATE)" /r/app
  [ "$status" -eq 1 ]
  [ "$output" = "[sandbox_workspace_write] writable_roots does not name this checkout's .jj
[sandbox_workspace_write] writable_roots does not name this checkout's .git
[sandbox_workspace_write] writable_roots has 2 root(s) besides this checkout's .jj and .git" ]
}

@test "check-profile: multi-line arrays, literal strings, comments and a dotted key pass" {
  profile 'sandbox_mode = "workspace-write" # writer
approval_policy = "on-request"
[sandbox_workspace_write]
writable_roots = [
  "/r/app/.jj",   # the store
  '"'"'/r/app/.git'"'"',
]
network_access = false'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 0 ]
  profile 'sandbox_mode = "workspace-write"
sandbox_workspace_write.writable_roots = ["/r/app/.jj", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 0 ]
}

@test "check-profile: a read-only mode, a commented root, a .jj-backup root or a root in another table fails" {
  profile 'sandbox_mode = "read-only" # not "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]
  [ "$output" = 'sandbox_mode is not "workspace-write"' ]

  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
# writable_roots = ["/r/app/.jj", "/r/app/.git"]
writable_roots = ["/r/app/.jj-backup", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]
  [ "$output" = "[sandbox_workspace_write] writable_roots does not name this checkout's .jj
[sandbox_workspace_write] writable_roots has 1 root(s) besides this checkout's .jj and .git" ]

  profile 'sandbox_mode = "workspace-write"
writable_roots = ["/r/app/.jj", "/r/app/.git"]
[sandbox_workspace_write]
network_access = true'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]

  profile '[profiles.x]
sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]
  [ "$output" = 'sandbox_mode is not "workspace-write"' ]
}

@test "check-profile: TOML it cannot read, a missing file or bad usage exits 2 without a path" {
  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git"'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 2 ]
  [ "$output" = "the profile is not valid TOML" ]
  profile 'sandbox_mode = workspace-write'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 2 ]
  check "$BATS_TEST_TMPDIR/missing.toml" /r/app
  [ "$status" -eq 2 ]
  [[ $output != *"$BATS_TEST_TMPDIR"* ]] || false
  check "$BATS_TEST_TMPDIR/p.toml"
  [ "$status" -eq 2 ]
}

@test "check-profile: duplicate keys and a bare word as a value are invalid TOML" {
  profile 'sandbox_mode = "read-only"
sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 2 ]
  [ "$output" = "the profile is not valid TOML" ]
  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git"]
network_access = flase'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 2 ]
}

@test "check-profile: roots are compared as TOML decodes them, escapes included" {
  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app\t/.jj", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]
  [[ $output == *"does not name this checkout's .jj"* ]] || false
  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 0 ]
}

@test "check-profile: a third writable root, or roots that are not a list of paths, fail" {
  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = ["/r/app/.jj", "/r/app/.git", "/r/other"]'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]
  [ "$output" = "[sandbox_workspace_write] writable_roots has 1 root(s) besides this checkout's .jj and .git" ]
  [[ $output != */r/other* ]] || false
  profile 'sandbox_mode = "workspace-write"
[sandbox_workspace_write]
writable_roots = "/r/app/.jj"'
  check "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 1 ]
  [[ $output == *"writable_roots is not a list of paths"* ]] || false
}

@test "check-profile: without a python3 that has tomllib it says so and exits 2" {
  local tools="$BATS_TEST_TMPDIR/tools"
  mkdir -p "$tools"
  ln -s "$(command -v bash)" "$tools/bash"
  profile 'sandbox_mode = "workspace-write"'
  PATH="$tools" run "$REPO_ROOT/codex/check-profile.sh" "$BATS_TEST_TMPDIR/p.toml" /r/app
  [ "$status" -eq 2 ]
  [[ $output == *"no python3 with tomllib (Python 3.11 or later) on PATH"* ]] || false
}
