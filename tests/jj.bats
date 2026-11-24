#!/usr/bin/env bats
# zsh/jj.zsh: jw, jwc, jwx, jreview, jwst, jnext, the repo-entry hint, jsync, jwrm, jpush, jland and the `jj tug` alias, in throwaway colocated repos.

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
  [ "${lines[1]}" = "args=-n app/x" ]
  [ "$(parent x)" = second ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc y @-- 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/y" ]
  [ "${lines[1]}" = "args=-n app/y" ]
  [ "$(parent y)" = init ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc feat/z --permission-mode plan 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/feat-z" ]
  [ "${lines[1]}" = "args=-n app/feat-z --permission-mode plan" ]
  [ "$(parent feat-z)" = second ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc w @-- --continue 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/w" ]
  [ "${lines[1]}" = "args=-n app/w --continue" ]
  [ "$(parent w)" = init ]
}

@test "jwc: a second argument with whitespace is the task for claude, not a rev" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "pwd=%%s\\nargc=%%s\\nfirst=%%s\\n" "$(pwd -P)" "$#" "$3"\n' > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  (cd "$REPO" && echo two > two.txt && jj commit -m second >/dev/null 2>&1)
  parent() { jj -R "$REPO" --ignore-working-copy log --no-graph -r "$1@-" -T "description.first_line()"; }

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc x 'fix the retry storm' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/x" ]
  [ "${lines[1]}" = "argc=3" ]
  [ "${lines[2]}" = "first=fix the retry storm" ]
  [ "$(parent x)" = second ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc y @-- 'add the export button' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "pwd=$WS/y" ]
  [ "${lines[1]}" = "argc=3" ]
  [ "${lines[2]}" = "first=add the export button" ]
  [ "$(parent y)" = init ]
}

@test "jwc: claude runs with JW_NAME set to the workspace name" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "JW_NAME=%%s\\n" "$JW_NAME"\n' > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwc fix/x 2>/dev/null; print -r -- \"after=\${JW_NAME:-unset}\""
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "JW_NAME=fix-x" ]
  [ "${lines[1]}" = "after=unset" ]
  [ ! -e "$WS/fix-x/.jw_name" ]
}

@test "jwc: claude runs without the Anthropic key variables and with DOTFILES_AGENT_WORKSPACE=1" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "key=${ANTHROPIC_API_KEY-unset} token=${ANTHROPIC_AUTH_TOKEN-unset} marker=${DOTFILES_AGENT_WORKSPACE-unset}"\n' \
    > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  ANTHROPIC_API_KEY=test-not-a-key ANTHROPIC_AUTH_TOKEN=test-not-a-key PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    run_zsh "cd '$REPO' && jwc x 2>/dev/null; print -r -- \"after=\${DOTFILES_AGENT_WORKSPACE:-unset}\""
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "key=unset token=unset marker=1" ]
  [ "${lines[1]}" = "after=unset" ]
}

@test "jwc: a failing jw never starts claude" {
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/norepo"
  printf '#!/bin/sh\ntouch "%s/claude.ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$BATS_TEST_TMPDIR/norepo' && jwc x"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/claude.ran" ]
}

# stub_codex: a fake codex that logs its arguments (one per line), directory and key variables,
# prints a two-line review and exits with STUB_CODEX_RC (default 0).
stub_codex() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/codex" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$BATS_TEST_TMPDIR/codex.args"
pwd -P > "$BATS_TEST_TMPDIR/codex.cwd"
echo "openai=\${OPENAI_API_KEY-unset} codexkey=\${CODEX_API_KEY-unset} home=\${CODEX_HOME-unset} name=\${JW_NAME-unset} marker=\${DOTFILES_AGENT_WORKSPACE-unset}" > "$BATS_TEST_TMPDIR/codex.env"
echo "review text"
echo "VERDICT: PASS"
exit \${STUB_CODEX_RC:-0}
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/codex"
}

@test "jwx: without ~/.codex/<repo>.config.toml stops before creating the workspace or starting codex" {
  stub_codex
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwx feat/x"
  [ "$status" -eq 1 ]
  [[ $output == *"no ~/.codex/app.config.toml"* ]] || false
  [[ $output == *"codex/repo-profile.example.toml"* ]] || false
  [ ! -e "$WS/feat-x" ]
  [ ! -e "$BATS_TEST_TMPDIR/codex.args" ]
}

