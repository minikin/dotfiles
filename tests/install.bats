#!/usr/bin/env bats
# install.sh: symlinks, backups, Claude settings merge, identity bootstrap.
# Every test runs install.sh from a copy of the repo against a fake HOME.

load helpers

setup() {
  fake_home
  copy_repo
}

home_listing() { (cd "$HOME" && find . | LC_ALL=C sort); }
count_backups() { find "$HOME" "$DOTFILES" -name '*.bak-*' 2>/dev/null | wc -l | tr -d ' '; }
file_mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1"; }
SETTINGS() { echo "$HOME/.claude/settings.json"; }

@test "install: --dry-run changes nothing on disk" {
  before_home=$(home_listing)
  before_repo=$(cd "$DOTFILES" && find . -exec ls -ld {} + | LC_ALL=C sort)
  run_install --dry-run
  [ "$status" -eq 0 ]
  [ "$(home_listing)" = "$before_home" ]
  [ "$(cd "$DOTFILES" && find . -exec ls -ld {} + | LC_ALL=C sort)" = "$before_repo" ]
  [[ $output == *"+ ln -s"* ]] || false
}

@test "install: first run symlinks every link line" {
  run_install
  [ "$status" -eq 0 ]
  n=0
  while IFS=$'\t' read -r src dest; do
    n=$((n + 1))
    [ -L "$dest" ] || { echo "not a symlink: $dest"; return 1; }
    [[ $dest -ef $DOTFILES/$src ]] || { echo "wrong target: $dest"; return 1; }
  done < <(link_pairs)
  [ "$n" -ge 10 ]
}

@test "install: second run is a no-op (no new backups, settings unchanged)" {
  run_install
  [ "$status" -eq 0 ]
  before=$(count_backups)
  run_install
  [ "$status" -eq 0 ]
  [ "$(count_backups)" -eq "$before" ]
  [[ $output == *"settings.json (unchanged)"* ]] || false
  [[ $output != *"+ ln -s"* ]] || false
}

@test "install: an existing plain file is backed up before being replaced" {
  printf 'my old zshrc\n' > "$HOME/.zshrc"
  run_install
  [ "$status" -eq 0 ]
  [[ $HOME/.zshrc -ef $DOTFILES/zsh/zshrc ]] || false
  backups=("$HOME"/.zshrc.bak-*)
  [ "${#backups[@]}" -eq 1 ]
  [ -f "${backups[0]}" ]
  [ "$(cat "${backups[0]}")" = "my old zshrc" ]
}

@test "install: an empty settings.json is merged into valid JSON" {
  mkdir -p "$HOME/.claude"
  : > "$(SETTINGS)"
  run_install
  [ "$status" -eq 0 ]
  jq -e . "$(SETTINGS)" >/dev/null
  jq -e '.permissions.deny | index("Bash(jj *--tool*)")' "$(SETTINGS)" >/dev/null
  jq -e '.statusLine.command == "~/.claude/statusline.sh"' "$(SETTINGS)" >/dev/null
}

@test "install: invalid settings.json is left untouched and install fails" {
  mkdir -p "$HOME/.claude"
  printf '{"a":1,}' > "$(SETTINGS)"
  run_install
  [ "$status" -ne 0 ]
  [[ $output == *"merge failed"* ]] || false
  [ "$(cat "$(SETTINGS)")" = '{"a":1,}' ]
  [ ! -e "$(SETTINGS).tmp" ]
}

