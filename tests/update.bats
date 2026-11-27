#!/usr/bin/env bats
# bin/dotfiles-update against stub brew, agy, mise, uv, rustup, mas, codex, claude, go and cargo.

load helpers

setup() {
  fake_home
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$STUB_LOG"
  export DOTFILES_DIR="$REPO_ROOT"
  command -v jq >/dev/null && ln -s "$(command -v jq)" "$STUBS/jq"
  for tool in brew agy mise uv rustup mas; do
    stub "$tool" <<'EOF'
[[ $1 == --version ]] && { echo "$(basename "$0") 9.9.9"; exit 0; }
[[ " $* " == *" ls --global --json "* ]] && { echo '{"go:example.org/tool":[{"installed":false}],"cargo:example-crate":[{"installed":true}],"cargo:missing-crate":[{"installed":false}],"node":[{"installed":true}],"yq":[{"installed":false}]}'; exit 0; }
echo "$(basename "$0") $* cwd=$PWD" >>"$STUB_LOG"
if [[ " ${STUB_FAIL:-} " == *" $(basename "$0") "* ]]; then
  [[ -n ${STUB_ERROR:-} ]] && echo "$STUB_ERROR"
  exit 3
fi
exit 0
EOF
  done
  stub codex <<'EOF'
echo "codex-cli 9.9.9"
EOF
  stub claude <<'EOF'
echo "9.9.9 (Claude Code)"
EOF
}