# codex_profile [root]: ~/.codex/app.config.toml with root's .jj and .git as writable roots
# (default root: the repo's main checkout as jj reports it).
codex_profile() {
  local root=${1:-$(jj -R "$REPO" --ignore-working-copy workspace root --name default)}
  mkdir -p "$HOME/.codex"
  printf 'sandbox_mode = "workspace-write"\n[sandbox_workspace_write]\nwritable_roots = ["%s/.jj", "%s/.git"]\n' \
    "$root" "$root" > "$HOME/.codex/app.config.toml"
}

@test "jwx: a profile that does not name this checkout's .jj stops it too" {
  stub_codex
  codex_profile '/path/to/<repo>'
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwx feat/x"
  [ "$status" -eq 1 ]
  [[ $output == *"names no writable root for this checkout's .jj"* ]] || false
  codex_profile /elsewhere/app
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwx feat/x"
  [ "$status" -eq 1 ]
  [ ! -e "$WS/feat-x" ]
  [ ! -e "$BATS_TEST_TMPDIR/codex.args" ]
}

@test "jwx: starts codex -p <repo> --add-dir <workspace git dir> in the workspace, keys and CODEX_HOME removed, marker set" {
  stub_codex
  codex_profile
  (cd "$REPO" && echo two > two.txt && jj commit -m second >/dev/null 2>&1)
  OPENAI_API_KEY=test-not-a-key CODEX_API_KEY=test-not-a-key CODEX_HOME="$BATS_TEST_TMPDIR/codexhome" \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwx feat/x @-- 'fix the retry storm' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/codex.cwd")" = "$WS/feat-x" ]
  gitdir=$(git -C "$WS/feat-x" rev-parse --absolute-git-dir)
  [[ $gitdir == */.git/worktrees/feat-x ]] || false
  [ "$(cat "$BATS_TEST_TMPDIR/codex.args")" = "-p"$'\n'"app"$'\n'"--add-dir"$'\n'"$gitdir"$'\n'"fix the retry storm" ]
  [ "$(cat "$BATS_TEST_TMPDIR/codex.env")" = "openai=unset codexkey=unset home=unset name=feat-x marker=1" ]
  [ "$(jj -R "$REPO" --ignore-working-copy log --no-graph -r 'feat-x@-' -T 'description.first_line()')" = init ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jwx feat/x --sandbox workspace-write 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/codex.args")" = "-p"$'\n'"app"$'\n'"--add-dir"$'\n'"$gitdir"$'\n'"--sandbox"$'\n'"workspace-write" ]
}

@test "jwx: a failing jw never starts codex" {
  stub_codex
  mkdir -p "$BATS_TEST_TMPDIR/norepo" "$HOME/.codex"
  touch "$HOME/.codex/norepo.config.toml"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$BATS_TEST_TMPDIR/norepo' && jwx x"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/codex.args" ]
}

# osc <script>: run a zsh script with jj.zsh loaded, escapes made visible (ESC as ^[, BEL as ^G)
osc() { run_zsh "$1"; output=$(cat -v <<<"$output"); }

@test "title: a workspace gets the tab title repo/workspace and a tint in its colour" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  osc "cd '$WS/feat' && _jw_where_chpwd && _jw_title_precmd"
  [ "$status" -eq 0 ]
  echo "output: $output"
  [[ $output == *'^[]2;app/feat^G'* ]] || false
  [[ $output =~ \^\[\]11\;#[0-9a-f]{6}\^G ]] || false
}

@test "title: a new shell's first prompt clears a tint left by the shell it replaced, once" {
  # reload runs exec zsh, which skips zshexit, so the old shell's tint is still on screen.
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  osc "cd '$REPO' && _jw_where_chpwd && _jw_title_precmd && _jw_title_precmd"
  [ "$status" -eq 0 ]
  [ "$(grep -o ']111' <<<"$output" | wc -l | tr -d ' ')" = 1 ]
}

@test "title: the main checkout gets the repo name and no tint, and leaving a workspace resets the tint" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  osc "cd '$REPO' && _jw_where_chpwd && _jw_title_precmd"
  [ "$status" -eq 0 ]
  [[ $output == *'^[]2;app^G'* ]] || false
  [[ $output != *'^[]11;'* ]] || false
  osc "cd '$WS/feat' && _jw_where_chpwd && _jw_title_precmd && cd '$REPO' && _jw_where_chpwd && _jw_title_precmd"
  [[ $output == *'^[]111^G'* ]] || false
  osc "cd '$WS/feat' && _jw_where_chpwd && _jw_title_precmd && _jw_title_precmd"
  [ "$(grep -o ']11;' <<<"$output" | wc -l | tr -d ' ')" = 1 ]
}

