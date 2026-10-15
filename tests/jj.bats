#!/usr/bin/env bats
# zsh/jj.zsh: jw, jwrm, jpush and the `jj tug` alias, in throwaway colocated repos.

load helpers

setup() {
  fake_home
  export JW_NO_SETUP=1
  REPO="$HOME/src/app"
  make_jj_repo "$REPO"
  WS="$(realpath_of "$HOME/src")/app-ws"
}

@test "jw: creates <repo>-ws/<name> (slashes become dashes) and cds into it" {
  run_zsh "cd '$REPO' && jw feat/x >/dev/null 2>&1 && pwd -P && git status --short --branch"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$WS/feat-x" ]
  [ -d "$WS/feat-x" ]
  [ -f "$WS/feat-x/README.md" ]
  [[ ${lines[1]} == "## "* ]]   # git works inside the workspace
  run jj -R "$REPO" workspace list -T 'name ++ "\n"'
  [[ $output == *feat-x* ]] || false
}

@test "jw: from inside a workspace creates a sibling, not a nested workspace" {
  run_zsh "cd '$REPO' && jw one >/dev/null 2>&1 && jw two >/dev/null 2>&1 && pwd -P"
  [ "$status" -eq 0 ]
  [ "$output" = "$WS/two" ]
  [ -d "$WS/one" ]
  [ ! -e "$WS/one-ws" ]
  [ ! -e "$(dirname "$WS")/one-ws" ]
}

@test "jw: copies ignored env files, never overwrites tracked files, JW_NO_SETUP skips" {
  (
    cd "$REPO"
    printf 'tracked\n' > .env.example
    jj commit -m 'add env example' >/dev/null 2>&1
    printf 'SECRET=1\n' > .env
    mkdir -p svc && printf 'SVC=1\n' > svc/.env.local
    printf 'local edit\n' > .env.example   # uncommitted change to a tracked file
  )
  unset JW_NO_SETUP
  run_zsh "cd '$REPO' && jw withenv"
  [ "$status" -eq 0 ]
  [ "$(cat "$WS/withenv/.env")" = "SECRET=1" ]
  [ "$(cat "$WS/withenv/svc/.env.local")" = "SVC=1" ]
  [ "$(cat "$WS/withenv/.env.example")" = "tracked" ]
  [[ $output != *"copied .env.example"* ]] || false

  run_zsh "cd '$REPO' && JW_NO_SETUP=1 jw bare"
  [ "$status" -eq 0 ]
  [ ! -e "$WS/bare/.env" ]
  [ ! -e "$WS/bare/svc/.env.local" ]
  [[ $output != *"copied"* ]] || false
  [[ $output != *"setup:"* ]] || false
}

@test "jw: setup runs 'just setup' instead of lockfile installs" {
  command -v just >/dev/null || skip "just not installed"
  (
    cd "$REPO"
    printf 'setup:\n    touch setup-ran\n' > justfile
    printf '{"lockfileVersion": 3}\n' > package-lock.json
    jj commit -m 'add justfile' >/dev/null 2>&1
  )
  # A fake npm that would leave a marker if the lockfile install ran
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ntouch "%s/npm-ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/npm"
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  unset JW_NO_SETUP
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jw s"
  [ "$status" -eq 0 ]
  [[ $output == *"setup: just setup"* ]] || false
  [ -f "$WS/s/setup-ran" ]
  [ ! -e "$BATS_TEST_TMPDIR/npm-ran" ]
}

@test "jw: recreates a workspace whose directory was deleted by hand" {
  run_zsh "cd '$REPO' && jw x"
  [ "$status" -eq 0 ]
  rm -rf "$WS/x"
  run_zsh "cd '$REPO' && jw x >/dev/null 2>&1 && pwd -P"
  [ "$status" -eq 0 ]
  [ "$output" = "$WS/x" ]
  [ -f "$WS/x/README.md" ]
  run git -C "$REPO" worktree list
  [ "$status" -eq 0 ]
  [[ $output != *prunable* ]] || false
  run git -C "$WS/x" status --short
  [ "$status" -eq 0 ]
}