@test "install: existing keys are kept and allow/deny lists are unioned without duplicates" {
  mkdir -p "$HOME/.claude"
  cat > "$(SETTINGS)" <<'JSON'
{
  "model": "opus",
  "env": { "JJ_EDITOR": "vim", "KEEP_ME": "1" },
  "permissions": {
    "allow": ["Bash(ls)", "Bash(jj st)"],
    "deny":  ["Bash(rm -rf *)", "Bash(jj *--tool*)"]
  }
}
JSON
  run_install
  [ "$status" -eq 0 ]
  s=$(SETTINGS)
  jq -e '.model == "opus"' "$s"
  jq -e '.env.KEEP_ME == "1"' "$s"
  jq -e '.env.JJ_EDITOR == "false"' "$s"              # fragment keys win
  jq -e '.permissions.allow | index("Bash(ls)")' "$s"
  jq -e '.permissions.allow | index("Bash(jj log *)")' "$s"
  jq -e '.permissions.deny | index("Bash(rm -rf *)")' "$s"
  jq -e '.permissions.deny | index("Bash(jj *--config*)")' "$s"
  jq -e '(.permissions.allow | length) == (.permissions.allow | unique | length)' "$s"
  jq -e '(.permissions.deny | length) == (.permissions.deny | unique | length)' "$s"
  jq -e '[.permissions.allow[] | select(. == "Bash(jj st)")] | length == 1' "$s"
  # every fragment rule made it in
  frag="$DOTFILES/claude/settings.fragment.json"
  jq -e --slurpfile f "$frag" '($f[0].permissions.allow - .permissions.allow) == []' "$s"
  jq -e --slurpfile f "$frag" '($f[0].permissions.deny - .permissions.deny) == []' "$s"
}

@test "install: the user's own hooks survive next to the fragment's hooks" {
  mkdir -p "$HOME/.claude"
  cat > "$(SETTINGS)" <<'JSON'
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "say hello" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "my-linter" } ] }
    ]
  }
}
JSON
  run_install
  [ "$status" -eq 0 ]
  s=$(SETTINGS)
  jq -e '[.hooks.Notification[].hooks[].command] | index("say hello")' "$s"
  jq -e '[.hooks.Notification[].hooks[].command] | index("~/.claude/notify.sh")' "$s"
  jq -e '[.hooks.Stop[].hooks[].command] | index("~/.claude/notify.sh")' "$s"
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command == "~/.claude/guard-push.sh"' "$s"
  jq -e '[.hooks.SessionStart[].hooks[].command] | index("~/.claude/session-context.sh")' "$s"
  jq -e '.hooks.PostToolUse[0].hooks[0].command == "my-linter"' "$s"
}

@test "install: re-running does not duplicate hooks" {
  run_install
  [ "$status" -eq 0 ]
  first=$(cat "$(SETTINGS)")
  run_install
  [ "$status" -eq 0 ]
  [ "$(cat "$(SETTINGS)")" = "$first" ]
  s=$(SETTINGS)
  frag="$DOTFILES/claude/settings.fragment.json"
  jq -e --slurpfile f "$frag" '.hooks == $f[0].hooks' "$s"
  jq -e '(.hooks.Stop | length) == 1 and (.hooks.PreToolUse | length) == 1' "$s"
}

@test "install: parent dir already linked into the repo is left alone" {
  mkdir -p "$HOME/.config"
  ln -s "$DOTFILES/ghostty" "$HOME/.config/ghostty"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/ghostty" ]
  [ -f "$DOTFILES/ghostty/config" ]
  [ ! -L "$DOTFILES/ghostty/config" ]
  [ -z "$(find "$DOTFILES/ghostty" -name '*.bak-*')" ]
  [[ $HOME/.config/ghostty/config -ef $DOTFILES/ghostty/config ]] || false
}

