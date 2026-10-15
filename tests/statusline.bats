#!/usr/bin/env bats
# claude/statusline.sh: "dir · [workspace] change desc · model", read-only for jj.

load helpers

setup() {
  fake_home
  export JW_NO_SETUP=1
  REPO="$HOME/src/app"
  make_jj_repo "$REPO"
}

# statusline <dir>: feed the Claude Code status JSON for <dir> to the script
statusline() {
  run bash "$REPO_ROOT/claude/statusline.sh" <<<"{\"workspace\":{\"current_dir\":\"$1\"},\"model\":{\"display_name\":\"Opus\"}}"
}

op_count() { jj -R "$1" --ignore-working-copy op log --no-graph -T 'id ++ "\n"' | wc -l | tr -d ' '; }

@test "statusline: inside a jj workspace shows dir, [workspace], change, desc and model" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && echo code > login.txt && jj describe -m 'add login' >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  ws="$HOME/src/app-ws/feat"
  statusline "$ws"
  [ "$status" -eq 0 ]
  echo "output: $output"
  [[ $output =~ ^~/src/app-ws/feat\ ·\ \[feat\]\ [a-z]{4,}\ .*add\ login\ ·\ Opus$ ]] || false
}

@test "statusline: single-workspace repo never prints an empty []" {
  statusline "$REPO"
  [ "$status" -eq 0 ]
  echo "output: $output"
  [[ $output != *"[]"* ]] || false
  [[ $output =~ ^~/src/app\ ·\ .+\ ·\ Opus$ ]] || false
}

@test "statusline: outside a repo prints only dir and model" {
  mkdir -p "$HOME/outside"
  statusline "$HOME/outside"
  [ "$status" -eq 0 ]
  [ "$output" = "~/outside · Opus" ]
}

@test "statusline: empty JSON input exits 0" {
  cd "$HOME"
  run bash "$REPO_ROOT/claude/statusline.sh" <<<'{}'
  [ "$status" -eq 0 ]
  [ "$output" = "~" ]
}

@test "statusline: never adds operations to the jj op log" {
  printf 'dirty\n' > "$REPO/uncommitted.txt"   # a snapshot would record an operation
  before=$(op_count "$REPO")
  statusline "$REPO"
  [ "$status" -eq 0 ]
  statusline "$REPO"
  [ "$(op_count "$REPO")" -eq "$before" ]
}

@test "statusline: a current_dir that no longer exists still exits 0" {
  cd "$HOME"
  statusline "$HOME/gone"
  [ "$status" -eq 0 ]
  [[ $output == *"· Opus" ]] || false
}

@test "statusline: plain git repo (no jj) shows git:<branch>" {
  plain="$HOME/src/plain"
  git init --quiet -b feature-x "$plain"
  git -C "$plain" commit --quiet --allow-empty -m init
  statusline "$plain"
  [ "$status" -eq 0 ]
  echo "output: $output"
  [ "$output" = "~/src/plain · git:feature-x · Opus" ]
}

@test "statusline: plain git repo on a detached HEAD prints no git segment" {
  plain="$HOME/src/plain"
  git init --quiet -b main "$plain"
  git -C "$plain" commit --quiet --allow-empty -m init
  git -C "$plain" checkout --quiet --detach
  statusline "$plain"
  [ "$status" -eq 0 ]
  [ "$output" = "~/src/plain · Opus" ]
}

# statusline_json <json>: feed raw status JSON
statusline_json() { run bash "$REPO_ROOT/claude/statusline.sh" <<<"$1"; }

@test "statusline: context percentage and cost follow the model" {
  mkdir -p "$HOME/outside"
  statusline_json "{\"workspace\":{\"current_dir\":\"$HOME/outside\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":42.7},\"cost\":{\"total_cost_usd\":1.234}}"
  [ "$status" -eq 0 ]
  [ "$output" = "~/outside · Opus · 42% ctx · \$1.23" ]
}

@test "statusline: null used_percentage falls back to total_input_tokens over the window size" {
  mkdir -p "$HOME/outside"
  statusline_json "{\"workspace\":{\"current_dir\":\"$HOME/outside\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":null,\"total_input_tokens\":50000,\"context_window_size\":200000}}"
  [ "$status" -eq 0 ]
  [ "$output" = "~/outside · Opus · 25% ctx" ]
}

@test "statusline: no context data before the first response and zero cost are omitted" {
  mkdir -p "$HOME/outside"
  statusline_json "{\"workspace\":{\"current_dir\":\"$HOME/outside\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":null,\"total_input_tokens\":0,\"context_window_size\":200000},\"cost\":{\"total_cost_usd\":0}}"
  [ "$status" -eq 0 ]
  [ "$output" = "~/outside · Opus" ]
}

@test "statusline: 0% context is still shown" {
  mkdir -p "$HOME/outside"
  statusline_json "{\"workspace\":{\"current_dir\":\"$HOME/outside\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":0}}"
  [ "$status" -eq 0 ]
  [ "$output" = "~/outside · Opus · 0% ctx" ]
}

@test "statusline: a dir with spaces and a model with spaces survive the single jq call" {
  mkdir -p "$HOME/my dir"
  statusline_json "{\"workspace\":{\"current_dir\":\"$HOME/my dir\"},\"model\":{\"display_name\":\"Opus 5.5\"},\"cost\":{\"total_cost_usd\":12}}"
  [ "$status" -eq 0 ]
  [ "$output" = "~/my dir · Opus 5.5 · \$12.00" ]
}
