#!/usr/bin/env bats
# zsh/jj.zsh: jw, jwc, jwst, jnext, the repo-entry hint, jsync, jwrm, jpush, jland and the `jj tug` alias, in throwaway colocated repos.

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

@test "jw, jws, jwrm, jwst: read-only jj queries pass --ignore-working-copy" {
  run grep -nE "workspace list -T|log -r 'trunk\(\) & ~root\(\)'" "$REPO_ROOT/zsh/jj.zsh"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 5 ]
  for l in "${lines[@]}"; do
    [[ $l == *--ignore-working-copy* ]] || { echo "missing --ignore-working-copy: $l"; return 1; }
  done
  # jwst queries only from the root: -R <workspace dir> would snapshot it, and snapshots get signed
  run bash -c "sed -n '/^jwst()/,/^}/p' '$REPO_ROOT/zsh/jj.zsh' | grep -E '(^|[^a-z_])jj '"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 3 ]
  for l in "${lines[@]}"; do
    [[ $l == *'jj -R $root --ignore-working-copy '* ]] || { echo "jwst query not read-only from the root: $l"; return 1; }
  done
  # jnext and the repo-entry hint: the same rule, and the root lookup is read-only too
  for f in jnext _jw_hint _jw_wc_names; do
    run bash -c "sed -n '/^$f()/,/^}/p' '$REPO_ROOT/zsh/jj.zsh' | grep -E '(^[[:space:]]*|\\\$\\()jj '"
    [ "$status" -eq 0 ]
    for l in "${lines[@]}"; do
      [[ $l == *'jj -R $root --ignore-working-copy '* || $l == *'jj -R $1 --ignore-working-copy '* ||
         $l == *'jj --ignore-working-copy workspace root '* ]] || { echo "$f query not read-only from the root: $l"; return 1; }
    done
  done
  run grep -nE 'jpush|workspace add' "$REPO_ROOT/zsh/jj.zsh"
  [[ $output != *--ignore-working-copy* ]] || false
}

@test "jwc: passes an optional rev to jw and the remaining arguments to claude" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "pwd=%%s\\nargs=%%s\\n" "$(pwd -P)" "$*"\n' > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  (cd "$REPO" && echo two > two.txt && jj commit -m second >/dev/null 2>&1)
  parent() { jj -R "$REPO" --ignore-working-copy log --no-graph -r "$1@-" -T "description.first_line()"; }

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc x 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/x" ]
  [ "${lines[1]}" = "args=" ]
  [ "$(parent x)" = second ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc y @-- 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/y" ]
  [ "${lines[1]}" = "args=" ]
  [ "$(parent y)" = init ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc feat/z --permission-mode plan 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/feat-z" ]
  [ "${lines[1]}" = "args=--permission-mode plan" ]
  [ "$(parent feat-z)" = second ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc w @-- --continue 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/w" ]
  [ "${lines[1]}" = "args=--continue" ]
  [ "$(parent w)" = init ]
}

@test "jwst: one row per workspace with change, behind count, pushed and conflicts" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  # a: pushed, then main moves on, so it is 1 behind
  # b: not pushed, rebased onto the new main with a conflict in README.md
  run_zsh "cd '$REPO' && jw a && echo a > a.txt && jj commit -m 'a work' && jpush \
    && jw b && echo b > README.md && jj commit -m 'b work' \
    && cd '$REPO' && echo main > README.md && jj commit -m 'main moves' && jland \
    && jj rebase -b b@ -d 'trunk()'"
  [ "$status" -eq 0 ]
  ops_before=$(jj -R "$REPO" --ignore-working-copy op log --no-graph -T 'id ++ "\n"' | wc -l)
  echo dirty > "$WS/a/unsaved.txt"

  run_zsh "cd '$REPO' && jwst"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} =~ ^WORKSPACE\ +CHANGE\ +BEHIND\ +PUSHED\ +CONFLICTS\ +DESCRIPTION$ ]] || false
  re_a='^a +[k-z]{8} +1 +yes +no +a work$'
  re_b='^b +[k-z]{8} +0 +no +yes +b work$'
  re_d='^default +- +0 +no +no +\(no changes\)$'
  [[ ${lines[1]} =~ $re_a ]] || false
  [[ ${lines[2]} =~ $re_b ]] || false
  [[ ${lines[3]} =~ $re_d ]] || false
  # columns line up
  [ "$(expr "${lines[1]}" : 'a *')" -eq "$(expr "${lines[3]}" : 'default *')" ]
  # read-only: no snapshot of a's unsaved file, no new operation
  [ "$(jj -R "$REPO" --ignore-working-copy op log --no-graph -T 'id ++ "\n"' | wc -l)" -eq "$ops_before" ]
}

