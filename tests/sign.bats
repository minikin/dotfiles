#!/usr/bin/env bats
# zsh/sign.zsh: sign-as writes per-repo identity overrides for jj and git.
# Keys and signers here are placeholders: no signing backend is configured, so nothing signs.

load helpers

PFILE_KEY="ssh-ed25519 AAAAplaceholderkeyfortests"

setup() {
  fake_home
  REPO="$HOME/src/app"
  make_jj_repo "$REPO"
  PFILE="$HOME/.config/git/personal.gitconfig"
}

# jj_repo <key>: the repo-level value only (JJ_EMAIL from fake_home overrides user.email otherwise)
jj_repo() {
  jj -R "$REPO" config list --repo --include-overridden "$1" -T 'value.as_string() ++ "\n"' 2>/dev/null
}

# jj_repo_unset <key>: true unless the repo config sets the key, even to ""
jj_repo_unset() {
  [ -z "$(jj -R "$REPO" config list --repo --include-overridden "$1" 2>/dev/null)" ]
}

run_sign() {
  run zsh -f -c "source '$REPO_ROOT/zsh/sign.zsh'; cd '$REPO' && $1"
}

personal_identity() {
  mkdir -p "${PFILE%/*}"
  git config -f "$PFILE" user.email personal@example.org
  if [ "${1:-}" = with-key ]; then
    git config -f "$PFILE" user.signingkey "$PFILE_KEY"
    git config -f "$PFILE" gpg.ssh.program /usr/bin/false
  fi
}

@test "sign-as personal: with its own key sets email, key and signer for jj and git" {
  personal_identity with-key
  run_sign "sign-as personal"
  [ "$status" -eq 0 ]
  [ "$(jj_repo user.email)" = personal@example.org ]
  [ "$(jj_repo signing.key)" = "$PFILE_KEY" ]
  [ "$(jj_repo signing.backends.ssh.program)" = /usr/bin/false ]
  [ "$(git -C "$REPO" config --local user.email)" = personal@example.org ]
  [ "$(git -C "$REPO" config --local user.signingkey)" = "$PFILE_KEY" ]
  [ "$(git -C "$REPO" config --local gpg.ssh.program)" = /usr/bin/false ]
}

@test "sign-as personal: without its own key sets only the email and keeps the main key" {
  personal_identity
  git -C "$REPO" config --local user.signingkey stale-key
  git -C "$REPO" config --local gpg.ssh.program stale-prog
  jj -R "$REPO" config set --repo signing.key stale-key
  run_sign "sign-as personal"
  [ "$status" -eq 0 ]
  [ "$(jj_repo user.email)" = personal@example.org ]
  [ "$(git -C "$REPO" config --local user.email)" = personal@example.org ]
  jj_repo_unset signing.key
  jj_repo_unset signing.backends.ssh.program
  run git -C "$REPO" config --local user.signingkey
  [ "$status" -ne 0 ]
  run git -C "$REPO" config --local gpg.ssh.program
  [ "$status" -ne 0 ]
}

@test "sign-as personal: without personal.gitconfig fails with one clear message" {
  run_sign "sign-as personal"
  [ "$status" -ne 0 ]
  [[ $output == *"no second identity set up"* ]]
  [[ $output != *fatal* ]]
  run git -C "$REPO" config --local user.email
  [ "$status" -ne 0 ]
}

@test "sign-as work: removes every per-repo override" {
  personal_identity with-key
  run_sign "sign-as personal"
  [ "$status" -eq 0 ]
  run_sign "sign-as work"
  [ "$status" -eq 0 ]
  for k in user.email signing.key signing.backends.ssh.program; do
    jj_repo_unset "$k" || { echo "jj still has $k"; return 1; }
  done
  for k in user.email user.signingkey gpg.ssh.program core.sshCommand; do
    run git -C "$REPO" config --local "$k"
    [ "$status" -ne 0 ] || { echo "git still has $k"; return 1; }
  done
}

@test "sign-as status: prints the identity and changes nothing" {
  personal_identity with-key
  run_sign "sign-as status"
  [ "$status" -eq 0 ]
  [[ $output == *"jj:  test@example.com"* ]]
  [[ $output == *"git: "* ]]
  run git -C "$REPO" config --local user.email
  [ "$status" -ne 0 ]
  jj_repo_unset user.email
}

@test "sign-as: outside a repo fails" {
  run zsh -f -c "source '$REPO_ROOT/zsh/sign.zsh'; cd '$HOME' && sign-as status"
  [ "$status" -ne 0 ]
  [[ $output == *"not in a repo"* ]]
}
