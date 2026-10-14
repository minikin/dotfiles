# sign-as [work|personal|status] — commit identity + signing key for the current repo.
# Default everywhere is the main identity; repos under $DOTFILES_PERSONAL_DIR (chosen in install.sh) use the second one.
# This sets a per-repo override for jj (shared by all its workspaces) and git.
sign-as() {
  local mode=${1:-status} pfile=~/.config/git/personal.gitconfig email key prog sshcmd
  if ! jj root >/dev/null 2>&1 && ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "not in a repo" >&2; return 1
  fi
  case $mode in
    personal)
      [[ -f $pfile ]] || { echo "no second identity set up: move ~/.config/jj/conf.d/identity.toml aside, re-run install.sh and answer yes to the second identity" >&2; return 1; }
      email=$(git config -f $pfile user.email)
      key=$(git config -f $pfile user.signingkey)
      prog=$(git config -f $pfile gpg.ssh.program)
      sshcmd=$(git config -f $pfile core.sshCommand)
      [[ $email == PERSONAL_EMAIL || -z $email ]] && { echo "fill in $pfile first" >&2; return 1; }
      # No key of its own means "same as the main key": drop the repo override instead of setting "".
      if jj root >/dev/null 2>&1; then
        jj config set --repo user.email "$email"
        if [[ -n $key ]]; then jj config set --repo signing.key "$key"
        else jj config unset --repo signing.key 2>/dev/null; fi
        if [[ -n $prog ]]; then jj config set --repo signing.backends.ssh.program "$prog"
        else jj config unset --repo signing.backends.ssh.program 2>/dev/null; fi
      fi
      git config --local user.email "$email"
      if [[ -n $key ]]; then git config --local user.signingkey "$key"
      else git config --local --unset user.signingkey 2>/dev/null; fi
      if [[ -n $prog ]]; then git config --local gpg.ssh.program "$prog"
      else git config --local --unset gpg.ssh.program 2>/dev/null; fi
      if [[ -n $sshcmd ]]; then git config --local core.sshCommand "$sshcmd"
      else git config --local --unset core.sshCommand 2>/dev/null; fi
      ;;
    work)
      if jj root >/dev/null 2>&1; then
        jj config unset --repo user.email 2>/dev/null
        jj config unset --repo signing.key 2>/dev/null
        jj config unset --repo signing.backends.ssh.program 2>/dev/null
      fi
      git config --local --unset user.email 2>/dev/null
      git config --local --unset user.signingkey 2>/dev/null
      git config --local --unset gpg.ssh.program 2>/dev/null
      git config --local --unset core.sshCommand 2>/dev/null
      ;;
    status) ;;
    *) echo "usage: sign-as [work|personal|status]" >&2; return 1 ;;
  esac
  if jj root >/dev/null 2>&1; then
    echo "jj:  $(jj config get user.email)  key …${$(jj config get signing.key)[-12,-1]}"
    if [[ $mode != status ]] && [[ $(jj log -r @ --no-graph -T 'author.email()') != $(jj config get user.email) ]]; then
      jj metaedit --update-author -r @ >/dev/null 2>&1 && echo "     updated author of @"
    fi
  fi
  echo "git: $(git config user.email)  key …${$(git config user.signingkey)[-12,-1]}"
}