@test "title: JW_TINT=0 keeps the title but never tints" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  osc "JW_TINT=0; cd '$WS/feat' && _jw_where_chpwd && _jw_title_precmd"
  [[ $output == *'^[]2;app/feat^G'* ]] || false
  [[ $output != *'^[]11;'* ]] || false
}

@test "title: outside a repo the title is the ~-relative dir, and a command is appended while it runs" {
  mkdir -p "$HOME/outside"
  osc "cd '$HOME/outside' && _jw_where_chpwd && _jw_title_precmd && _jw_title_preexec 'just test'"
  [[ $output == *'^[]2;~/outside^G'* ]] || false
  [[ $output == *'^[]2;~/outside · just test^G'* ]] || false
  osc "cd '$HOME/outside' && _jw_where_chpwd && _jw_title_preexec \$'for x in 1\\n2\\e]0;evil'"
  echo "output: $output"
  [ "$output" = '^[]2;~/outside · for x in 1 2 ]0;evil^G' ]
}

@test "title: outside a repo the hook never runs where.sh, inside one it does" {
  mkdir -p "$HOME/outside/deep" "$REPO/sub"
  stub="$BATS_TEST_TMPDIR/where-stub"
  printf '#!/bin/sh\necho called >> "%s.log"\nexec bash "%s" "$@"\n' "$stub" "$REPO_ROOT/claude/where.sh" > "$stub"
  chmod +x "$stub"
  run_zsh "_jw_where_sh='$stub'; cd '$HOME/outside/deep' && _jw_where_chpwd && print -r -- \${JW_WHERE:-unset}"
  [ "$status" -eq 0 ]
  [ "$output" = unset ]
  [ ! -e "$stub.log" ]
  run_zsh "_jw_where_sh='$stub'; cd '$REPO/sub' && _jw_where_chpwd"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$stub.log" | tr -d ' ')" = 1 ]
}

@test "title: JW_WHERE is exported in a workspace and unset in the main checkout" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  run_zsh "cd '$WS/feat' && _jw_where_chpwd && zsh -fc 'print -r -- \${JW_WHERE:-unset}'; cd '$REPO' && _jw_where_chpwd && zsh -fc 'print -r -- \${JW_WHERE:-unset}'"
  [ "${lines[0]}" = app/feat ]
  [ "${lines[1]}" = unset ]
}

@test "slot: workspaces get the lowest free slot, kept in .jj, and a removed one frees it" {
  run_zsh "cd '$REPO' && jw one >/dev/null 2>&1 && jw two >/dev/null 2>&1"
  run_zsh "_jw_slot '$WS/one'; _jw_slot '$WS/two'; _jw_slot '$WS/one'"
  [ "$status" -eq 0 ]
  [ "$output" = $'1\n2\n1' ]
  [ "$(cat "$WS/two/.jj/jw-slot")" = 2 ]
  run jj -R "$WS/two" st
  [[ $output != *jw-slot* ]] || false
  run_zsh "cd '$REPO' && jwrm one >/dev/null 2>&1 && jw three >/dev/null 2>&1 && _jw_slot '$WS/three'"
  [ "$output" = 1 ]
}

@test "slot: a workspace exports JW_SLOT, JW_PORT_BASE and PORT, leaving it restores your PORT" {
  run_zsh "cd '$REPO' && jw one >/dev/null 2>&1"
  run_zsh "export PORT=8080; cd '$WS/one' && _jw_where_chpwd && zsh -fc 'print -r -- \$JW_SLOT \$JW_PORT_BASE \$PORT'; \
    cd '$REPO' && _jw_where_chpwd && zsh -fc 'print -r -- \${JW_SLOT:-unset} \${JW_PORT_BASE:-unset} \$PORT'"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1 10100 10100" ]
  [ "${lines[1]}" = "unset unset 8080" ]
  run_zsh "cd '$WS/one' && _jw_where_chpwd && cd '$HOME' && _jw_where_chpwd && print -r -- \${PORT:-unset}"
  [ "$output" = unset ]
}