@test "jsync: rebases a workspace onto the new trunk, keeps unsaved edits, leaves it fresh" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw a && echo a > a.txt && jj commit -m 'a work' \
    && cd '$REPO' && echo m > m.txt && jj commit -m 'main moves' && jland"
  [ "$status" -eq 0 ]
  echo unsaved > "$WS/a/unsaved.txt"

  run_zsh "cd '$REPO' && jsync a"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "a: rebased onto trunk" ]
  run jj -R "$REPO" --ignore-working-copy log --no-graph -r 'trunk() & ::a@' -T 'description.first_line()'
  [ "$output" = "main moves" ]
  [ "$(cat "$WS/a/unsaved.txt")" = unsaved ]
  [ -f "$WS/a/m.txt" ]
  run jj -R "$WS/a" status
  [ "$status" -eq 0 ]
  [[ $output == *unsaved.txt* ]] || false
  run jj -R "$WS/a" --ignore-working-copy log --no-graph -r '@- & ~empty()' -T 'description.first_line()'
  [ "$output" = "a work" ]
}

@test "jsync: skips an up-to-date workspace and reports conflicts" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw b && echo b > README.md && jj commit -m 'b work' \
    && cd '$REPO' && echo main > README.md && jj commit -m 'main moves' && jland && jw c"
  [ "$status" -eq 0 ]

  run_zsh "cd '$REPO' && jsync c b"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "c: up to date" ]
  [ "${lines[1]}" = "b: conflicts, left for the agent" ]
  [ "${#lines[@]}" -eq 2 ]
  run jj -R "$WS/b" status
  [ "$status" -eq 0 ]

  run_zsh "cd '$REPO' && jsync b"
  [ "$output" = "b: up to date, conflicts left for the agent" ]
}

@test "jsync: an unknown workspace fails without stopping the others" {
  run_zsh "cd '$REPO' && jw a"
  [ "$status" -eq 0 ]
  run_zsh "cd '$REPO' && jsync nope a"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "nope: no such workspace directory, run: jw nope" ]
  [ "${lines[1]}" = "a: up to date" ]
}

@test "jsync: without arguments picks workspaces with fzf, default included; works without a remote" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ncat > "%s/offered"\necho default\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/fzf"
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  run_zsh "cd '$REPO' && jw a"
  [ "$status" -eq 0 ]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$WS/a' && jsync"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "default: up to date" ]
  [ "$(sort "$BATS_TEST_TMPDIR/offered" | tr '\n' ' ')" = "a default " ]
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

@test "jland: moves main to the latest change and pushes it" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && echo y > f.txt && jj commit -m 'land me' >/dev/null 2>&1 && jland"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "land me" ]
}

@test "jland: lands the given revision" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && echo y > f.txt && jj commit -m 'one' >/dev/null 2>&1 \
    && echo z > g.txt && jj commit -m 'two' >/dev/null 2>&1 && jland @--"
  [ "$status" -eq 0 ]
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = one ]
}

@test "jland: refuses a change without a description and moves nothing" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  before=$(jj -R "$REPO" log -r main --no-graph -T commit_id)
  run_zsh "cd '$REPO' && echo y > f.txt && jland"
  [ "$status" -ne 0 ]
  [[ $output == *"jland: "*"has no description"* ]] || false
  [ "$(jj -R "$REPO" log --ignore-working-copy -r main --no-graph -T commit_id)" = "$before" ]
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = init ]
}

@test "jland: refuses to move main backwards" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && echo y > f.txt && jj commit -m 'one' >/dev/null 2>&1 \
    && echo z > g.txt && jj commit -m 'two' >/dev/null 2>&1 && jland >/dev/null 2>&1 && jland 'main-'"
  [ "$status" -ne 0 ]
  [[ $output == *"backwards"* ]] || false
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = two ]
}

@test "jj tug: in a fresh workspace does not move main" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  main_before=$(jj -R "$REPO" log -r main --no-graph -T commit_id)
  run_zsh "cd '$REPO' && jw t >/dev/null 2>&1 && echo z > t.txt && jj commit -m 'agent' >/dev/null 2>&1 && jj tug"
  [[ $output == *"No bookmarks to update"* || $status -eq 0 ]] || false
  [ "$(jj -R "$REPO" log -r main --no-graph -T commit_id)" = "$main_before" ]
}

@test "jland: outside a jj repo says so instead of blaming the description" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run_zsh "cd '$BATS_TEST_TMPDIR/plain' && jland"
  [ "$status" -ne 0 ]
  [ "$output" = "jland: not in a jj repo" ]
}

# Four agents in four states, plus default: a pushed and behind trunk, c rebased into a
# conflict, p described but not pushed, e empty on top of trunk.
make_agent_states() {
  add_bare_remote "$REPO" "$BATS_TEST_TMPDIR/remote.git"
  run_zsh "cd '$REPO' && jw a && echo a > a.txt && jj commit -m 'a work' && jpush \
    && jw c && echo c > README.md && jj commit -m 'c work' \
    && cd '$REPO' && echo main > README.md && jj commit -m 'main moves' && jland \
    && jj rebase -b c@ -d 'trunk()' \
    && jw p && echo p > p.txt && jj commit -m 'p work' \
    && jw e"
  [ "$status" -eq 0 ]
}