@test "install: non-interactive identity from DOTFILES_* env vars" {
  ssh-keygen -q -t ed25519 -N '' -C work -f "$BATS_TEST_TMPDIR/work_key"
  ssh-keygen -q -t ed25519 -N '' -C personal -f "$BATS_TEST_TMPDIR/personal_key"
  export DOTFILES_NAME='Test "Q" User'
  export DOTFILES_EMAIL=work@example.com
  export DOTFILES_SIGNING_KEY="$BATS_TEST_TMPDIR/work_key.pub"
  export DOTFILES_PERSONAL_EMAIL=me@personal.example
  export DOTFILES_PERSONAL_DIR="~/src/mine"
  export DOTFILES_PERSONAL_KEY="$BATS_TEST_TMPDIR/personal_key.pub"
  run_install
  [ "$status" -eq 0 ]

  id="$HOME/.config/jj/conf.d/identity.toml"
  [ -f "$id" ]
  [ "$(file_mode "$id")" = 600 ]
  grep -qF 'name = "Test \"Q\" User"' "$id"
  # The file must be valid TOML that jj reads back to the original values
  [ "$(env -u JJ_USER -u JJ_EMAIL JJ_CONFIG="$id" jj config get user.name)" = 'Test "Q" User' ]
  [ "$(JJ_CONFIG="$id" jj config get signing.key)" = "$DOTFILES_SIGNING_KEY" ]
  [ "$(JJ_CONFIG="$id" jj config get signing.backend)" = ssh ]
  [ "$(JJ_CONFIG="$id" jj config get signing.backends.ssh.program)" = /usr/bin/ssh-keygen ]
  grep -qF 'email = "work@example.com"' "$id"
  grep -qF -- '--when.repositories = ["~/src/mine"]' "$id"
  [ -d "$HOME/src/mine" ]
  grep -qF 'email = "me@personal.example"' "$id"
  grep -qF "key = \"$DOTFILES_PERSONAL_KEY\"" "$id"

  [ "$(git config --global gpg.format)" = ssh ]
  [ "$(git config --global commit.gpgsign)" = true ]
  [ "$(git config --global user.signingkey)" = "$DOTFILES_SIGNING_KEY" ]
  [ "$(git config --global --get 'includeIf.gitdir:~/src/mine/.path')" = "$HOME/.config/git/personal.gitconfig" ]
  [ "$(git config -f "$HOME/.config/git/personal.gitconfig" user.email)" = me@personal.example ]

  signers="$HOME/.config/git/allowed_signers"
  grep -qF "work@example.com namespaces=\"git\" $(cat "$BATS_TEST_TMPDIR/work_key.pub")" "$signers"
  grep -qF "me@personal.example namespaces=\"git\" $(cat "$BATS_TEST_TMPDIR/personal_key.pub")" "$signers"
}

@test "install: no terminal and no DOTFILES_NAME copies the identity template" {
  run_install
  [ "$status" -eq 0 ]
  id="$HOME/.config/jj/conf.d/identity.toml"
  cmp "$id" "$DOTFILES/jj/identity.example.toml"
  [ "$(file_mode "$id")" = 600 ]
  [[ $output == *"no terminal"* ]] || false
}

@test "install: template placeholders are never copied into git identity" {
  run env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL bash "$DOTFILES/install.sh" </dev/null
  [ "$status" -eq 0 ]
  [[ $output == *"still has placeholders"* ]] || false
  run git config --global user.email
  [ "$status" -ne 0 ]
  run git config --global user.name
  [ "$status" -ne 0 ]
}

@test "install: an existing identity.toml is not touched" {
  id="$HOME/.config/jj/conf.d/identity.toml"
  mkdir -p "${id%/*}"
  printf '[user]\nname = "Keep Me"\n' > "$id"
  export DOTFILES_NAME=Other DOTFILES_EMAIL=other@example.com
  run_install
  [ "$status" -eq 0 ]
  [ "$(cat "$id")" = "$(printf '[user]\nname = "Keep Me"')" ]
  [ ! -e "$HOME/.config/git/allowed_signers" ]
}

@test "install: a bad signing key path fails non-interactively" {
  export DOTFILES_NAME=Test DOTFILES_EMAIL=test@example.com
  export DOTFILES_SIGNING_KEY="$BATS_TEST_TMPDIR/does-not-exist.pub"
  run_install
  [ "$status" -ne 0 ]
  [[ $output == *"neither a public key line nor an existing .pub file"* ]] || false
  [ ! -e "$HOME/.config/jj/conf.d/identity.toml" ]
}

@test "install: first run without settings.json does not claim a backup it never made" {
  run_install
  [ "$status" -eq 0 ]
  [ -z "$(find "$HOME/.claude" -name 'settings.json.bak-*')" ]
  [[ $output != *"(backup:"* ]] || false
}

@test "install: one identity only writes no second scope and no includeIf" {
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/k"
  export DOTFILES_NAME=Solo DOTFILES_EMAIL=solo@example.com DOTFILES_SIGNING_KEY="$BATS_TEST_TMPDIR/k.pub"
  run_install
  [ "$status" -eq 0 ]
  ! grep -q -- '--scope' "$HOME/.config/jj/conf.d/identity.toml" || false
  run git config --global --get-regexp '^includeif\.'
  [ -z "$output" ]
  [ ! -e "$HOME/.config/git/personal.gitconfig" ]
  ! grep -q DOTFILES_PERSONAL_DIR "$HOME/.config/dotfiles/config" || false
}

