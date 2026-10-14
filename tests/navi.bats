#!/usr/bin/env bats
# navi runs picker commands ($ var: ...) in bash, not zsh, so pickers must call real
# programs. Commands may use zsh functions (jw, jpush, infra): Ctrl-G inserts them
# into the zsh prompt.

load helpers

CHEATS="$REPO_ROOT/navi"

setup() {
  fake_home
  command -v navi >/dev/null || skip "navi not installed"
}

# entries <file>: "description<TAB>command" for every entry.
entries() {
  awk '/^# / { desc = substr($0, 3); next }
       desc != "" && NF { print desc "\t" $0; desc = "" }' "$1"
}

# pickers <file>: "name<TAB>shell command" for every $ var: line (options after --- dropped).
pickers() {
  awk '/^\$ [a-z_]+:/ {
         name = $2; sub(/:$/, "", name)
         cmd = $0; sub(/^\$ [a-z_]+: */, "", cmd); sub(/ --- .*$/, "", cmd)
         print name "\t" cmd
       }' "$1"
}

@test "navi: every entry renders with values for all its <vars>" {
  local file desc cmd expected var out
  for file in "$CHEATS"/*.cheat; do
    while IFS=$'\t' read -r desc cmd; do
      expected=$cmd
      # Query with a prefix: without a terminal navi cuts descriptions to a column
      # width, so a long full query matches nothing. The exact output check below
      # still catches a wrong match.
      local -a envs=()
      for var in $(grep -oE '<[a-z_]+>' <<<"$cmd" | tr -d '<>' | sort -u); do
        envs+=("$var=V_$var")
        expected=${expected//<$var>/V_$var}
      done
      # stdout only: without a terminal navi warns on stderr (stty), which is noise here.
      out=$(env "${envs[@]}" perl -e 'alarm 10; exec @ARGV' navi --path "$CHEATS" --print --best-match --query "${desc:0:30}" </dev/null 2>"$BATS_TEST_TMPDIR/navi.err") || {
        echo "navi failed for '$desc' in ${file##*/}: $(cat "$BATS_TEST_TMPDIR/navi.err")"; return 1; }
      [ "$out" = "$expected" ] || {
        echo "${file##*/}: '$desc'"; echo "expected: $expected"; echo "got:      $out"; return 1; }
    done < <(entries "$file")
  done
}

@test "navi: descriptions are unique across all cheats" {
  dups=$(for f in "$CHEATS"/*.cheat; do entries "$f" | cut -f1; done | sort | uniq -d)
  [ -z "$dups" ] || { echo "duplicate descriptions: $dups"; return 1; }
}

@test "navi: pickers call no zsh functions (navi runs them in bash)" {
  bad=$(for f in "$CHEATS"/*.cheat; do pickers "$f" | cut -f2 | sed "s|^|${f##*/}: |"; done |
    grep -E '(^|[^a-z_-])(jw|jwc|jws|jwl|jwrm|jpush|infra|sign-as|z|zi)( |$)' || true)
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

@test "navi: every jj picker uses --ignore-working-copy (no snapshots, no signing prompts)" {
  bad=$(for f in "$CHEATS"/*.cheat; do pickers "$f" | cut -f2; done |
    grep -E '(^|[|;&] *)jj ' | grep -v -- '--ignore-working-copy' || true)
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

@test "navi: destructive infra entries are labelled [LOCAL ONLY] and target localhost" {
  while IFS=$'\t' read -r desc cmd; do
    if grep -qE -- '--delete|FLUSH|infra reset' <<<"$cmd"; then
      [[ $desc == "[LOCAL ONLY]"* ]] || { echo "unlabelled: $desc"; return 1; }
    fi
    if grep -qE 'kcat|redis-cli|bootstrap-server' <<<"$cmd"; then
      grep -q 'localhost' <<<"$cmd" || { echo "not localhost: $cmd"; return 1; }
    fi
  done < <(entries "$CHEATS/infra.cheat")
}

@test "navi: direct pushes to main are labelled [PERSONAL]" {
  while IFS=$'\t' read -r desc cmd; do
    if grep -q 'git push -b main' <<<"$cmd"; then
      [[ $desc == "[PERSONAL]"* ]] || { echo "unlabelled: $desc"; return 1; }
    fi
  done < <(for f in "$CHEATS"/*.cheat; do entries "$f"; done)
}

@test "navi: local pickers run in bash and print values" {
  make_jj_repo "$HOME/src/app"
  cd "$HOME/src/app" || return 1
  jj bookmark create feat -r @- >/dev/null 2>&1 || return 1
  mkdir -p ../app-ws && jj workspace add --name agent-1 ../app-ws/agent-1 >/dev/null 2>&1 || return 1
  cd ../app-ws/agent-1 || return 1
  local f name cmd out
  for f in "$CHEATS"/*.cheat; do
    while IFS=$'\t' read -r name cmd; do
      # Pickers that need a live service or account are covered by hand, not here.
      if grep -qE 'docker|kubectl|gh |go list|redis-cli' <<<"$cmd"; then continue; fi
      out=$(bash -c "$cmd" 2>&1) || { echo "${f##*/} \$ $name failed: $out"; return 1; }
      [ -n "$out" ] || { echo "${f##*/} \$ $name printed nothing"; return 1; }
    done < <(pickers "$f")
  done
}

