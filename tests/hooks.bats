#!/usr/bin/env bats
# claude/notify.sh and claude/guard-push.sh: the Claude Code hooks install.sh links into ~/.claude.

load helpers

setup() {
  fake_home
}

NOTIFY() { echo "$REPO_ROOT/claude/notify.sh"; }
GUARD() { echo "$REPO_ROOT/claude/guard-push.sh"; }
CONTEXT() { echo "$REPO_ROOT/claude/session-context.sh"; }

# context <cwd> [source]: feed a SessionStart event to session-context.sh
context() {
  run bash "$(CONTEXT)" <<<"{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$1\",\"source\":\"${2:-startup}\"}"
}

# make_workspace: jj repo at ~/src/app with a second workspace at ~/src/app-ws/feat
make_workspace() {
  make_jj_repo "$HOME/src/app"
  mkdir -p "$HOME/src/app-ws"
  (cd "$HOME/src/app" && jj workspace add --name feat "$HOME/src/app-ws/feat" >/dev/null 2>&1)
}

# guard <cwd> <command>: feed a PreToolUse Bash event to guard-push.sh
guard() {
  local json
  json=$(jq -nc --arg cwd "$1" --arg cmd "$2" \
    '{hook_event_name: "PreToolUse", cwd: $cwd, tool_name: "Bash", tool_input: {command: $cmd}}')
  run bash "$(GUARD)" <<<"$json"
}

@test "notify: Stop outside a repo is titled with the dir name and says done" {
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<'{"hook_event_name":"Stop","cwd":"/x/app-ws/feat","last_assistant_message":"All set"}'
  [ "$status" -eq 0 ]
  [ "$output" = "feat|done" ]
}

@test "notify: a real workspace is titled repo/workspace, the main checkout with the repo name" {
  make_workspace
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<"{\"hook_event_name\":\"Stop\",\"cwd\":\"$HOME/src/app-ws/feat\"}"
  [ "$status" -eq 0 ]
  [ "$output" = "app/feat|done" ]
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<"{\"hook_event_name\":\"Stop\",\"cwd\":\"$HOME/src/app\"}"
  [ "$output" = "app|done" ]
}

@test "notify: Notification uses the hook's message" {
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<'{"hook_event_name":"Notification","cwd":"/x/app","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}'
  [ "$status" -eq 0 ]
  [ "$output" = "app|Claude needs your permission to use Bash" ]
}

@test "notify: Notification without a message says waiting for input" {
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<'{"hook_event_name":"Notification","cwd":"/x/app"}'
  [ "$status" -eq 0 ]
  [ "$output" = "app|waiting for input" ]
}

@test "notify: no cwd falls back to Claude Code as the title" {
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<'{"hook_event_name":"Stop"}'
  [ "$status" -eq 0 ]
  [ "$output" = "Claude Code|done" ]
}

@test "notify: semicolons and control characters cannot break the OSC sequence" {
  JW_NOTIFY=print run bash "$(NOTIFY)" <<<'{"hook_event_name":"Notification","cwd":"/x/a;b","message":"one;two\u0007\u001b]0;evil\nthree"}'
  [ "$status" -eq 0 ]
  [ "$output" = "a,b|one,two]0,evil three" ]
}

@test "notify: default output is one terminalSequence object with OSC 777 and a bell" {
  run bash "$(NOTIFY)" <<<'{"hook_event_name":"Stop","cwd":"/x/app-ws/feat"}'
  [ "$status" -eq 0 ]
  expected=$(printf '\033]777;notify;feat;done\007\007')
  jq -e --arg s "$expected" '.terminalSequence == $s and (keys == ["terminalSequence"])' <<<"$output"
}

@test "notify: invalid or empty input still exits 0" {
  run bash "$(NOTIFY)" <<<'not json'
  [ "$status" -eq 0 ]
  run bash "$(NOTIFY)" </dev/null
  [ "$status" -eq 0 ]
}

@test "session-context: a jj workspace tells the agent its workspace, repo and root" {
  make_workspace
  root=$(realpath_of "$HOME/src/app-ws/feat")
  for src in startup resume compact; do
    context "$HOME/src/app-ws/feat" "$src"
    [ "$status" -eq 0 ]
    jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$output"
    ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
    echo "ctx: $ctx"
    [[ $ctx == *'jj workspace "feat" of the repo "app"'* ]] || false
    [[ $ctx == *"$root"* ]] || false
    [[ $ctx == *"app/feat"* ]] || false
  done
}

