#!/usr/bin/env bats
# install.sh: symlinks, backups, Claude settings merge, identity bootstrap.
# Every test runs install.sh from a copy of the repo against a fake HOME.

load helpers

setup() {
  fake_home
  copy_repo
  # --brew runs mise install, and the tests that pass it put this folder first on PATH.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "mise $* cwd=$PWD" >> "%s"\n' "$BATS_TEST_TMPDIR/mise-calls" > "$BATS_TEST_TMPDIR/bin/mise"
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"
}

home_listing() { (cd "$HOME" && find . | LC_ALL=C sort); }
count_backups() { find "$HOME" "$DOTFILES" -name '*.bak-*' 2>/dev/null | wc -l | tr -d ' '; }
# BSD form first, GNU form second, each captured on its own: GNU stat prints a report for -f
# before it fails, and that output must not reach the comparison.
file_mode() { local m; m=$(stat -f %Lp "$1" 2>/dev/null) || m=$(stat -c %a "$1"); echo "$m"; }
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

@test "install: the ssh PATH snippet is appended to .zshenv once, after what is there" {
  printf 'export EDITOR=vi\n' > "$HOME/.zshenv"
  run_install
  [ "$status" -eq 0 ]
  run_install
  [ "$status" -eq 0 ]
  [[ $output == *"ok   ~/.zshenv"* ]] || false
  [ "$(head -1 "$HOME/.zshenv")" = 'export EDITOR=vi' ]
  [ "$(grep -c 'dotfiles: PATH for non-interactive ssh logins' "$HOME/.zshenv")" -eq 1 ]
}

@test "install: a non-interactive zsh finds ~/.local/bin and Homebrew tools through .zshenv" {
  run_install
  [ "$status" -eq 0 ]
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\n' > "$HOME/.local/bin/osewa"
  chmod +x "$HOME/.local/bin/osewa"
  # env -i is what sshd hands a command: no PATH from the parent, only zsh's default.
  run env -i HOME="$HOME" zsh -c 'command -v osewa; print -rl -- $path'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$HOME/.local/bin/osewa" ]
  [[ $output == *$'\n/opt/homebrew/bin'* ]] || false
}

@test "install: --dry-run leaves .zshenv alone" {
  run_install --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"+ append zsh/zshenv.snippet >> ~/.zshenv"* ]] || false
  [ ! -e "$HOME/.zshenv" ]
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

@test "install: a fresh install configures the sandbox but leaves it off" {
  run_install
  [ "$status" -eq 0 ]
  jq -e '.sandbox.enabled == null' "$(SETTINGS)"
  jq -e '.sandbox.autoAllowBashIfSandboxed == true' "$(SETTINGS)"
}

@test "install: the sandbox allows JSR, docs.rs and rustup downloads, and pkg.go.dev through *.go.dev" {
  run_install
  [ "$status" -eq 0 ]
  local d
  for d in jsr.io docs.rs static.rust-lang.org '*.go.dev'; do
    jq -e --arg d "$d" '.sandbox.network.allowedDomains | index($d)' "$(SETTINGS)" >/dev/null || { echo "missing $d"; return 1; }
  done
  jq -e '.sandbox.network.allowedDomains | index("pkg.go.dev") | not' "$(SETTINGS)"
}