@test "navi: picking a change inserts only its id (column 1 of a tab-separated picker)" {
  command -v expect >/dev/null || skip "expect not installed"
  make_jj_repo "$HOME/src/app"
  cd "$HOME/src/app" || return 1
  id=$(jj --ignore-working-copy log --no-graph -r 'description(init)' -T 'change_id.shortest(8)')
  run expect -c "
    set timeout 15
    spawn navi --path $CHEATS --print --best-match --query {Abandon a change}
    expect -re {.+}
    send -- {init}
    sleep 1
    send -- \"\r\"
    expect eof
  "
  [[ $output == *"jj abandon $id"* ]] || { echo "want 'jj abandon $id' in:"; echo "$output"; return 1; }
}

# navi_zsh <dir> <script>: source navi.zsh inside <dir>, then run <script>.
navi_zsh() {
  run zsh -f -c "cd '$1' || exit 1; source '$REPO_ROOT/zsh/navi.zsh'; $2"
}

@test "navi.zsh: an untrusted repo's .navi/ is not loaded" {
  make_jj_repo "$HOME/work/app"
  mkdir -p "$HOME/work/app/.navi"
  navi_zsh "$HOME/work/app" 'print -r -- "path=${NAVI_PATH-unset}"'
  [ "$status" -eq 0 ]
  [ "$output" = "path=unset" ]
}

@test "navi.zsh: repos under DOTFILES_PERSONAL_DIR are trusted, default folder first" {
  make_jj_repo "$HOME/src/mine/app"
  mkdir -p "$HOME/src/mine/app/.navi"
  export DOTFILES_PERSONAL_DIR="$HOME/src/mine"
  navi_zsh "$HOME/src/mine/app" 'print -r -- "$NAVI_PATH"'
  [ "$status" -eq 0 ]
  [[ $output == "$HOME/.local/share/navi/cheats:"*"/src/mine/app/.navi" ]]
}

@test "navi.zsh: without DOTFILES_PERSONAL_DIR nothing is trusted automatically" {
  make_jj_repo "$HOME/src/mine/app"
  mkdir -p "$HOME/src/mine/app/.navi"
  unset DOTFILES_PERSONAL_DIR
  navi_zsh "$HOME/src/mine/app" 'print -r -- "path=${NAVI_PATH-unset}"'
  [ "$output" = "path=unset" ]
}

@test "navi.zsh: navi-trust and navi-untrust toggle a work repo" {
  make_jj_repo "$HOME/work/app"
  mkdir -p "$HOME/work/app/.navi"
  navi_zsh "$HOME/work/app" 'navi-trust >/dev/null; print -r -- "after-trust=${NAVI_PATH-unset}";
    navi-untrust >/dev/null; print -r -- "after-untrust=${NAVI_PATH-unset}"'
  [ "$status" -eq 0 ]
  [[ ${lines[0]} == after-trust=*"/.navi" ]]
  [ "${lines[1]}" = "after-untrust=unset" ]
  [ -f "$HOME/.config/navi/trusted-repos" ]
  ! grep -q . "$HOME/.config/navi/trusted-repos"
}

@test "navi.zsh: a workspace of a trusted repo loads its own .navi/" {
  make_jj_repo "$HOME/work/app"
  (cd "$HOME/work/app" && mkdir -p .navi && printf '%% x\n' > .navi/x.cheat &&
    jj commit -m navi >/dev/null 2>&1 && mkdir -p ../app-ws && jj workspace add --name w1 ../app-ws/w1 >/dev/null 2>&1) || return 1
  navi_zsh "$HOME/work/app" 'navi-trust >/dev/null; cd ../app-ws/w1 && print -r -- "$NAVI_PATH"'
  [ "$status" -eq 0 ]
  [[ $output == *"/app-ws/w1/.navi" ]]
}