@test "slot: the main checkout and a git worktree get no slot" {
  git -C "$REPO" worktree add -q "$HOME/src/wt" >/dev/null 2>&1
  run_zsh "cd '$REPO' && _jw_where_chpwd && print -r -- \${JW_SLOT:-none}; cd '$HOME/src/wt' && _jw_where_chpwd && print -r -- \${JW_SLOT:-none}"
  [ "$status" -eq 0 ]
  [ "$output" = $'none\nnone' ]
  [ ! -e "$REPO/.jj/jw-slot" ]
}

@test "title: a cd in \$(...) or with redirected output prints nothing, and the next prompt tints" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  run env -u CLAUDECODE JW_HINT=0 zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; x=\$(cd '$WS/feat' && pwd -P); print -r -- \"x=\$x\"; cd '$WS/feat' >/dev/null; print -r -- tinted=\${_jw_tint_shown:-no}; _jw_title_precmd"
  output=$(cat -v <<<"$output")
  echo "output: $output"
  [ "${lines[0]}" = "x=$WS/feat" ]
  [[ $output == *"tinted=unknown"* ]] || false
  [[ $output =~ \^\[\]11\;#[0-9a-f]{6}\^G ]] || false
}

@test "jreview: runs a read-only claude -p in the workspace on the trunk()..@ diff" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\npwd -P > "%s/claude.cwd"\nprintf "%%s\\n" "$@" > "%s/claude.args"\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  run_zsh "cd '$REPO' && jw feat/x >/dev/null 2>&1 && echo x > x.txt && jw other >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$WS/other' && jreview feat/x 'focus on the retry logic' && pwd -P"
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == "jreview: reviewing feat-x"* ]] || false
  [ "${lines[1]}" = "$WS/other" ]
  [ "$(cat "$BATS_TEST_TMPDIR/claude.cwd")" = "$WS/feat-x" ]
  args=$(cat "$BATS_TEST_TMPDIR/claude.args")
  grep -qx -- -p "$BATS_TEST_TMPDIR/claude.args"
  allowed=$(sed -n '/^--allowedTools$/{n;p;}' "$BATS_TEST_TMPDIR/claude.args")
  [[ $allowed == *Read* && $allowed == *'Bash(jj diff *)'* ]] || false
  [[ $allowed != *Edit* && $allowed != *Write* ]] || false
  [[ $args == *"trunk()..@"* ]] || false
  [[ $args == *"focus on the retry logic"* ]] || false
}