@test "install: a second email without its folder (or the reverse) is refused" {
  export DOTFILES_NAME=X DOTFILES_EMAIL=x@example.com DOTFILES_PERSONAL_EMAIL=y@example.org
  run_install
  [ "$status" -eq 2 ]
  [[ $output == *"together"* ]] || false
  [ ! -e "$HOME/.config/jj/conf.d/identity.toml" ]
  unset DOTFILES_PERSONAL_EMAIL
  export DOTFILES_PERSONAL_DIR="~/src/mine"
  run_install
  [ "$status" -eq 2 ]
}

@test "install: a folder outside HOME is stored as an absolute path" {
  export DOTFILES_NAME=X DOTFILES_EMAIL=x@example.com DOTFILES_PERSONAL_EMAIL=y@example.org
  export DOTFILES_PERSONAL_DIR="$BATS_TEST_TMPDIR/outside/"
  run_install
  [ "$status" -eq 0 ]
  outside=$(realpath_of "$BATS_TEST_TMPDIR/outside")
  grep -qF -- "--when.repositories = [\"$outside\"]" "$HOME/.config/jj/conf.d/identity.toml"
  git config --global --get "includeIf.gitdir:$outside/.path" >/dev/null
}

@test "install: writes ~/.config/dotfiles/config and keeps it on re-run" {
  export DOTFILES_NAME=X DOTFILES_EMAIL=x@example.com DOTFILES_PERSONAL_EMAIL=y@example.org DOTFILES_PERSONAL_DIR="~/src/mine"
  run_install
  [ "$status" -eq 0 ]
  conf="$HOME/.config/dotfiles/config"
  ( set -a; source "$conf"; [ "$DOTFILES_DIR" = "$DOTFILES" ] && [ "$DOTFILES_PERSONAL_DIR" = "$HOME/src/mine" ] )
  unset DOTFILES_NAME DOTFILES_EMAIL DOTFILES_PERSONAL_EMAIL DOTFILES_PERSONAL_DIR
  run_install
  [ "$status" -eq 0 ]
  [[ $output == *"$conf (unchanged)"* ]] || false
}

@test "install: the template's placeholder folder never becomes DOTFILES_PERSONAL_DIR" {
  run_install
  [ "$status" -eq 0 ]
  ! grep -q DOTFILES_PERSONAL_DIR "$HOME/.config/dotfiles/config" || false
}

@test "install: a private key file given as the signing key is rejected and never written" {
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/id_test"
  export DOTFILES_NAME=Test DOTFILES_EMAIL=test@example.com
  export DOTFILES_SIGNING_KEY="$BATS_TEST_TMPDIR/id_test"
  run_install
  [ "$status" -eq 1 ]
  [[ $output == *"not a public key file"* ]] || false
  [ ! -e "$HOME/.config/jj/conf.d/identity.toml" ]
  [ ! -e "$HOME/.config/git/allowed_signers" ]
  ! grep -rqs 'PRIVATE KEY' "$HOME" || false
}

@test "install: allowed_signers is created private (mode 600)" {
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/k"
  export DOTFILES_NAME=Test DOTFILES_EMAIL=test@example.com DOTFILES_SIGNING_KEY="$BATS_TEST_TMPDIR/k.pub"
  run_install
  [ "$status" -eq 0 ]
  [ "$(file_mode "$HOME/.config/git/allowed_signers")" = 600 ]
}

@test "install: a personal key without a main key never becomes the main signing key" {
  ssh-keygen -q -t ed25519 -N '' -C personal -f "$BATS_TEST_TMPDIR/personal_key"
  export DOTFILES_NAME=Test DOTFILES_EMAIL=work@example.com DOTFILES_SIGNING_KEY=''
  export DOTFILES_PERSONAL_EMAIL=me@personal.example DOTFILES_PERSONAL_DIR="~/src/mine"
  export DOTFILES_PERSONAL_KEY="$BATS_TEST_TMPDIR/personal_key.pub"
  run_install
  [ "$status" -eq 0 ]
  id="$HOME/.config/jj/conf.d/identity.toml"
  ! grep -q '^\[signing\]' "$id" || false
  grep -qF '[--scope.signing]' "$id"
  grep -qF "key = \"$DOTFILES_PERSONAL_KEY\"" "$id"
  run git config --global user.signingkey
  [ "$status" -ne 0 ]
  [ "$(git config -f "$HOME/.config/git/personal.gitconfig" user.signingkey)" = "$DOTFILES_PERSONAL_KEY" ]
  signers="$HOME/.config/git/allowed_signers"
  ! grep -q '^work@example.com ' "$signers" || false
  grep -qF "me@personal.example namespaces=\"git\" $(cat "$BATS_TEST_TMPDIR/personal_key.pub")" "$signers"
}

