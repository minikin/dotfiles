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
  [[ $output == *"+ ln -s"* ]]
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
  [[ $output == *"settings.json (unchanged)"* ]]
  [[ $output != *"+ ln -s"* ]]
}

@test "install: an existing plain file is backed up before being replaced" {
  printf 'my old zshrc\n' > "$HOME/.zshrc"
  run_install
  [ "$status" -eq 0 ]
  [[ $HOME/.zshrc -ef $DOTFILES/zsh/zshrc ]]
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
  [[ $output == *"merge failed"* ]]
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

@test "install: parent dir already linked into the repo is left alone" {
  mkdir -p "$HOME/.config"
  ln -s "$DOTFILES/ghostty" "$HOME/.config/ghostty"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$HOME/.config/ghostty" ]
  [ -f "$DOTFILES/ghostty/config" ]
  [ ! -L "$DOTFILES/ghostty/config" ]
  [ -z "$(find "$DOTFILES/ghostty" -name '*.bak-*')" ]
  [[ $HOME/.config/ghostty/config -ef $DOTFILES/ghostty/config ]]
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
  [[ $output == *"no terminal"* ]]
}

@test "install: template placeholders are never copied into git identity" {
  run_install
  [ "$status" -eq 0 ]
  run git config --global user.email
  [ "$status" -ne 0 ]
  run git config --global user.name
  [ "$status" -ne 0 ]
  run_install
  [[ $output == *"still has placeholders"* ]]
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
  [[ $output == *"neither a public key line nor an existing .pub file"* ]]
  [ ! -e "$HOME/.config/jj/conf.d/identity.toml" ]
}

@test "install: first run without settings.json does not claim a backup it never made" {
  run_install
  [ "$status" -eq 0 ]
  [ -z "$(find "$HOME/.claude" -name 'settings.json.bak-*')" ]
  [[ $output != *"(backup:"* ]]
}

@test "install: one identity only writes no second scope and no includeIf" {
  ssh-keygen -q -t ed25519 -N '' -f "$BATS_TEST_TMPDIR/k"
  export DOTFILES_NAME=Solo DOTFILES_EMAIL=solo@example.com DOTFILES_SIGNING_KEY="$BATS_TEST_TMPDIR/k.pub"
  run_install
  [ "$status" -eq 0 ]
  ! grep -q -- '--scope' "$HOME/.config/jj/conf.d/identity.toml"
  run git config --global --get-regexp '^includeif\.'
  [ -z "$output" ]
  [ ! -e "$HOME/.config/git/personal.gitconfig" ]
  ! grep -q DOTFILES_PERSONAL_DIR "$HOME/.config/dotfiles/config"
}

@test "install: a second email without its folder (or the reverse) is refused" {
  export DOTFILES_NAME=X DOTFILES_EMAIL=x@example.com DOTFILES_PERSONAL_EMAIL=y@example.org
  run_install
  [ "$status" -eq 2 ]
  [[ $output == *"together"* ]]
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
  grep -qF -- "--when.repositories = [\"$BATS_TEST_TMPDIR/outside\"]" "$HOME/.config/jj/conf.d/identity.toml"
  git config --global --get "includeIf.gitdir:$BATS_TEST_TMPDIR/outside/.path" >/dev/null
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
  [[ $output == *"$conf (unchanged)"* ]]
}

@test "install: the template's placeholder folder never becomes DOTFILES_PERSONAL_DIR" {
  run_install
  [ "$status" -eq 0 ]
  ! grep -q DOTFILES_PERSONAL_DIR "$HOME/.config/dotfiles/config"
}