@test "session-context: the main checkout and a git worktree are named as such" {
  make_workspace
  context "$HOME/src/app"
  [[ $(jq -r '.hookSpecificOutput.additionalContext' <<<"$output") == *'main checkout of the repo "app"'* ]] || false
  git init --quiet -b main "$HOME/src/plain"
  git -C "$HOME/src/plain" commit --quiet --allow-empty -m init
  git -C "$HOME/src/plain" worktree add --quiet -b fix "$HOME/src/plain-wt/fix-x"
  context "$HOME/src/plain-wt/fix-x"
  [[ $(jq -r '.hookSpecificOutput.additionalContext' <<<"$output") == *'git worktree "fix-x" of the repo "plain"'* ]] || false
  git -C "$HOME/src/app" worktree add --quiet -b agent1 "$HOME/src/app/.claude/worktrees/agent1" 2>/dev/null
  context "$HOME/src/app/.claude/worktrees/agent1"
  [[ $(jq -r '.hookSpecificOutput.additionalContext' <<<"$output") == *'git worktree "agent1" of the repo "app"'* ]] || false
}

@test "session-context: outside a repo or on bad input it prints nothing and exits 0" {
  mkdir -p "$HOME/outside"
  context "$HOME/outside"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  run bash "$(CONTEXT)" <<<'not json'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "guard: git push and jj git push from a jj workspace are blocked with exit 2" {
  make_workspace
  [ -f "$HOME/src/app-ws/feat/.jj/repo" ]
  guard "$HOME/src/app-ws/feat" "jj git push -b feat"
  [ "$status" -eq 2 ]
  [[ $output == *"agents in jj workspaces and git worktrees do not push"* ]] || false
  [[ $output == *"jpush/jland"* ]] || false
  guard "$HOME/src/app-ws/feat" "jj st && git push origin HEAD"
  [ "$status" -eq 2 ]
  guard "$HOME/src/app-ws/feat" $'jj describe -m x\ngit push'
  [ "$status" -eq 2 ]
}

@test "guard: a subdirectory of a workspace is still a workspace" {
  make_workspace
  mkdir -p "$HOME/src/app-ws/feat/sub/dir"
  guard "$HOME/src/app-ws/feat/sub/dir" "git push"
  [ "$status" -eq 2 ]
}

@test "guard: a git worktree, also one inside a jj repo, is blocked like a workspace" {
  git init --quiet -b main "$HOME/src/plain"
  git -C "$HOME/src/plain" commit --quiet --allow-empty -m init
  git -C "$HOME/src/plain" worktree add --quiet -b fix "$HOME/src/plain-wt/fix-x"
  guard "$HOME/src/plain-wt/fix-x" "git push origin fix"
  [ "$status" -eq 2 ]
  [[ $output == *"git worktrees do not push"* ]] || false
  make_jj_repo "$HOME/src/app"
  git -C "$HOME/src/app" worktree add --quiet -b agent1 "$HOME/src/app/.claude/worktrees/agent1" 2>/dev/null
  guard "$HOME/src/app/.claude/worktrees/agent1" "git push"
  [ "$status" -eq 2 ]
}

@test "guard: the main checkout of a plain git repo may push" {
  git init --quiet -b main "$HOME/src/plain"
  git -C "$HOME/src/plain" commit --quiet --allow-empty -m init
  guard "$HOME/src/plain" "git push"
  [ "$status" -eq 0 ]
}

@test "guard: the main checkout may push" {
  make_jj_repo "$HOME/src/app"
  [ -d "$HOME/src/app/.jj/repo" ]
  guard "$HOME/src/app" "jj git push -b main"
  [ "$status" -eq 0 ]
}

@test "guard: a non-jj directory may push" {
  mkdir -p "$HOME/plain"
  guard "$HOME/plain" "git push"
  [ "$status" -eq 0 ]
}

@test "guard: other commands in a workspace pass" {
  make_workspace
  for cmd in "jj log" "git status" "git pushd" "jj git fetch" "mygit push"; do
    guard "$HOME/src/app-ws/feat" "$cmd"
    echo "cmd: $cmd status: $status"
    [ "$status" -eq 0 ]
  done
}

@test "guard: invalid input exits 0" {
  run bash "$(GUARD)" <<<'not json'
  [ "$status" -eq 0 ]
}