# install.sh runs jj with the caller's cwd, so a run from inside the personal folder would
# see that folder's --when.repositories scope.
@test "install: git identity comes from the main identity even when run inside the personal folder" {
  pdir="$BATS_TEST_TMPDIR/personal"
  make_jj_repo "$pdir/proj"
  export DOTFILES_NAME=Main DOTFILES_EMAIL=main@example.com
  export DOTFILES_PERSONAL_EMAIL=me@example.org DOTFILES_PERSONAL_DIR="$pdir"
  cd "$pdir/proj"
  run env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL bash "$DOTFILES/install.sh" </dev/null
  [ "$status" -eq 0 ]
  [ "$(env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj config get user.email)" = me@example.org ]
  [ "$(git config --global --no-includes user.email)" = main@example.com ]
  [ "$(git config --global --no-includes user.name)" = Main ]
}

@test "install: git identity from an existing identity.toml is read outside any repo" {
  pdir="$BATS_TEST_TMPDIR/personal"
  make_jj_repo "$pdir/proj"
  id="$HOME/.config/jj/conf.d/identity.toml"
  mkdir -p "${id%/*}"
  cat > "$id" <<TOML
[user]
name = "Main"
email = "main@example.com"

[[--scope]]
--when.repositories = ["$(realpath_of "$pdir")"]
[--scope.user]
email = "me@example.org"
TOML
  cd "$pdir/proj"
  run env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL bash "$DOTFILES/install.sh" </dev/null
  [ "$status" -eq 0 ]
  [ "$(env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj config get user.email)" = me@example.org ]
  [ "$(git config --global --no-includes user.email)" = main@example.com ]
}

@test "install: the no-terminal template copy leaves signing off so jj keeps working" {
  run_install
  [ "$status" -eq 0 ]
  [[ $output == *"signing is off"* ]] || false
  run env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj config get signing.behavior
  [ "$output" != own ]
  run env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj config get signing.key
  [ "$status" -ne 0 ]
  repo="$BATS_TEST_TMPDIR/r"
  mkdir -p "$repo"
  cd "$repo"
  env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj git init --colocate --quiet
  printf 'x\n' > f
  env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj commit -m test
  env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj st
}

@test "install: a symlinked personal folder is stored as its physical path" {
  mkdir -p "$BATS_TEST_TMPDIR/real/personal"
  ln -s "$BATS_TEST_TMPDIR/real/personal" "$BATS_TEST_TMPDIR/alias"
  real=$(realpath_of "$BATS_TEST_TMPDIR/real/personal")
  export DOTFILES_NAME=X DOTFILES_EMAIL=x@example.com DOTFILES_PERSONAL_EMAIL=y@example.org
  export DOTFILES_PERSONAL_DIR="$BATS_TEST_TMPDIR/alias"
  run_install
  [ "$status" -eq 0 ]
  grep -qF -- "--when.repositories = [\"$real\"]" "$HOME/.config/jj/conf.d/identity.toml"
  git config --global --get "includeIf.gitdir:$real/.path" >/dev/null
  ( source "$HOME/.config/dotfiles/config"; [ "$DOTFILES_PERSONAL_DIR" = "$real" ] )
  make_jj_repo "$real/proj"
  [ "$(cd "$real/proj" && env -u JJ_CONFIG -u JJ_USER -u JJ_EMAIL jj config get user.email)" = y@example.org ]
}

@test "install: an empty name or email from env vars is refused" {
  export DOTFILES_NAME=X DOTFILES_EMAIL=''
  run_install
  [ "$status" -eq 2 ]
  [[ $output == *"DOTFILES_EMAIL"* ]] || false
  [ ! -e "$HOME/.config/jj/conf.d/identity.toml" ]
  [ ! -e "$HOME/.config/git/allowed_signers" ]
  export DOTFILES_EMAIL=x@example.com DOTFILES_PERSONAL_DIR="~/src/mine" DOTFILES_PERSONAL_EMAIL=''
  run_install
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.config/jj/conf.d/identity.toml" ]
}