@test "jreview: an unknown workspace fails; without a name picks with fzf, default left out" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\npwd -P > "%s/claude.cwd"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  printf '#!/bin/sh\ncat > "%s/offered"\necho a\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/fzf"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude" "$BATS_TEST_TMPDIR/bin/fzf"
  run_zsh "cd '$REPO' && jw a >/dev/null 2>&1 && echo a > a.txt"
  [ "$status" -eq 0 ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview nope"
  [ "$status" -eq 1 ]
  [[ $output == *"nope"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/claude.cwd" ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/offered")" = "a" ]
  [ "$(cat "$BATS_TEST_TMPDIR/claude.cwd")" = "$WS/a" ]
}

@test "jreview: a workspace with no changes since trunk() stops without running claude" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ntouch "%s/claude.ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  add_bare_remote "$REPO" "$BATS_TEST_TMPDIR/remote.git"
  run_zsh "cd '$REPO' && jw idle >/dev/null 2>&1"
  [ "$status" -eq 0 ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview idle"
  [ "$status" -eq 1 ]
  [[ $output == *"jreview: idle has no changes since trunk()"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/claude.ran" ]
}

@test "jreview: claude gets --model fable by default, before the tool lists, without the Anthropic keys" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/claude.args"\necho "key=${ANTHROPIC_API_KEY-unset} token=${ANTHROPIC_AUTH_TOKEN-unset}" > "%s/claude.env"\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  run_zsh "cd '$REPO' && jw a >/dev/null 2>&1 && echo a > a.txt"
  [ "$status" -eq 0 ]
  args() { cat "$BATS_TEST_TMPDIR/claude.args"; }
  model() { sed -n '/^--model$/{n;p;}' "$BATS_TEST_TMPDIR/claude.args"; }

  ANTHROPIC_API_KEY=test-not-a-key ANTHROPIC_AUTH_TOKEN=test-not-a-key PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    run_zsh "cd '$REPO' && jreview a"
  [ "$status" -eq 0 ]
  [ "$(model)" = fable ]
  (( $(grep -nx -- --model "$BATS_TEST_TMPDIR/claude.args" | cut -d: -f1) < $(grep -nx -- --allowedTools "$BATS_TEST_TMPDIR/claude.args" | cut -d: -f1) )) || false
  [ "$(cat "$BATS_TEST_TMPDIR/claude.env")" = "key=unset token=unset" ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --model opus a"
  [ "$status" -eq 0 ]
  [ "$(model)" = opus ]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --model=sonnet a"
  [ "$status" -eq 0 ]
  [ "$(model)" = sonnet ]
  [[ $(args) != *--codex* ]] || false
}

@test "jreview --codex: a read-only codex exec in the workspace, keys removed, its stdout and exit status as is" {
  stub_codex
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ntouch "%s/claude.ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  run_zsh "cd '$REPO' && jw feat/x >/dev/null 2>&1 && echo x > x.txt"
  [ "$status" -eq 0 ]

  OPENAI_API_KEY=test-not-a-key CODEX_API_KEY=test-not-a-key CODEX_HOME="$BATS_TEST_TMPDIR/codexhome" \
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --codex feat/x 'the retry logic' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = $'review text\nVERDICT: PASS' ]
  [ "$(cat "$BATS_TEST_TMPDIR/codex.cwd")" = "$WS/feat-x" ]
  [ "$(sed -n 1,4p "$BATS_TEST_TMPDIR/codex.args")" = $'exec\n-s\nread-only\n--ephemeral' ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/codex.args")" -eq 5 ]
  prompt=$(sed -n 5p "$BATS_TEST_TMPDIR/codex.args")
  [[ $prompt == *"jj --ignore-working-copy diff --git -r 'trunk()..@'"* ]] || false
  [[ $prompt == *"Focus: the retry logic" ]] || false
  [[ $(cat "$BATS_TEST_TMPDIR/codex.env") == "openai=unset codexkey=unset home=unset "* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/claude.ran" ]

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --codex --model gpt-x feat/x 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1,6p "$BATS_TEST_TMPDIR/codex.args")" = $'exec\n-s\nread-only\n--ephemeral\n-m\ngpt-x' ]

  STUB_CODEX_RC=3 PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --codex feat/x 2>/dev/null"
  [ "$status" -eq 3 ]
  [ "$(grep -c 'VERDICT:' <<<"$output")" -eq 1 ]
}

@test "jreview: a missing --model value or an unknown option fails, -- ends the options" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ntouch "%s/claude.ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --model"
  [ "$status" -eq 2 ]
  [[ $output == *"--model needs a model name"* ]] || false
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --model --codex a"
  [ "$status" -eq 2 ]
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview --bogus a"
  [ "$status" -eq 2 ]
  [[ $output == *"usage: jreview"* ]] || false
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jreview -- -odd"
  [ "$status" -eq 1 ]
  [[ $output == *"jreview: no workspace named -odd"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/claude.ran" ]
}

# stub_gate <check exit> <verdict>: fake just (a check recipe exiting with <check exit>) and a
# fake claude whose review ends with VERDICT: <verdict>, both logging that they ran.
stub_gate() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n[ "$1" = --summary ] && { echo check; exit 0; }\ntouch "%s/check.ran"\nexit %s\n' \
    "$BATS_TEST_TMPDIR" "$1" > "$BATS_TEST_TMPDIR/bin/just"
  printf '#!/bin/sh\ntouch "%s/claude.ran"\necho "looks fine"\necho\necho "VERDICT: %s"\n' \
    "$BATS_TEST_TMPDIR" "$2" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/just" "$BATS_TEST_TMPDIR/bin/claude"
}

@test "jdone: outside an agent workspace refuses" {
  run_zsh "cd '$REPO' && jdone"
  [ "$status" -eq 1 ]
  [[ $output == *"jdone: run it in an agent's jj workspace"* ]] || false
}

@test "jdone: a failing check stops before the review and the push" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  stub_gate 1 PASS
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && touch justfile && echo y > f.txt && jj commit -m feature >/dev/null 2>&1 && jdone"
  [ "$status" -eq 1 ]
  [[ $output == *"the check failed"* ]] || false
  [ -e "$BATS_TEST_TMPDIR/check.ran" ]
  [ ! -e "$BATS_TEST_TMPDIR/claude.ran" ]
  run git -C "$remote" rev-parse --verify -q refs/heads/feat
  [ "$status" -ne 0 ]
}

@test "jdone: a blocking review stops the push, a passing one pushes" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  stub_gate 0 BLOCK
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && touch justfile && echo y > f.txt && jj commit -m feature >/dev/null 2>&1 && jdone"
  [ "$status" -eq 1 ]
  echo "output: $output"
  [[ $output == *"VERDICT: BLOCK"* ]] || false
  [[ $output == *"the review did not pass"* ]] || false
  run git -C "$remote" rev-parse --verify -q refs/heads/feat
  [ "$status" -ne 0 ]

  stub_gate 0 PASS
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$WS/feat' && jdone"
  [ "$status" -eq 0 ]
  run git -C "$remote" log -1 --format=%s refs/heads/feat
  [ "$output" = feature ]
}

@test "jdone: a review that is only the verdict line passes" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  stub_gate 0 PASS
  printf '#!/bin/sh\necho "VERDICT: PASS"\n' > "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && touch justfile && echo y > f.txt && jj commit -m feature >/dev/null 2>&1 && jdone"
  echo "output: $output"
  [ "$status" -eq 0 ]
  run git -C "$remote" log -1 --format=%s refs/heads/feat
  [ "$output" = feature ]
}

