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
  [[ $output =~ ^~/src/app-ws/feat\ ·\ \[feat\]\ [a-z]{4,}\ .*add\ login\ ·\ Opus$ ]]
}

@test "statusline: single-workspace repo never prints an empty []" {
  statusline "$REPO"
  [ "$status" -eq 0 ]
  echo "output: $output"
  [[ $output != *"[]"* ]]
  [[ $output =~ ^~/src/app\ ·\ .+\ ·\ Opus$ ]]
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
  [[ $output == *"· Opus" ]]
}
