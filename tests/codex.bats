#!/usr/bin/env bats
# codex/repo-profile.example.toml: the Codex profile template jwx points to.

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