@test "install: after the repo moves, every link is repointed with one backup of each old link" {
  run_install
  [ "$status" -eq 0 ]
  mv "$DOTFILES" "$DOTFILES.moved"
  DOTFILES="$DOTFILES.moved"
  run_install
  [ "$status" -eq 0 ]
  while IFS=$'\t' read -r src dest; do
    [[ $dest -ef $DOTFILES/$src ]] || { echo "not repointed: $dest"; return 1; }
    backups=("$dest".bak-*)
    [ "${#backups[@]}" -eq 1 ] || { echo "backups for $dest: ${#backups[@]}"; return 1; }
    [ -L "${backups[0]}" ]
  done < <(link_pairs)
  ( source "$HOME/.config/dotfiles/config"; [ "$DOTFILES_DIR" = "$DOTFILES" ] )
}

# fake_screenshot_tools: a logging `defaults` on PATH and a logging activateSettings, so the
# --shottr step never writes the real com.apple.symbolichotkeys or reloads the real session.
fake_screenshot_tools() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "defaults $*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/defaults"
  printf '#!/bin/sh\necho "activate $*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/activateSettings"
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export DOTFILES_ACTIVATE_SETTINGS="$BATS_TEST_TMPDIR/bin/activateSettings"
}

@test "install: --shottr turns off every macOS screenshot shortcut and applies it" {
  fake_screenshot_tools
  run_install --shottr
  [ "$status" -eq 0 ]
  for id in 28 29 30 31 184; do
    grep -qF "defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add $id <dict><key>enabled</key><false/></dict>" "$BATS_TEST_TMPDIR/calls" ||
      { echo "shortcut $id not turned off"; return 1; }
  done
  [ "$(grep -c '^defaults ' "$BATS_TEST_TMPDIR/calls")" -eq 5 ]
  grep -qx 'activate -u' "$BATS_TEST_TMPDIR/calls"
}

@test "install: without --shottr the screenshot shortcuts are left alone" {
  fake_screenshot_tools
  run_install
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
  [[ $output != *"screenshot shortcuts"* ]] || false
}

@test "install: --dry-run --shottr only prints the screenshot commands" {
  fake_screenshot_tools
  run_install --dry-run --shottr
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
  [[ $output == *"+ defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 184"* ]] || false
}

@test "install: an unknown argument exits 2 before changing anything" {
  before_home=$(home_listing)
  run_install --dry-run --bogus
  [ "$status" -eq 2 ]
  [[ $output == *"unknown argument: --bogus"* ]] || false
  [ "$(home_listing)" = "$before_home" ]
}

# fake_brew: a logging `brew` on PATH, so --brew never installs anything for real.
fake_brew() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/brew"
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "install: --brew runs brew bundle on the repo's Brewfile before linking" {
  fake_brew
  run_install --brew
  [ "$status" -eq 0 ]
  grep -qx "brew bundle --file $DOTFILES/Brewfile" "$BATS_TEST_TMPDIR/calls"
  [[ ${output%%== symlinks*} == *"== brew bundle"* ]] || false
}

@test "install: --all runs brew bundle and the screenshot step" {
  fake_brew
  fake_screenshot_tools
  run_install --all
  [ "$status" -eq 0 ]
  grep -q '^brew bundle' "$BATS_TEST_TMPDIR/calls"
  grep -qx 'activate -u' "$BATS_TEST_TMPDIR/calls"
}

@test "install: --brew without Homebrew fails before changing anything" {
  mkdir -p "$BATS_TEST_TMPDIR/nobrew"
  for t in bash dirname date; do ln -s "$(command -v "$t")" "$BATS_TEST_TMPDIR/nobrew/$t"; done
  before_home=$(home_listing)
  PATH="$BATS_TEST_TMPDIR/nobrew" run_install --brew
  [ "$status" -eq 1 ]
  [[ $output == *"Homebrew is required"* ]] || false
  [ "$(home_listing)" = "$before_home" ]
}