stub() {
  { echo '#!/bin/bash'; cat; } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

update() {
  PATH="$STUBS:/usr/bin:/bin" run "$REPO_ROOT/bin/dotfiles-update" "$@"
}

@test "update: runs every step in order and exits 0" {
  update
  [ "$status" -eq 0 ]
  run cut -d' ' -f1-2 "$STUB_LOG"
  casks=""
  [[ $OSTYPE == darwin* ]] && casks=$'brew list\nbrew list\nbrew list\nbrew upgrade\n'
  expected="brew update
brew bundle
brew upgrade
${casks}brew cleanup
agy update
rustup default
rustup update
mise --cd
mise --cd
uv tool"
  [[ $OSTYPE == darwin* ]] && expected+=$'\nmas upgrade'
  [ "$output" = "$expected" ]
}

@test "update: brew bundle reads the repo's Brewfile" {
  [[ $OSTYPE == darwin* ]] || skip "macOS passes the Brewfile path"
  update
  grep -qF "brew bundle --file $REPO_ROOT/Brewfile" "$STUB_LOG" || false
}

@test "update: mise installs and upgrades from HOME, not the current folder" {
  command -v jq >/dev/null || skip "jq not installed"
  update
  grep -qx "mise --cd $HOME install node yq cwd=$BATS_TEST_TMPDIR" "$STUB_LOG" || false
  grep -qx "mise --cd $HOME upgrade node yq cwd=$BATS_TEST_TMPDIR" "$STUB_LOG" || false
}

@test "update: go: and cargo: tools are skipped with a pointer when go, cargo and cargo-binstall are missing" {
  command -v jq >/dev/null || skip "jq not installed"
  update
  [ "$status" -eq 0 ]
  [[ $output == *"skip 1 go: tools: go not on PATH (brew install go, it is in the Brewfile)"* ]] || false
  [[ $output == *"skip cargo: example-crate missing-crate: needs cargo to build (brew install rustup, then rustup default stable)"* ]] || false
}

@test "update: with cargo-binstall and no cargo, installed crates stay and missing ones are skipped" {
  command -v jq >/dev/null || skip "jq not installed"
  stub cargo-binstall </dev/null
  update
  grep -qx "mise --cd $HOME upgrade cargo:example-crate node yq cwd=$BATS_TEST_TMPDIR" "$STUB_LOG" || false
  [[ $output == *"skip cargo: missing-crate: needs cargo to build"* ]] || false
}

@test "update: go: and cargo: tools are kept when go and cargo are on PATH" {
  command -v jq >/dev/null || skip "jq not installed"
  stub go </dev/null
  stub cargo </dev/null
  update
  grep -qx "mise --cd $HOME install go:example.org/tool cargo:example-crate cargo:missing-crate node yq cwd=$BATS_TEST_TMPDIR" "$STUB_LOG" || false
  [[ $output != *"not on PATH"* ]] || false
}

@test "update: rustup with no default toolchain gets stable instead of an update" {
  stub rustup <<'EOF'
echo "rustup $*" >>"$STUB_LOG"
[[ $1 == default && $# -eq 1 ]] && exit 1
exit 0
EOF
  update
  [ "$status" -eq 0 ]
  grep -qx 'rustup default stable' "$STUB_LOG" || false
  ! grep -q 'rustup update' "$STUB_LOG" || false
}

@test "update: Homebrew's keg-only rustup is found and put on PATH before mise runs" {
  rm "$STUBS/rustup"
  keg="$BATS_TEST_TMPDIR/keg/bin"
  mkdir -p "$keg"
  { echo '#!/bin/bash'; echo 'echo "keg-rustup $*" >>"$STUB_LOG"'; } >"$keg/rustup"
  { echo '#!/bin/bash'; echo 'exit 0'; } >"$keg/cargo"
  chmod +x "$keg/rustup" "$keg/cargo"
  DOTFILES_RUSTUP_DIRS=$keg update
  grep -qx 'keg-rustup update' "$STUB_LOG" || false
  [[ $output != *"needs cargo to build"* ]] || false
}

@test "update: an App Store refusal tells you to sign in with your Apple ID" {
  [[ $OSTYPE == darwin* ]] || skip "mas runs on macOS only"
  STUB_FAIL=mas STUB_ERROR='Error Domain=ISErrorDomain Code=-128 "Unknown Error."' update
  [ "$status" -eq 1 ]
  [[ $output == *"Code=-128"* ]] || false
  [[ $output == *"Sign in with your Apple ID in App Store.app"* ]] || false
  [[ $output == *"  mas upgrade"* ]] || false
}

@test "update: another mas failure does not mention signing in" {
  [[ $OSTYPE == darwin* ]] || skip "mas runs on macOS only"
  STUB_FAIL=mas STUB_ERROR='Error: network unreachable' update
  [ "$status" -eq 1 ]
  [[ $output != *"Apple ID"* ]] || false
}

@test "update: the installed agent casks are always upgraded with --greedy" {
  [[ $OSTYPE == darwin* ]] || skip "casks are macOS only"
  update
  grep -q '^brew upgrade --cask --greedy antigravity codex claude-code@latest ' "$STUB_LOG" || false
}

@test "update: --greedy upgrades every cask in one brew upgrade" {
  update --greedy
  [ "$status" -eq 0 ]
  grep -q '^brew upgrade --greedy ' "$STUB_LOG" || false
  [ "$(grep -c -- '--greedy' "$STUB_LOG")" -eq 1 ]
}

@test "update: a failing step does not stop the rest and the exit status is 1" {
  STUB_FAIL="brew agy" update
  [ "$status" -eq 1 ]
  grep -q '^uv tool upgrade --all' "$STUB_LOG" || false
  [[ $output == *"== Failed"* ]] || false
  [[ $output == *"  agy update"* ]] || false
  [[ $output == *"  brew update"* ]] || false
}

@test "update: missing tools are skipped" {
  rm "$STUBS"/{brew,agy,mise,uv,rustup,mas,codex,claude}
  update
  [ "$status" -eq 0 ]
  [[ $output == *"skip Homebrew: brew not installed"* ]] || false
  [[ $output == *"skip agy: not installed"* ]] || false
  [[ $output == *"skip codex: not installed"* ]] || false
  [ ! -s "$STUB_LOG" ]
}

@test "update: --dry-run prints commands and runs none" {
  update --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"+ brew update"* ]] || false
  [[ $output == *"+ agy update"* ]] || false
  [ -z "$(grep -v '^brew list ' "$STUB_LOG")" ]
}

@test "update: prints the agent CLI versions and flags a codex outside Homebrew" {
  update
  [[ $output == *"codex-cli 9.9.9"* ]] || false
  [[ $output == *"9.9.9 (Claude Code)"* ]] || false
  [[ $output == *"note codex runs from $STUBS/codex, not Homebrew"* ]] || false
}

@test "update: failing mise ls records failure without claiming no global tools" {
  command -v jq >/dev/null || skip "jq not installed"
  stub mise <<'EOF'
if [[ " $* " == *" ls --global --json "* ]]; then
  echo "mise registry error" >&2
  exit 3
fi
echo "mise $*" >>"$STUB_LOG"
EOF
  update
  [ "$status" -eq 1 ]
  [[ $output != *"skip mise: no global tools"* ]] || false
  [[ $output == *"== Failed"* ]] || false
  [[ $output == *"mise --cd $HOME ls --global --json"* ]] || false
  grep -q '^uv tool upgrade --all' "$STUB_LOG" || false
}

@test "update: finds printf-%q escaped DOTFILES_DIR with spaces via symlinked entrypoint" {
  unset DOTFILES_DIR
  spaced="$BATS_TEST_TMPDIR/my dotfiles"
  mkdir -p "$spaced" "$BATS_TEST_TMPDIR/bin"
  : >"$spaced/Brewfile"
  mkdir -p "$HOME/.config/dotfiles"
  printf 'DOTFILES_DIR=%q\n' "$spaced" >"$HOME/.config/dotfiles/config"
  ln -sf "$REPO_ROOT/bin/dotfiles-update" "$BATS_TEST_TMPDIR/bin/dotfiles-update"
  PATH="$STUBS:/usr/bin:/bin" run "$BATS_TEST_TMPDIR/bin/dotfiles-update" --dry-run
  [ "$status" -eq 0 ]
  [[ $output != *"no Brewfile"* ]] || false
  if [[ $OSTYPE == darwin* ]]; then
    [[ $output == *"brew bundle --file $spaced/Brewfile"* ]] || false
  else
    [[ $output == *"+ scripts/linux-brewfile.sh | brew bundle --file=-"* ]] || false
  fi
}

@test "update: finds the repo from ~/.config/dotfiles/config" {
  unset DOTFILES_DIR
  mkdir -p "$HOME/.config/dotfiles"
  echo "DOTFILES_DIR=$BATS_TEST_TMPDIR/elsewhere" >"$HOME/.config/dotfiles/config"
  update --dry-run
  [[ $output == *"no Brewfile in $BATS_TEST_TMPDIR/elsewhere"* ]] || false
}

@test "update: unknown argument exits 2" {
  update --bogus
  [ "$status" -eq 2 ]
}