@test "jdone: a last line that only contains VERDICT: PASS, or a failing reviewer, does not push" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  stub_gate 0 PASS
  printf '#!/bin/sh\necho "looks fine"\necho "VERDICT: BLOCK (previous VERDICT: PASS withdrawn)"\n' > "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && touch justfile && echo y > f.txt && jj commit -m feature >/dev/null 2>&1 && jdone"
  [ "$status" -eq 1 ]
  [[ $output == *"the review did not pass"* ]] || false
  run git -C "$remote" rev-parse --verify -q refs/heads/feat
  [ "$status" -ne 0 ]

  printf '#!/bin/sh\necho "VERDICT: PASS"\nexit 7\n' > "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$WS/feat' && jdone"
  [ "$status" -eq 1 ]
  [[ $output == *"the review did not pass"* ]] || false
  run git -C "$remote" rev-parse --verify -q refs/heads/feat
  [ "$status" -ne 0 ]
}

@test "jdone: words that look like jreview options are focus for the Claude review" {
  add_bare_remote "$REPO" "$BATS_TEST_TMPDIR/remote.git"
  stub_gate 0 PASS
  stub_codex
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/claude.args"\necho "looks fine"\necho "VERDICT: PASS"\n' \
    "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && touch justfile && echo y > f.txt && jj commit -m feature >/dev/null 2>&1 && jdone --codex"
  echo "output: $output"
  [ "$status" -eq 0 ]
  grep -q 'Focus: --codex' "$BATS_TEST_TMPDIR/claude.args"
  [ ! -e "$BATS_TEST_TMPDIR/codex.args" ]
}

@test "jwrm --merged: removes workspaces with no work, keeps ones with work or in use" {
  add_bare_remote "$REPO" "$BATS_TEST_TMPDIR/remote.git"
  run_zsh "cd '$REPO' && jw done >/dev/null 2>&1 && jw busy >/dev/null 2>&1 && jw work >/dev/null 2>&1 && echo w > w.txt"
  [ "$status" -eq 0 ]
  (cd "$WS/busy" && exec sleep 30) &
  sleeper=$!
  run_zsh "cd '$WS/done' && jwrm --merged && pwd -P"
  kill $sleeper 2>/dev/null || true
  echo "output: $output"
  [ "$status" -eq 0 ]
  [[ $output == *"jwrm: busy is in use, skipped"* ]] || false
  [ "${lines[${#lines[@]}-1]}" = "$(realpath_of "$REPO")" ]
  [ ! -e "$WS/done" ]
  [ -d "$WS/busy" ]
  [ -d "$WS/work" ]
  run_zsh "cd '$REPO' && jwrm --merged"
  [ "$status" -eq 0 ]
  [ ! -e "$WS/busy" ]
  [ -d "$WS/work" ]
}

