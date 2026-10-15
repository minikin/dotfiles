#!/usr/bin/env bats
# scripts/check-commits.sh: Conventional Commits subjects in a git range.

load helpers

setup() {
  fake_home
  repo="$BATS_TEST_TMPDIR/repo"
  git init --quiet -b main "$repo"
  git -C "$repo" commit --quiet --allow-empty -m "Legacy subject before the convention"
  base=$(git -C "$repo" rev-parse HEAD)
}

commit() { git -C "$repo" commit --quiet --allow-empty -m "$1"; }

check() {
  run bash -c "cd '$repo' && '$REPO_ROOT/scripts/check-commits.sh' '$base..HEAD'"
}

@test "commits: conventional subjects pass" {
  commit "feat(zsh): add jwx"
  commit "fix: handle empty input"
  commit "docs: explain drift"
  commit "refactor(install)!: rename the identity file"
  check
  [ "$status" -eq 0 ]
  [[ $output == *"4 commits ok"* ]] || false
}

@test "commits: a subject without a type fails and is named" {
  commit "feat(zsh): add jwx"
  commit "zsh: old style subject"
  check
  [ "$status" -eq 1 ]
  [[ $output == *"zsh: old style subject"* ]] || false
  [[ $output != *"add jwx"* ]] || false
}

@test "commits: unknown type, uppercase scope and missing summary fail" {
  for s in "feature: x" "fix(ZSH): x" "fix(zsh):" "fix(zsh) x"; do
    git -C "$repo" reset --quiet --hard "$base"
    commit "$s"
    check
    [ "$status" -eq 1 ] || { echo "accepted: $s"; false; }
  done
}

@test "commits: commits before the range are not checked" {
  check
  [ "$status" -eq 0 ]
  [[ $output == *"0 commits ok"* ]] || false
}

@test "commits: merge commits are skipped" {
  git -C "$repo" checkout --quiet -b side
  commit "fix: on side"
  git -C "$repo" checkout --quiet main
  commit "fix: on main"
  git -C "$repo" merge --quiet --no-ff -m "Merge branch 'side'" side
  check
  [ "$status" -eq 0 ]
}