@test "jwrm: from inside the workspace cds out, removes it and keeps the change" {
  run_zsh "cd '$REPO' && jw x >/dev/null 2>&1 && echo work > agent.txt && jj describe -m 'agent work' >/dev/null 2>&1 \
    && jj log -r @ --no-graph -T change_id && echo && jwrm x >/dev/null 2>&1 && pwd -P"
  [ "$status" -eq 0 ]
  change=${lines[0]}
  [ "${lines[1]}" = "$(realpath_of "$REPO")" ]
  [ ! -e "$WS/x" ]
  run jj -R "$REPO" workspace list -T 'name ++ "\n"'
  [[ $output != *x* ]] || false
  run jj -R "$REPO" log -r "$change" --no-graph -T 'description'
  [ "$status" -eq 0 ]
  [[ $output == *"agent work"* ]] || false
}

@test "jwrm: from inside the workspace reached through a symlink still cds out first" {
  ln -s "$HOME/src" "$BATS_TEST_TMPDIR/link"
  run_zsh "cd '$REPO' && jw x >/dev/null 2>&1 && cd '$BATS_TEST_TMPDIR/link/app-ws/x' && jwrm x >/dev/null 2>&1 && pwd -P"
  [ "$status" -eq 0 ]
  [ "$output" = "$(realpath_of "$REPO")" ]
  [ ! -e "$WS/x" ]
}

@test "jw, jws, jwrm: read-only jj queries pass --ignore-working-copy" {
  run grep -nE "workspace list -T|log -r 'trunk\(\) & ~root\(\)'" "$REPO_ROOT/zsh/jj.zsh"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 4 ]
  for l in "${lines[@]}"; do
    [[ $l == *--ignore-working-copy* ]] || { echo "missing --ignore-working-copy: $l"; return 1; }
  done
  run grep -nE 'jpush|workspace add' "$REPO_ROOT/zsh/jj.zsh"
  [[ $output != *--ignore-working-copy* ]] || false
}

@test "jpush: refuses a workspace named after trunk; pushes a normal workspace as its own bookmark" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  main_before=$(git -C "$remote" rev-parse refs/heads/main)

  run_zsh "cd '$REPO' && jw main >/dev/null 2>&1 && echo x > m.txt && jj commit -m 'onto main' >/dev/null 2>&1 && jpush"
  [ "$status" -ne 0 ]
  [[ $output == *refusing* ]] || false
  [ "$(git -C "$remote" rev-parse refs/heads/main)" = "$main_before" ]

  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && echo y > f.txt && jj commit -m 'feature' >/dev/null 2>&1 && jpush"
  [ "$status" -eq 0 ]
  run git -C "$remote" log -1 --format=%s refs/heads/feat
  [ "$status" -eq 0 ]
  [ "$output" = feature ]
  [ "$(git -C "$remote" rev-parse refs/heads/main)" = "$main_before" ]
}

@test "jpush: in the default workspace requires an explicit name" {
  run_zsh "cd '$REPO' && jpush"
  [ "$status" -ne 0 ]
  [[ $output == *"usage: jpush"* ]] || false
}

@test "jpush: a second push moves the existing bookmark forward" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && echo y > f.txt && jj commit -m 'first' >/dev/null 2>&1 && jpush \
    && echo z > g.txt && jj commit -m 'second' >/dev/null 2>&1 && jpush"
  echo "$output"
  [ "$status" -eq 0 ]
  run git -C "$remote" log -2 --format=%s refs/heads/feat
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = second ]
  [ "${lines[1]}" = first ]
}

@test "jpush: refuses when several workspaces share @ instead of joining their names" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && echo y > f.txt && jj describe -m 'shared' >/dev/null 2>&1 \
    && change=\$(jj log -r @ --no-graph -T change_id) && jw fix >/dev/null 2>&1 && jj edit \$change >/dev/null 2>&1 && jpush"
  [ "$status" -ne 0 ]
  [[ $output == *"usage: jpush"* ]] || false
  run git -C "$remote" for-each-ref --format='%(refname:short)' refs/heads
  [ "$output" = main ]
}

@test "jj tug: in a fresh workspace does not move main" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  main_before=$(jj -R "$REPO" log -r main --no-graph -T commit_id)
  run_zsh "cd '$REPO' && jw t >/dev/null 2>&1 && echo z > t.txt && jj commit -m 'agent' >/dev/null 2>&1 && jj tug"
  [[ $output == *"No bookmarks to update"* || $status -eq 0 ]] || false
  [ "$(jj -R "$REPO" log -r main --no-graph -T commit_id)" = "$main_before" ]
}
