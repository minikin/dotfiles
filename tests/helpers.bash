# Shared helpers for the bats suite. Load with: load helpers
#
# Isolation rules:
#   - HOME is a fresh directory under BATS_TEST_TMPDIR, so nothing reads or writes the
#     real home (no ~/.config/jj/conf.d, so no 1Password signing config is ever loaded).
#   - jj reads only the repo's jj/config.toml (JJ_CONFIG) plus JJ_USER / JJ_EMAIL.
#   - git reads only $HOME/.gitconfig (GIT_CONFIG_GLOBAL) and never the system config.
#   - Anything that writes files does so below BATS_TEST_TMPDIR.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
# Captured once, before any test fakes HOME (used only to locate the docker compose plugin).
: "${ORIG_HOME:=$HOME}"
export ORIG_HOME

# fake_home: point every config lookup at a throwaway HOME under BATS_TEST_TMPDIR.
fake_home() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_CONFIG_HOME="$HOME/.config"
  unset XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME ZDOTDIR
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  unset GIT_CONFIG_SYSTEM GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  # Identity for git commands run directly by tests (e.g. pushing to a bare remote)
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  # jj: repo config only; identity from env; no signing config anywhere in sight
  export JJ_CONFIG="$REPO_ROOT/jj/config.toml"
  export JJ_USER=Test JJ_EMAIL=test@example.com
  export JJ_EDITOR=false EDITOR=false VISUAL=false
  export DOCKER_CONFIG="$HOME/.docker"
  unset DOTFILES_NAME DOTFILES_EMAIL DOTFILES_SIGNING_KEY DOTFILES_PERSONAL_EMAIL DOTFILES_PERSONAL_KEY DOTFILES_PERSONAL_DIR DOTFILES_DIR
  unset JW_NO_SETUP
  # The live shell exports these from navi.zsh, which would hide the defaults under test.
  unset NAVI_CONFIG NAVI_CONFIG_YAML NAVI_PATH
  # mise shims resolve tool versions from configs found via cwd (this repo's mise/config.toml)
  # and may hit the network, printing warnings into captured output.
  PATH=$(tr ':' '\n' <<<"$PATH" | grep -v '/mise/shims$' | paste -sd: -)
  export PATH
  # jj loads the per-repo config of the cwd's repo even under -R, so from a jj checkout it
  # warns about the missing config on stderr under the fake HOME, and `run` captures that.
  cd "$BATS_TEST_TMPDIR" || return 1
}

# copy_repo: copy the dotfiles tree (without VCS dirs) to $BATS_TEST_TMPDIR/dotfiles and set
# DOTFILES to it. install.sh then symlinks into the copy, so even a buggy run can never
# rename or overwrite a file in the real checkout.
copy_repo() {
  DOTFILES="$BATS_TEST_TMPDIR/dotfiles"
  mkdir -p "$DOTFILES"
  (cd "$REPO_ROOT" && tar -cf - --exclude ./.git --exclude ./.jj --exclude ./tests .) |
    (cd "$DOTFILES" && tar -xf -)
  export DOTFILES
}

# run_install [args...]: run the copied install.sh non-interactively (stdin from /dev/null).
run_install() {
  run bash "$DOTFILES/install.sh" "$@" </dev/null
}

# link_pairs: print "src<TAB>dest" (dest with $HOME expanded) for every `link` line in install.sh.
link_pairs() {
  local script=${1:-$DOTFILES/install.sh}
  awk '/^link[ \t]/ { print $2 "\t" $3 }' "$script" |
    sed -e 's/"//g' -e "s|\$HOME|$HOME|g"
}

# make_jj_repo <dir>: colocated jj repo with one committed change ("init") below an empty @.
make_jj_repo() {
  local dir=$1
  mkdir -p "$dir"
  (
    cd "$dir" || exit 1
    jj git init --colocate --quiet >/dev/null 2>&1 || jj git init --colocate >/dev/null 2>&1 || exit 1
    printf 'hello\n' > README.md
    printf '.env\n.env.local\n' > .gitignore
    jj commit -m init >/dev/null 2>&1
  )
}

# add_bare_remote <repo> <remote-dir>: create a bare git remote, push the init change as `main`
# and track it, so trunk() resolves to main@origin.
add_bare_remote() {
  local repo=$1 remote=$2
  git init --bare --quiet "$remote"
  (
    cd "$repo" || exit 1
    jj git remote add origin "$remote" || exit 1
    jj bookmark create main -r @- >/dev/null 2>&1 || exit 1
    jj git push --bookmark main >/dev/null 2>&1 || exit 1
  )
}

# run_zsh <script>: run zsh without any rc files, with zsh/jj.zsh loaded.
run_zsh() {
  run zsh -f -c "source '$REPO_ROOT/zsh/jj.zsh'; $1"
}

# realpath_of <dir>: physical path (macOS temp dirs live behind the /var -> /private/var link).
realpath_of() { (cd "$1" && pwd -P); }
