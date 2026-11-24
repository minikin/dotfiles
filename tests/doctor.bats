#!/usr/bin/env bats
# just doctor in a copy of the repo, with a stub agent-preflight and a stub brew.

load helpers

setup() {
  fake_home
  command -v just >/dev/null || skip "just not installed"
  copy_repo
  TOOLS="$BATS_TEST_TMPDIR/tools"
  mkdir -p "$TOOLS"
  ln -s "$(command -v just)" "$TOOLS/just"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$STUB_LOG"
  printf '#!/bin/sh\necho "preflight ran"\nexit "${STUB_PREFLIGHT_RC:-0}"\n' >"$DOTFILES/bin/agent-preflight"
  printf '#!/bin/sh\necho "brew $*" >>"$STUB_LOG"\nexit "${STUB_BREW_RC:-0}"\n' >"$TOOLS/brew"
  chmod +x "$DOTFILES/bin/agent-preflight" "$TOOLS/brew"
}

# doctor: just doctor with only the stub tools, just and the system dirs on PATH.
doctor() { PATH="$TOOLS:/usr/bin:/bin" run just -f "$DOTFILES/justfile" doctor; }

sections_all_printed() {
  [[ $output == *"== drift"* && $output == *"== agent-preflight"* && $output == *"== brew bundle check"* ]] || false
  [[ $output == *"== phone access"*"run remote-check in zsh"* ]] || false
}

@test "doctor: drift, preflight and brew bundle check all pass, exit 0" {
  doctor
  echo "$output"
  [ "$status" -eq 0 ]
  sections_all_printed
  [[ $output == *"preflight ran"* ]] || false
  grep -qx "brew bundle check --file Brewfile --no-upgrade" "$STUB_LOG"
}

@test "doctor: a failing preflight fails doctor and every section still runs" {
  STUB_PREFLIGHT_RC=1 doctor
  [ "$status" -eq 1 ]
  sections_all_printed
  grep -q '^brew bundle check' "$STUB_LOG"
}

@test "doctor: a failing brew bundle check fails doctor and the last section still prints" {
  STUB_BREW_RC=1 doctor
  [ "$status" -eq 1 ]
  sections_all_printed
}

@test "doctor: without brew it says so and passes" {
  rm "$TOOLS/brew"
  doctor
  [ "$status" -eq 0 ]
  [[ $output == *"skip brew bundle check: brew not installed"* ]] || false
  sections_all_printed
}

@test "doctor: drift lists the links and changes nothing in HOME" {
  before=$(cd "$HOME" && find . | sort)
  doctor
  [[ $output == *"missing      ~/.zshrc"* ]] || false
  [ "$(cd "$HOME" && find . | sort)" = "$before" ]
}