@test "install: sandbox domains are unioned, other sandbox keys kept" {
  mkdir -p "$HOME/.claude"
  cat > "$(SETTINGS)" <<'JSON'
{
  "sandbox": {
    "enabled": false,
    "allowUnsandboxedCommands": false,
    "excludedCommands": ["flutter", "go"],
    "network": { "allowedDomains": ["*.example.com", "github.com"], "allowAllUnixSockets": true }
  }
}
JSON
  run_install
  [ "$status" -eq 0 ]
  s=$(SETTINGS)
  frag="$DOTFILES/claude/settings.fragment.json"
  jq -e '.sandbox.enabled == false' "$s"             # the fragment leaves the switch to you
  jq -e '.sandbox.allowUnsandboxedCommands == false' "$s"
  jq -e '.sandbox.network.allowAllUnixSockets == true' "$s"
  jq -e '.sandbox.network.allowedDomains | index("*.example.com")' "$s"
  jq -e '.sandbox.excludedCommands == ["flutter", "go"]' "$s"
  jq -e --slurpfile f "$frag" '($f[0].sandbox.network.allowedDomains - .sandbox.network.allowedDomains) == []' "$s"
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
  # Drains stdin: on the Linux path install.sh pipes the Brewfile in, and an early exit would
  # SIGPIPE the writer under pipefail.
  printf '#!/bin/sh\necho "brew $*" >> "%s"\ncat >/dev/null\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/brew"
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

@test "install: --brew sets the stable toolchain when Homebrew's rustup has none" {
  keg="$BATS_TEST_TMPDIR/keg"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$keg/bin"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/brew"
  printf '#!/bin/sh\necho "rustup $*" >> "%s"\n[ "$*" = default ] && exit 1\nexit 0\n' "$BATS_TEST_TMPDIR/calls" > "$keg/bin/rustup"
  chmod +x "$BATS_TEST_TMPDIR/bin/brew" "$keg/bin/rustup"
  DOTFILES_RUSTUP_DIRS="$keg/bin" PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --brew
  [ "$status" -eq 0 ]
  grep -qx 'rustup default stable' "$BATS_TEST_TMPDIR/calls"

  # A toolchain that is already set is left alone.
  printf '#!/bin/sh\necho "rustup $*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$keg/bin/rustup"
  : > "$BATS_TEST_TMPDIR/calls"
  DOTFILES_RUSTUP_DIRS="$keg/bin" PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --brew
  [ "$status" -eq 0 ]
  ! grep -q 'rustup default stable' "$BATS_TEST_TMPDIR/calls" || false
}

@test "install: a failing rustup default stable warns and still installs links" {
  fake_brew
  keg="$BATS_TEST_TMPDIR/keg"
  mkdir -p "$keg/bin"
  printf '#!/bin/sh\necho "rustup $*" >> "%s"\nexit 1\n' "$BATS_TEST_TMPDIR/calls" > "$keg/bin/rustup"
  chmod +x "$keg/bin/rustup"
  DOTFILES_RUSTUP_DIRS="$keg/bin" run_install --brew
  [ "$status" -eq 0 ]
  [[ $output == *"rustup default stable failed: continuing with dotfile links"* ]] || false
  [ -L "$HOME/.zshrc" ]
}

@test "install: --brew installs the global mise tools from HOME after linking" {
  fake_brew
  run_install --brew
  [ "$status" -eq 0 ]
  grep -qx "mise --cd $HOME install cwd=$PWD" "$BATS_TEST_TMPDIR/mise-calls"
  [[ ${output#*== symlinks} == *"== global mise tools"* ]] || false
}

@test "install: a failing mise install leaves the links in place and still exits 0" {
  fake_brew
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/mise"
  run_install --brew
  [ "$status" -eq 0 ]
  [[ $output == *"mise install failed: the links are in place"* ]] || false
  [ -L "$HOME/.config/mise/config.toml" ]
}

@test "install: without --brew, mise install does not run" {
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/mise-calls" ]
}

@test "install: an older .zprofile gets the rustup PATH once, a new one already has it" {
  printf '# old snippet\neval "$(/opt/homebrew/bin/mise activate zsh --shims)"\n' > "$HOME/.zprofile"
  run_install
  [ "$status" -eq 0 ]
  [ "$(grep -c 'opt/rustup/bin' "$HOME/.zprofile")" -eq 1 ]
  run_install
  [ "$(grep -c 'opt/rustup/bin' "$HOME/.zprofile")" -eq 1 ]

  rm "$HOME/.zprofile"
  run_install
  [ "$(grep -c 'opt/rustup/bin' "$HOME/.zprofile")" -eq 1 ]
}

@test "install: --all runs brew bundle and the screenshot step" {
  fake_brew
  fake_screenshot_tools
  run_install --all
  [ "$status" -eq 0 ]
  grep -q '^brew bundle' "$BATS_TEST_TMPDIR/calls"
  grep -qx 'activate -u' "$BATS_TEST_TMPDIR/calls"
}

@test "install: a failing brew bundle keeps its exit status, hints at --adopt and links nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\nexit 42\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/brew"
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  before_home=$(home_listing)
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --brew
  [ "$status" -eq 42 ]
  [[ $output == *"brew bundle failed (exit 42), dotfile installation has not started."* ]] || false
  [[ $output == *"If Homebrew reported an app that already exists in /Applications"* ]] || false
  [[ $output == *"brew install --cask --adopt <cask>"* ]] || false
  [[ $output != *"== symlinks"* ]] || false
  [ "$(home_listing)" = "$before_home" ]

  rm "$BATS_TEST_TMPDIR/calls"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --dry-run --brew
  [ "$status" -eq 0 ]
  [[ $output == *"+ brew bundle --file $DOTFILES/Brewfile"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
  [ "$(home_listing)" = "$before_home" ]
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

AGY_HOOKS() { echo "$HOME/.gemini/config/hooks.json"; }

# A made-up hooks.json in agy's layout: named hooks, flat and grouped events.
write_agy_hooks() {
  mkdir -p "$HOME/.gemini/config"
  cat >"$(AGY_HOOKS)" <<'JSON'
{
  "other-a": {"PreInvocation": [{"type": "command", "command": "./hooks/a.sh", "timeout": 5}]},
  "other-b": {"enabled": true, "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "./hooks/b.sh"}]}]}
}
JSON
}

@test "install: agy hooks merge keeps every other named hook and adds the guard" {
  write_agy_hooks
  run_install
  [ "$status" -eq 0 ]
  run jq -r 'keys | join(",")' "$(AGY_HOOKS)"
  [ "$output" = "dotfiles-agent-guard,other-a,other-b" ]
  run jq -r '."other-b".PreToolUse[0].hooks[0].command, ."dotfiles-agent-guard".PreToolUse[0].hooks[0].command' "$(AGY_HOOKS)"
  [ "${lines[0]}" = "./hooks/b.sh" ]
  [ "${lines[1]}" = "~/.gemini/config/hooks/dotfiles-guard-agents.zsh" ]
  [ "$(find "$HOME/.gemini/config" -name 'hooks.json.bak-*' | wc -l | tr -d ' ')" = "1" ]
}

@test "install: agy hooks merge is idempotent" {
  write_agy_hooks
  run_install
  before=$(cat "$(AGY_HOOKS)")
  run_install
  [ "$status" -eq 0 ]
  [[ $output == *"hooks.json (unchanged)"* ]] || false
  [ "$(cat "$(AGY_HOOKS)")" = "$before" ]
  [ "$(find "$HOME/.gemini/config" -name 'hooks.json.bak-*' | wc -l | tr -d ' ')" = "1" ]
}

@test "install: without an agy hooks.json one is created with only the guard" {
  run_install
  [ "$status" -eq 0 ]
  run jq -r 'keys | join(",")' "$(AGY_HOOKS)"
  [ "$output" = "dotfiles-agent-guard" ]
}

@test "install: invalid agy hooks.json is left untouched and install fails" {
  mkdir -p "$HOME/.gemini/config"
  printf '{ not json' >"$(AGY_HOOKS)"
  run_install
  [ "$status" -ne 0 ]
  [ "$(cat "$(AGY_HOOKS)")" = "{ not json" ]
  [[ $output == *"agy hooks merge failed"* ]] || false
}

@test "install: existing Codex and agy rule files are backed up and replaced by links" {
  mkdir -p "$HOME/.codex" "$HOME/.gemini"
  echo old-codex >"$HOME/.codex/AGENTS.md"
  echo old-agy >"$HOME/.gemini/GEMINI.md"
  run_install
  [ "$status" -eq 0 ]
  [ "$HOME/.codex/AGENTS.md" -ef "$DOTFILES/agents/AGENTS.md" ]
  [ "$HOME/.config/dotfiles/AGENTS.md" -ef "$DOTFILES/agents/AGENTS.md" ]
  [ "$HOME/.gemini/GEMINI.md" -ef "$DOTFILES/agy/GEMINI.md" ]
  [ "$(cat "$HOME"/.codex/AGENTS.md.bak-*)" = "old-codex" ]
  [ "$(cat "$HOME"/.gemini/GEMINI.md.bak-*)" = "old-agy" ]
}

@test "install: agy's include path is where install.sh links the shared rules" {
  local inc
  inc=$(sed -n 's/^@\[[^]]*\](\(~\/[^)]*\))$/\1/p' "$DOTFILES/agy/GEMINI.md")
  [ -n "$inc" ]
  link_pairs | grep -qxF "agents/AGENTS.md	${inc/#\~/$HOME}"
}

@test "install: agy gets the rex-orchestrator skill from the source Claude's skill links to" {
  mkdir -p "$BATS_TEST_TMPDIR/skills-repo/rex-orchestrator" "$HOME/.claude/skills"
  ln -s "$BATS_TEST_TMPDIR/skills-repo/rex-orchestrator" "$HOME/.claude/skills/rex-orchestrator"
  run_install
  [ "$status" -eq 0 ]
  real=$(cd "$BATS_TEST_TMPDIR/skills-repo/rex-orchestrator" && pwd -P)
  [ "$(readlink "$HOME/.gemini/config/skills/rex-orchestrator")" = "$real" ]
  run_install
  [[ $output == *"ok   $HOME/.gemini/config/skills/rex-orchestrator"* ]] || false
}

@test "install: without Claude's rex-orchestrator skill agy's is skipped" {
  run_install
  [ "$status" -eq 0 ]
  [[ $output == *"skip $HOME/.claude/skills/rex-orchestrator not found"* ]] || false
  [ ! -e "$HOME/.gemini/config/skills/rex-orchestrator" ]
}

@test "install: old agy rule files get a note and are never deleted" {
  mkdir -p "$HOME/Desktop" "$HOME/.gemini"
  echo old >"$HOME/Desktop/antigravity-instructions.md"
  echo old >"$HOME/.gemini/SUBSCRIPTION-AGENTS.md"
  run_install
  [ "$status" -eq 0 ]
  [[ $output == *"note $HOME/Desktop/antigravity-instructions.md is no longer loaded by agy"* ]] || false
  [[ $output == *"note $HOME/.gemini/SUBSCRIPTION-AGENTS.md is no longer loaded by agy"* ]] || false
  [ "$(cat "$HOME/Desktop/antigravity-instructions.md")" = "old" ]
  [ "$(cat "$HOME/.gemini/SUBSCRIPTION-AGENTS.md")" = "old" ]
}

@test "install: --dry-run leaves agy's files alone" {
  write_agy_hooks
  before=$(cat "$(AGY_HOOKS)")
  run_install --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"+ merge agy/hooks.fragment.json into $HOME/.gemini/config/hooks.json"* ]] || false
  [ "$(cat "$(AGY_HOOKS)")" = "$before" ]
  [ ! -e "$HOME/.gemini/GEMINI.md" ]
}

@test "install: an existing dotfiles-agent-guard entry is replaced whole, so enabled: false cannot survive" {
  write_agy_hooks
  jq '. + {"dotfiles-agent-guard": {"enabled": false, "Stop": [{"command": "./old.sh"}]}}' "$(AGY_HOOKS)" >"$BATS_TEST_TMPDIR/h.json"
  mv "$BATS_TEST_TMPDIR/h.json" "$(AGY_HOOKS)"
  run_install
  [ "$status" -eq 0 ]
  run jq -e --slurpfile f "$DOTFILES/agy/hooks.fragment.json" '."dotfiles-agent-guard" == $f[0]."dotfiles-agent-guard"' "$(AGY_HOOKS)"
  [ "$status" -eq 0 ]
  run jq -r 'keys | join(",")' "$(AGY_HOOKS)"
  [ "$output" = "dotfiles-agent-guard,other-a,other-b" ]
}

@test "install: the JSON merges never touch a file at the old fixed .tmp path and leave no temp file" {
  write_agy_hooks
  mkdir -p "$HOME/.claude"
  echo '{"model":"x"}' >"$(SETTINGS)"
  echo keep-hooks >"$(AGY_HOOKS).tmp"
  echo keep-settings >"$(SETTINGS).tmp"
  run_install
  [ "$status" -eq 0 ]
  [ "$(cat "$(AGY_HOOKS).tmp")" = "keep-hooks" ]
  [ "$(cat "$(SETTINGS).tmp")" = "keep-settings" ]
  [ -z "$(find "$HOME/.gemini/config" "$HOME/.claude" -name '*.merge.*')" ]
}

@test "install: the JSON merges keep the original file's mode" {
  write_agy_hooks
  mkdir -p "$HOME/.claude"
  echo '{"model":"x"}' >"$(SETTINGS)"
  chmod 600 "$(AGY_HOOKS)" "$(SETTINGS)"
  run_install
  [ "$status" -eq 0 ]
  [ "$(file_mode "$(AGY_HOOKS)")" = "600" ]
  [ "$(file_mode "$(SETTINGS)")" = "600" ]
}

@test "install: a symlinked hooks.json gets the mode of the file it points to" {
  write_agy_hooks
  mv "$(AGY_HOOKS)" "$BATS_TEST_TMPDIR/real-hooks.json"
  chmod 600 "$BATS_TEST_TMPDIR/real-hooks.json"
  ln -s "$BATS_TEST_TMPDIR/real-hooks.json" "$(AGY_HOOKS)"
  run_install
  [ "$status" -eq 0 ]
  [ "$(file_mode "$(AGY_HOOKS)")" = "600" ]
}

# make_gnu_stat: a stat in $BATS_TEST_TMPDIR/gnu that behaves like GNU's. It reads -f as "file
# system", prints a report, then fails on the format string it took for a path.
make_gnu_stat() {
  mkdir -p "$BATS_TEST_TMPDIR/gnu"
  cat >"$BATS_TEST_TMPDIR/gnu/stat" <<'STUB'
#!/bin/bash
if [[ " $* " == *" -f "* ]]; then echo "  File: \"$BATS_TEST_TMPDIR\" ID: 0 Namelen: 255 Type: apfs"; echo "stat: cannot read file system information for '%Lp'" >&2; exit 1; fi
if [[ " $* " == *" -c %a "* ]]; then exec /usr/bin/stat -L -f %Lp "${@: -1}"; fi
exec /usr/bin/stat "$@"
STUB
  chmod +x "$BATS_TEST_TMPDIR/gnu/stat"
}

@test "install: a GNU stat first on PATH does not break the mode lookup" {
  make_gnu_stat
  write_agy_hooks
  chmod 640 "$(AGY_HOOKS)"
  PATH="$BATS_TEST_TMPDIR/gnu:$PATH" run_install
  [ "$status" -eq 0 ]
  [ "$(file_mode "$(AGY_HOOKS)")" = "640" ]
}

@test "install tests: file_mode prints only the mode with a GNU stat first on PATH" {
  make_gnu_stat
  echo x >"$BATS_TEST_TMPDIR/f"
  chmod 640 "$BATS_TEST_TMPDIR/f"
  PATH="$BATS_TEST_TMPDIR/gnu:$PATH" run file_mode "$BATS_TEST_TMPDIR/f"
  [ "$output" = "640" ]
}

@test "install: on Linux --brew drops casks and macos-only formulae from the Brewfile" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\ncat > "%s"\n' "$BATS_TEST_TMPDIR/calls" "$BATS_TEST_TMPDIR/used" > "$BATS_TEST_TMPDIR/bin/brew"
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  DOTFILES_OS=linux-gnu PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --brew
  [ "$status" -eq 0 ]
  [[ $output == *"linux-gnu: casks and macos-only formulae skipped"* ]] || false
  grep -qx 'brew bundle --file=-' "$BATS_TEST_TMPDIR/calls"
  ! grep -qE '^[[:space:]]*cask[[:space:]]|# macos-only' "$BATS_TEST_TMPDIR/used" || false
  grep -qx 'brew "jj"' "$BATS_TEST_TMPDIR/used"
  grep -q '^tap "rjyo/moshi"' "$BATS_TEST_TMPDIR/used"
}

@test "install: on Linux --all skips the screenshot step" {
  fake_brew
  fake_screenshot_tools
  DOTFILES_OS=linux-gnu run_install --all
  [ "$status" -eq 0 ]
  [[ $output == *"skip --shottr: macOS only"* ]] || false
  ! grep -q 'activate -u' "$BATS_TEST_TMPDIR/calls" || false
}

@test "install: on Linux a failing brew bundle keeps its exit status and --dry-run runs nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\ncat >/dev/null\nexit 42\n' "$BATS_TEST_TMPDIR/calls" > "$BATS_TEST_TMPDIR/bin/brew"
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  DOTFILES_OS=linux-gnu PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --brew
  [ "$status" -eq 42 ]
  [[ $output == *"brew bundle failed (exit 42)"* ]] || false

  rm "$BATS_TEST_TMPDIR/calls"
  DOTFILES_OS=linux-gnu PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_install --dry-run --brew
  [ "$status" -eq 0 ]
  [[ $output == *"+ scripts/linux-brewfile.sh | brew bundle --file=-"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
}

@test "install: T3 Code antigravity provider links skills/plugins, preserves custom files, and skips hooks and non-profiles" {
  local prof1="$HOME/.t3/userdata/providers/antigravity/prof1"
  local prof2="$HOME/.t3/userdata/providers/antigravity/prof2"
  local nonprof="$HOME/.t3/userdata/providers/antigravity/not-a-profile"
  mkdir -p "$HOME/.agents/skills" "$HOME/.gemini/config/plugins" "$prof1/config" "$prof2/config" "$nonprof"
  printf '{"entries":[{"path":"/custom"}]}\n' > "$prof2/config/skills.json"

  before_home=$(home_listing)
  run_install --dry-run
  [ "$status" -eq 0 ]
  [ "$(home_listing)" = "$before_home" ]
  [ ! -e "$HOME/.gemini/config/skills.json" ]
  [ ! -e "$HOME/.gemini/config/plugins.json" ]

  run_install
  [ "$status" -eq 0 ]
  jq -e --arg p "$HOME/.agents/skills" '.entries == [{"path": $p}]' "$HOME/.gemini/config/skills.json"
  jq -e --arg p "$HOME/.gemini/config/plugins" '.entries == [{"path": $p}]' "$HOME/.gemini/config/plugins.json"
  [ "$(readlink "$prof1/config/skills.json")" = "$HOME/.gemini/config/skills.json" ]
  [ "$(readlink "$prof1/config/plugins.json")" = "$HOME/.gemini/config/plugins.json" ]
  [ ! -e "$prof1/config/hooks" ]
  [ ! -e "$prof1/config/hooks.json" ]
  [ ! -e "$nonprof/config" ]

  [ ! -L "$prof2/config/skills.json" ]
  jq -e '.entries == [{"path": "/custom"}]' "$prof2/config/skills.json"
  [ "$(readlink "$prof2/config/plugins.json")" = "$HOME/.gemini/config/plugins.json" ]
  [[ $output == *"skip $prof2/config/skills.json (provider-specific file)"* ]] || false

  before_backups=$(count_backups)
  run_install
  [ "$status" -eq 0 ]
  [ "$(count_backups)" -eq "$before_backups" ]
  [[ $output != *"+ ln -s"* ]] || false
}
