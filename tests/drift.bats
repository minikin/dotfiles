#!/usr/bin/env bats
# just drift: read-only comparison of the live files install.sh links with the repo copy.

load helpers

setup() {
  fake_home
  command -v just >/dev/null || skip "just not installed"
  copy_repo
  OTHER="$BATS_TEST_TMPDIR/old-checkout"
  mkdir -p "$OTHER/zsh" "$HOME/.config/zsh" "$HOME/.config/jj"
  cp "$DOTFILES/zsh/jj.zsh" "$OTHER/zsh/jj.zsh"

  ln -s "$DOTFILES/zsh/zshrc" "$HOME/.zshrc"
  ln -s "$OTHER/zsh/jj.zsh" "$HOME/.config/zsh/jj.zsh"
  cp "$DOTFILES/zsh/sign.zsh" "$HOME/.config/zsh/sign.zsh"
  printf 'edited\n' > "$HOME/.config/zsh/infra.zsh"
  ln -s "$BATS_TEST_TMPDIR/nowhere/navi.zsh" "$HOME/.config/zsh/navi.zsh"
}

drift() {
  run just --justfile "$DOTFILES/justfile" --working-directory "$DOTFILES" drift
}

line_for() { grep -E " $1( |$)" <<<"$output"; }

@test "drift: a link into the checkout is linked" {
  drift
  [ "$status" -eq 0 ]
  [[ $(line_for '~/.zshrc') == "linked "* ]]
}

@test "drift: a link into another clone with identical content is elsewhere, with its target" {
  drift
  [ "$status" -eq 0 ]
  echo "output: $output"
  [ "$(line_for '~/.config/zsh/jj.zsh')" = "elsewhere    ~/.config/zsh/jj.zsh -> $OTHER/zsh/jj.zsh" ]
}

@test "drift: a dangling link is elsewhere, not missing" {
  drift
  [ "$status" -eq 0 ]
  [ "$(line_for '~/.config/zsh/navi.zsh')" = "elsewhere    ~/.config/zsh/navi.zsh -> $BATS_TEST_TMPDIR/nowhere/navi.zsh" ]
}

@test "drift: a regular file is same (copy), DIFFERS or missing" {
  drift
  [ "$status" -eq 0 ]
  [[ $(line_for '~/.config/zsh/sign.zsh') == "same (copy) "* ]]
  [[ $(line_for '~/.config/zsh/infra.zsh') == "DIFFERS "* ]]
  [[ $(line_for '~/.config/jj/config.toml') == "missing "* ]]
}

@test "drift: changes nothing in HOME" {
  before=$(cd "$HOME" && find . -exec ls -ld {} + | sort)
  drift
  [ "$status" -eq 0 ]
  [ "$(cd "$HOME" && find . -exec ls -ld {} + | sort)" = "$before" ]
}