@test "jnext: one ranked row per agent that needs something, then jwst, aligned and read-only" {
  make_agent_states
  ops_before=$(jj -R "$REPO" --ignore-working-copy op log --no-graph -T 'id ++ "\n"' | wc -l)
  echo dirty > "$WS/p/unsaved.txt"

  run_zsh "cd '$WS/p' && jnext"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [[ ${lines[0]} =~ ^c\ +conflicts\ +jws\ +#\ jj\ st\ there,\ or\ tell\ its\ agent$ ]] || false
  [[ ${lines[1]} =~ ^a\ +behind\ trunk\ +jsync\ a\ +#\  ]] || false
  [[ ${lines[2]} =~ ^p\ +not\ pushed\ +jpush\ +#\ from\ its\ workspace ]] || false
  [[ ${lines[3]} =~ ^e\ +no\ work\ +jwrm\ e\ +#\ merged\ or\ abandoned$ ]] || false
  [[ ${lines[4]} =~ ^all\ +status\ +jwst\ +#\ full\ table$ ]] || false
  [[ $output != *default* ]] || false
  # the command and note columns line up
  for l in "${lines[@]}"; do
    [ "$(expr "$l" : '[^#]*')" -eq "$(expr "${lines[0]}" : '[^#]*')" ]
  done
  [ "$(jj -R "$REPO" --ignore-working-copy op log --no-graph -T 'id ++ "\n"' | wc -l)" -eq "$ops_before" ]
  run jj -R "$REPO" --ignore-working-copy file list -r p@
  [[ $output != *unsaved.txt* ]] || false
}

@test "jnext: without agents suggests starting one" {
  run_zsh "cd '$REPO' && jnext"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ ${lines[0]} =~ ^-\ +no\ agents\ +jwc\ feat/\<name\>\ --permission-mode\ plan\ +#\ or\ Ctrl-G,\ start$ ]] || false
  [[ ${lines[1]} =~ ^all\ +status\ +jwst\ +#\ full\ table$ ]] || false
}

@test "jnext: in a git-only repo suggests jj git init, outside any repo fails" {
  mkdir -p "$BATS_TEST_TMPDIR/g" "$BATS_TEST_TMPDIR/plain"
  git -C "$BATS_TEST_TMPDIR/g" init --quiet
  run_zsh "cd '$BATS_TEST_TMPDIR/g' && jnext"
  [ "$status" -eq 0 ]
  [[ $output == *"jj git init --colocate"* ]] || false
  [ "${#lines[@]}" -eq 1 ]
  run_zsh "cd '$BATS_TEST_TMPDIR/plain' && jnext"
  [ "$status" -eq 1 ]
  [ "$output" = "jnext: not in a jj or git repo" ]
}

@test "_jw_hint: one summary line, nothing without agents" {
  run_zsh "cd '$REPO' && _jw_hint"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  make_agent_states
  run_zsh "cd '$REPO' && _jw_hint"
  [ "$status" -eq 0 ]
  [ "$output" = "app: 4 agents · 1 behind trunk · conflicts · jnext" ]
  run_zsh "cd '$WS/a' && _jw_hint"
  [ "$output" = "app: 4 agents · 1 behind trunk · conflicts · jnext" ]
}

@test "_jw_hint: the number of jj calls does not grow with the number of agents" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" | tr "\\n" " " >> "%s/calls"\necho >> "%s/calls"\nexec %s "$@"\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" "$(command -v jj)" > "$BATS_TEST_TMPDIR/bin/jj"
  chmod +x "$BATS_TEST_TMPDIR/bin/jj"
  run_zsh "cd '$REPO' && jw one"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && _jw_hint"
  [ "$output" = "app: 1 agent · jnext" ]
  one=$(wc -l < "$BATS_TEST_TMPDIR/calls")
  run_zsh "cd '$REPO' && jw two && jw three && jw four"
  rm "$BATS_TEST_TMPDIR/calls"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && _jw_hint"
  [ "$output" = "app: 4 agents · jnext" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq "$one" ]
  run grep -vc -- --ignore-working-copy "$BATS_TEST_TMPDIR/calls"
  [ "$output" = 0 ]
}

@test "repo-entry hint: no chpwd hook outside an interactive shell, under Claude Code or with JW_HINT=0" {
  run zsh -f -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=" ]
  run env CLAUDECODE=1 zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=" ]
  run env -u CLAUDECODE JW_HINT=0 zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=" ]
  run env -u CLAUDECODE -u JW_HINT zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=_jw_hint_chpwd" ]
}

@test "repo-entry hint: once per repo per shell, in the main checkout only, including the start directory" {
  run_zsh "cd '$REPO' && jw a"
  mkdir -p "$REPO/sub" "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  run env -u CLAUDECODE -u JW_HINT zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; cd '$WS/a'; cd '$REPO/sub'; cd '$REPO'; cd /; cd '$REPO'"
  echo "$output"
  [ "$output" = "app: 1 agent · jnext" ]
  cd "$REPO"
  run env -u CLAUDECODE -u JW_HINT zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; cd /; cd '$REPO'"
  [ "$output" = "app: 1 agent · jnext" ]
}