@test "jw: installs a pre-push hook that stops agents pushing from a workspace, not you or the main checkout" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw feat"
  [ "$status" -eq 0 ]
  hook="$REPO/.git/hooks/pre-push"
  [ -x "$hook" ]
  grep -q 'jw-pre-push' "$hook"

  run env CLAUDECODE=1 git -C "$WS/feat" push "$remote" HEAD:refs/heads/agent
  [ "$status" -ne 0 ]
  [[ $output == *"agents in jj workspaces and git worktrees do not push"* ]] || false
  run env -u CLAUDECODE git -C "$WS/feat" push "$remote" HEAD:refs/heads/me
  [ "$status" -eq 0 ]
  run env CLAUDECODE=1 git -C "$REPO" push "$remote" HEAD:refs/heads/main-checkout
  [ "$status" -eq 0 ]
}

@test "jw: leaves a pre-push hook of your own and a core.hooksPath setup alone" {
  mkdir -p "$REPO/.git/hooks"
  printf '#!/bin/sh\necho mine\n' > "$REPO/.git/hooks/pre-push"
  run_zsh "cd '$REPO' && jw a"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/.git/hooks/pre-push")" = $'#!/bin/sh\necho mine' ]
  [[ $output == *"pre-push"*"not adding"* ]] || false

  rm "$REPO/.git/hooks/pre-push"
  git -C "$REPO" config core.hooksPath .githooks
  run_zsh "cd '$REPO' && jw b"
  [ "$status" -eq 0 ]
  [ ! -e "$REPO/.git/hooks/pre-push" ]
  [ ! -e "$REPO/.githooks/pre-push" ]
}

@test "jw: the pre-push hook blocks a workspace push for each agent variable alone, not a main-checkout push" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw feat"
  [ "$status" -eq 0 ]
  local v
  for v in CLAUDECODE CODEX_SANDBOX CODEX_THREAD_ID CODEX_CI OPENCODE DOTFILES_AGENT_WORKSPACE; do
    run env "$v=1" git -C "$WS/feat" push "$remote" "HEAD:refs/heads/agent-$v"
    [ "$status" -ne 0 ] || { echo "$v did not block"; return 1; }
    [[ $output == *"agents in jj workspaces and git worktrees do not push"* ]] || false
    run env "$v=1" git -C "$REPO" push "$remote" "HEAD:refs/heads/main-$v"
    [ "$status" -eq 0 ] || { echo "$v blocked the main checkout: $output"; return 1; }
  done
  run git -C "$WS/feat" push "$remote" HEAD:refs/heads/me
  [ "$status" -eq 0 ]
}

@test "jw: the pre-push hook never sees jj git push, so jpush works for an agent in a workspace" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  add_bare_remote "$REPO" "$remote"
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1 && echo y > f.txt && jj commit -m feature >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  grep -q 'jw-pre-push' "$REPO/.git/hooks/pre-push"
  run env CLAUDECODE=1 DOTFILES_AGENT_WORKSPACE=1 git -C "$WS/feat" push "$remote" HEAD~1:refs/heads/by-git
  [ "$status" -ne 0 ]
  CLAUDECODE=1 DOTFILES_AGENT_WORKSPACE=1 run_zsh "cd '$WS/feat' && jpush"
  echo "output: $output"
  [ "$status" -eq 0 ]
  run git -C "$remote" log -1 --format=%s refs/heads/feat
  [ "$output" = feature ]
}

@test "jw: reusing a workspace replaces an older jw hook, keeps a current one, leaves no temp file" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  hook="$REPO/.git/hooks/pre-push"
  printf '#!/bin/sh\n# jw-pre-push, old\n[ -n "$CLAUDECODE" ] || exit 0\nexit 1\n' > "$hook"
  run_zsh "cd '$REPO' && jw feat"
  [ "$status" -eq 0 ]
  grep -q 'CODEX_THREAD_ID' "$hook"
  [ -x "$hook" ]
  inode=$(ls -i "$hook" | awk '{print $1}')
  run_zsh "cd '$REPO' && jw feat"
  [ "$status" -eq 0 ]
  [ "$(ls -i "$hook" | awk '{print $1}')" = "$inode" ]
  [ -z "$(find "$REPO/.git/hooks" -name '.pre-push.*')" ]
}

