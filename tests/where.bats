#!/usr/bin/env bats
# claude/where.sh: repo, workspace, root, colour and kind for jj workspaces and git worktrees.

load helpers

setup() {
  fake_home
  WHERE="$REPO_ROOT/claude/where.sh"
}

make_workspace() {
  make_jj_repo "$HOME/src/app"
  mkdir -p "$HOME/src/app-ws"
  (cd "$HOME/src/app" && jj workspace add --name feat "$HOME/src/app-ws/feat" >/dev/null 2>&1)
}

op_count() { jj -R "$1" --ignore-working-copy op log --no-graph -T 'id ++ "\n"' | wc -l | tr -d ' '; }

@test "where: a jj workspace prints the main repo's name, the workspace name, root and a colour" {
  make_workspace
  run bash "$WHERE" "$HOME/src/app-ws/feat"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = app ]
  [ "${lines[1]}" = feat ]
  [ "${lines[2]}" = "$(realpath_of "$HOME/src/app-ws/feat")" ]
  [[ ${lines[3]} =~ ^[1-6]$ ]] || false
  [ "${lines[4]}" = jj ]
}

@test "where: a workspace nested inside the main checkout still gets the main repo's name" {
  make_jj_repo "$HOME/src/app"
  (cd "$HOME/src/app" && jj workspace add --name inner inner >/dev/null 2>&1)
  run bash "$WHERE" "$HOME/src/app/inner"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = app ]
  [ "${lines[1]}" = inner ]
}

@test "where: a git worktree inside a jj repo is the worktree, not the jj checkout around it" {
  make_jj_repo "$HOME/src/app"
  git -C "$HOME/src/app" worktree add --quiet -b agent1 "$HOME/src/app/.claude/worktrees/agent1" 2>/dev/null
  run bash "$WHERE" "$HOME/src/app/.claude/worktrees/agent1"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = app ]
  [ "${lines[1]}" = agent1 ]
  [ "${lines[2]}" = "$(realpath_of "$HOME/src/app/.claude/worktrees/agent1")" ]
  [ "${lines[4]}" = git ]
}

@test "where: a subdirectory of a workspace reports the workspace" {
  make_workspace
  mkdir -p "$HOME/src/app-ws/feat/sub/dir"
  run bash "$WHERE" "$HOME/src/app-ws/feat/sub/dir"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = feat ]
}

@test "where: the workspace name comes from jj, not from the directory" {
  make_jj_repo "$HOME/src/app"
  mkdir -p "$HOME/elsewhere"
  (cd "$HOME/src/app" && jj workspace add --name review "$HOME/elsewhere/dir" >/dev/null 2>&1)
  run bash "$WHERE" "$HOME/elsewhere/dir"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = app ]
  [ "${lines[1]}" = review ]
}

@test "where: the main jj checkout has an empty workspace name and colour" {
  make_workspace
  run bash "$WHERE" "$HOME/src/app"
  [ "$status" -eq 0 ]
  # bats drops empty entries from $lines, so compare the whole output
  [ "$output" = "app

$(realpath_of "$HOME/src/app")

jj" ]
}

@test "where: the colour is stable for a name and differs across names" {
  make_jj_repo "$HOME/src/app"
  mkdir -p "$HOME/src/app-ws"
  for n in a b c d e f g h; do
    (cd "$HOME/src/app" && jj workspace add --name "$n" "$HOME/src/app-ws/$n" >/dev/null 2>&1)
  done
  first=$(bash "$WHERE" "$HOME/src/app-ws/a" | sed -n 4p)
  [ "$(bash "$WHERE" "$HOME/src/app-ws/a" | sed -n 4p)" = "$first" ]
  colours=$(for n in a b c d e f g h; do bash "$WHERE" "$HOME/src/app-ws/$n" | sed -n 4p; done | sort -u | wc -l)
  [ "$colours" -gt 1 ]
}

@test "where: a linked git worktree prints the main repo's name and the worktree dir" {
  git init --quiet -b main "$HOME/src/plain"
  git -C "$HOME/src/plain" commit --quiet --allow-empty -m init
  git -C "$HOME/src/plain" worktree add --quiet -b fix "$HOME/src/plain-wt/fix-x"
  run bash "$WHERE" "$HOME/src/plain-wt/fix-x"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = plain ]
  [ "${lines[1]}" = fix-x ]
  [ "${lines[4]}" = git ]
  run bash "$WHERE" "$HOME/src/plain"
  [ "$output" = "plain

$(realpath_of "$HOME/src/plain")

git" ]
}

@test "where: outside a repo or in a missing dir it prints nothing and exits 1" {
  mkdir -p "$HOME/outside"
  run bash "$WHERE" "$HOME/outside"
  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  run bash "$WHERE" "$HOME/gone"
  [ "$status" -eq 1 ]
}

@test "where: never adds operations to the jj op log" {
  make_workspace
  printf 'dirty\n' > "$HOME/src/app-ws/feat/uncommitted.txt"
  before=$(op_count "$HOME/src/app")
  bash "$WHERE" "$HOME/src/app-ws/feat" >/dev/null
  [ "$(op_count "$HOME/src/app")" -eq "$before" ]
}