@test "jw: reusing a workspace leaves a hook of your own and a symlinked hook alone" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  hook="$REPO/.git/hooks/pre-push"
  printf '#!/bin/sh\necho mine\n' > "$hook"
  run_zsh "cd '$REPO' && jw feat"
  [ "$status" -eq 0 ]
  [ "$(cat "$hook")" = $'#!/bin/sh\necho mine' ]

  printf '#!/bin/sh\n# jw-pre-push, old\nexit 0\n' > "$BATS_TEST_TMPDIR/shared-hook"
  rm "$hook"
  ln -s "$BATS_TEST_TMPDIR/shared-hook" "$hook"
  run_zsh "cd '$REPO' && jw feat"
  [ "$status" -eq 0 ]
  [ -L "$hook" ]
  [ "$(cat "$BATS_TEST_TMPDIR/shared-hook")" = $'#!/bin/sh\n# jw-pre-push, old\nexit 0' ]
}

@test "jw: a hook it cannot write makes jw fail instead of keeping the old guard" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  printf '#!/bin/sh\n# jw-pre-push, old\nexit 0\n' > "$REPO/.git/hooks/pre-push"
  chmod 555 "$REPO/.git/hooks"
  run_zsh "cd '$REPO' && jw feat && pwd -P"
  chmod 755 "$REPO/.git/hooks"
  [ "$status" -eq 1 ]
  [[ $output == *"jw: could not install the agent pre-push hook"* ]] || false
  [ "$(cat "$REPO/.git/hooks/pre-push")" = $'#!/bin/sh\n# jw-pre-push, old\nexit 0' ]
}

@test "jwst: colours workspace names when its output is a real terminal" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  colour=$(bash "$REPO_ROOT/claude/where.sh" --colour app/feat)
  # script(1) gives jwst a pty: the case CLICOLOR_FORCE does not cover.
  run script -q /dev/null zsh -f -c "source '$REPO_ROOT/zsh/jj.zsh'; cd '$REPO' && jwst" </dev/null
  echo "$output" | cat -v
  [[ $output == *$'\e[1;3'"$colour"'mfeat'* ]] || false
}

@test "jwst and jws: workspace names in their where.sh colour, default plain, only with colour on" {
  run_zsh "cd '$REPO' && jw feat >/dev/null 2>&1"
  colour=$(bash "$REPO_ROOT/claude/where.sh" --colour app/feat)
  run_zsh "cd '$REPO' && jwst"
  [[ $output != *$'\e['* ]] || false
  CLICOLOR_FORCE=1 run_zsh "cd '$REPO' && jwst"
  echo "$output" | cat -v
  [[ ${lines[1]} == default* ]] || false
  [[ $output == *$'\e[1;3'"$colour"'mfeat'* ]] || false
  NO_COLOR=1 CLICOLOR_FORCE=1 run_zsh "cd '$REPO' && jwst"
  [[ $output != *$'\e['* ]] || false

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ncat > "%s/fzf.in"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/fzf"
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_zsh "cd '$REPO' && jws"
  cat -v "$BATS_TEST_TMPDIR/fzf.in"
  grep -q $'^default\t' "$BATS_TEST_TMPDIR/fzf.in"
  grep -q $'^\e\\[1;3'"$colour"$'mfeat\e\\[0m\t' "$BATS_TEST_TMPDIR/fzf.in"
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

@test "repo-entry hint: no hint hook outside an interactive shell, under Claude Code or with JW_HINT=0" {
  # The hint also fires for the start directory: start outside any repo, not in this checkout.
  cd "$HOME"
  run zsh -f -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=" ]
  run env CLAUDECODE=1 zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=" ]
  run env -u CLAUDECODE JW_HINT=0 zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=_jw_where_chpwd" ]
  run env -u CLAUDECODE -u JW_HINT zsh -f -i -c "source '$REPO_ROOT/zsh/jj.zsh'; print -r -- \"hooks=\${chpwd_functions[*]}\""
  [ "$output" = "hooks=_jw_where_chpwd _jw_hint_chpwd" ]
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
