#!/usr/bin/env bash
# Install the dotfiles: symlink configs into $HOME (backing up anything in the way),
# merge Claude Code settings, add the mise line to .zprofile, sync git identity from jj.
# Safe to re-run. Usage: ./install.sh [--dry-run | --help]
# Identity: prompts on first run, or set DOTFILES_NAME / DOTFILES_EMAIL / DOTFILES_SIGNING_KEY,
# plus DOTFILES_PERSONAL_DIR / DOTFILES_PERSONAL_EMAIL / DOTFILES_PERSONAL_KEY for an optional
# second identity used in one folder, to run without prompts.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
DRY=0
case ${1:-} in
  "") ;;
  --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown argument: $1 (usage: ./install.sh [--dry-run | --help])" >&2; exit 2 ;;
esac
STAMP=$(date +%Y%m%d-%H%M%S)

run() { echo "+ $*"; (( DRY )) || "$@"; }

link() {  # link <repo-relative src> <dest>
  local src=$REPO/$1 dest=$2
  # -ef also catches a parent dir that already links into the repo (prevents renaming
  # the repo's own file and creating a self-referencing symlink)
  if [[ $dest -ef $src ]]; then
    echo "ok   $dest"; return
  fi
  run mkdir -p "$(dirname "$dest")"
  if [[ -e $dest || -L $dest ]]; then
    run mv "$dest" "$dest.bak-$STAMP"
  fi
  run ln -s "$src" "$dest"
}

echo "== symlinks"
link ghostty/config           "$HOME/.config/ghostty/config"
link zsh/zshrc                "$HOME/.zshrc"
link zsh/jj.zsh               "$HOME/.config/zsh/jj.zsh"
link zsh/sign.zsh             "$HOME/.config/zsh/sign.zsh"
link zsh/infra.zsh            "$HOME/.config/zsh/infra.zsh"
link zsh/navi.zsh             "$HOME/.config/zsh/navi.zsh"
link navi                     "$HOME/.local/share/navi/cheats/dotfiles"
link infra/compose.yaml       "$HOME/.config/devinfra/compose.yaml"
link starship/starship.toml   "$HOME/.config/starship.toml"
link jj/config.toml           "$HOME/.config/jj/config.toml"   # identity lives in conf.d/identity.toml (below)
link mise/config.toml         "$HOME/.config/mise/config.toml"
link claude/CLAUDE.md         "$HOME/.claude/CLAUDE.md"
link claude/statusline.sh     "$HOME/.claude/statusline.sh"

# Ghostty on macOS also reads this file *after* ~/.config/ghostty/config; an empty or stale
# copy silently overrides settings, so move it aside.
GHOSTTY_MAC="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
[[ -f $GHOSTTY_MAC ]] && run mv "$GHOSTTY_MAC" "$GHOSTTY_MAC.bak-$STAMP"

echo "== .zprofile (append mise shims line if missing)"
if ! grep -qs 'mise activate zsh --shims' "$HOME/.zprofile"; then
  if (( DRY )); then echo "+ append zsh/zprofile.snippet >> ~/.zprofile"
  else { echo; cat "$REPO/zsh/zprofile.snippet"; } >> "$HOME/.zprofile"; fi
else
  echo "ok   ~/.zprofile"
fi

echo "== Claude Code settings (merge; fragment keys win, permission allow/deny lists are unioned)"
SETTINGS=$HOME/.claude/settings.json
if (( DRY )); then
  echo "+ merge claude/settings.fragment.json into $SETTINGS"
else
  command -v jq >/dev/null || { echo "jq is required — run: brew bundle" >&2; exit 1; }
  mkdir -p "$HOME/.claude"
  # Merge into a temp file and only replace on success, so a jq failure (bad JSON,
  # empty file) never leaves settings.json truncated. An empty file counts as {}.
  jq -n --slurpfile cur <(cat "$SETTINGS" 2>/dev/null || true) \
        --slurpfile add "$REPO/claude/settings.fragment.json" '
    ($cur[0] // {}) as $c | $add[0] as $a
    | ($c * $a)
    | .permissions.allow = ((($c.permissions.allow // []) + ($a.permissions.allow // [])) | unique)
    | .permissions.deny  = ((($c.permissions.deny  // []) + ($a.permissions.deny  // [])) | unique)
  ' > "$SETTINGS.tmp" || { rm -f "$SETTINGS.tmp"; echo "settings merge failed; $SETTINGS untouched" >&2; exit 1; }
  if [[ -f $SETTINGS ]] && jq -e --slurpfile n "$SETTINGS.tmp" '. == $n[0]' "$SETTINGS" >/dev/null 2>&1; then
    rm -f "$SETTINGS.tmp"; echo "ok   $SETTINGS (unchanged)"
  else
    if [[ -f $SETTINGS ]]; then
      cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
      mv "$SETTINGS.tmp" "$SETTINGS"
      echo "ok   $SETTINGS updated (backup: $SETTINGS.bak-$STAMP)"
    else
      mv "$SETTINGS.tmp" "$SETTINGS"
      echo "ok   $SETTINGS created"
    fi
  fi
fi

echo "== identity (local only: ~/.config/jj/conf.d/identity.toml — never in this repo)"
IDENTITY=$HOME/.config/jj/conf.d/identity.toml
NAME='' EMAIL=''
OP_SIGN=/Applications/1Password.app/Contents/MacOS/op-ssh-sign
toml() { local s=${1//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; }
# key_info <input>: sets KEY (jj signing.key), PROG (signer), PUB (public key text) from a
# public key line ("ssh-ed25519 AAAA...", signed via an agent) or a path to a .pub file.
key_info() {
  local in=${1/#\~/$HOME}
  if [[ $in == ssh-* || $in == ecdsa-* || $in == sk-* ]]; then
    KEY=$in PUB=$in
    if [[ -x $OP_SIGN ]]; then PROG=$OP_SIGN; else PROG=/usr/bin/ssh-keygen; fi
  elif [[ -f $in ]]; then
    PUB=$(<"$in")
    # A private key path passes -f too, and PUB ends up in allowed_signers.
    if [[ $PUB == *$'\n'* || ! ( $PUB == ssh-* || $PUB == ecdsa-* || $PUB == sk-* ) ]]; then
      PUB=''; echo "!! '$1' is not a public key file (expected one 'ssh-...' line, e.g. a .pub file)" >&2; return 1
    fi
    KEY=$in PROG=/usr/bin/ssh-keygen
  else
    echo "!! '$1' is neither a public key line nor an existing .pub file" >&2; return 1
  fi
}
if [[ -f $IDENTITY ]]; then
  echo "ok   $IDENTITY"
elif (( DRY )); then
  echo "+ create $IDENTITY (asks for name, emails, signing keys)"
elif [[ -z ${DOTFILES_NAME:-} && ! -t 0 ]]; then
  mkdir -p "${IDENTITY%/*}"; cp "$REPO/jj/identity.example.toml" "$IDENTITY"; chmod 600 "$IDENTITY"
  echo "!! no terminal: copied the template to $IDENTITY — edit it before committing"
  echo "   commit signing is off until you fill in and uncomment its [signing] block"
  echo "   (or re-run with DOTFILES_NAME, DOTFILES_EMAIL, DOTFILES_SIGNING_KEY and optionally DOTFILES_PERSONAL_DIR, DOTFILES_PERSONAL_EMAIL, DOTFILES_PERSONAL_KEY set)"
else
  # Values come from DOTFILES_* env vars (non-interactive, e.g. Claude running SETUP_PROMPT.md)
  # or from prompts.
  # read takes the variable *name* from $var on purpose (indirect assignment).
  # shellcheck disable=SC2229
  ask() { local var=$1 prompt=$2 env=$3; if [[ -n ${DOTFILES_NAME:-} ]]; then printf -v "$var" '%s' "${!env:-}"; else read -rp "  $prompt" "$var"; fi; }
  [[ -z ${DOTFILES_NAME:-} ]] && echo "Set up your commit identity (stored only on this machine)."
  ask NAME   "Full name: " DOTFILES_NAME
  ask EMAIL  "Email, used in every repo: " DOTFILES_EMAIL
  if [[ -n ${DOTFILES_NAME:-} && -z $EMAIL ]]; then
    echo "!! DOTFILES_EMAIL must not be empty when DOTFILES_NAME is set" >&2; exit 2
  fi
  while [[ -z $NAME ]]; do read -rp "  Full name: " NAME; done
  while [[ -z $EMAIL ]]; do read -rp "  Email: " EMAIL; done
  ask KEYIN  "Signing key — public key line or path to .pub (empty = don't sign): " DOTFILES_SIGNING_KEY
  KEY='' PROG='' PUB=''
  while [[ -n $KEYIN ]] && ! key_info "$KEYIN"; do [[ -n ${DOTFILES_NAME:-} ]] && exit 1; read -rp "  Signing key (empty = don't sign): " KEYIN; done

  # Optional second identity (e.g. personal next to a work account) for every repo in
  # one folder of your choice.
  PEMAIL='' PDIR='' PKEY='' PPROG='' PPUB=''
  if [[ -n ${DOTFILES_NAME:-} ]]; then
    PEMAIL=${DOTFILES_PERSONAL_EMAIL:-} PDIR=${DOTFILES_PERSONAL_DIR:-}
    if [[ -n $PEMAIL && -z $PDIR || -z $PEMAIL && -n $PDIR ]]; then
      echo "!! set DOTFILES_PERSONAL_EMAIL and DOTFILES_PERSONAL_DIR together, or neither" >&2; exit 2
    fi
  else
    read -rp "  Use a second identity for the repos in one folder (e.g. personal projects)? [y/N] " yn
    if [[ $yn == [yY]* ]]; then
      while [[ -z $PDIR ]]; do read -rp "  Folder for those repos (e.g. ~/src/personal): " PDIR; done
      while [[ -z $PEMAIL ]]; do read -rp "  Email for that folder: " PEMAIL; done
    fi
  fi
  if [[ -n $PEMAIL ]]; then
    ask PKEYIN "Signing key for that folder — key line or .pub path (empty = same as above): " DOTFILES_PERSONAL_KEY
    while [[ -n $PKEYIN ]] && ! key_info "$PKEYIN"; do [[ -n ${DOTFILES_NAME:-} ]] && exit 1; read -rp "  Signing key for that folder: " PKEYIN; done
    [[ -n $PKEYIN ]] && PKEY=$KEY PPROG=$PROG PPUB=$PUB
    if [[ -n $KEYIN ]]; then key_info "$KEYIN"; else KEY='' PROG='' PUB=''; fi
    # One spelling for jj and git: ~/... inside $HOME (portable), absolute elsewhere.
    PDIR=${PDIR/#\~/$HOME}; PDIR=${PDIR%/}
    [[ $PDIR == /* ]] || { echo "!! folder must be an absolute path or start with ~: $PDIR" >&2; exit 2; }
    mkdir -p "$PDIR"
    # jj --when.repositories and git includeIf gitdir: compare against the physical repo path,
    # so a symlinked folder would silently never match.
    PDIR=$(cd "$PDIR" && pwd -P)
    HOME_REAL=$(cd "$HOME" && pwd -P)
    PDIR_ABS=$PDIR
    if [[ $PDIR == "$HOME_REAL"/* ]]; then PDIR_ABS=$HOME${PDIR#"$HOME_REAL"}; PDIR="~${PDIR#"$HOME_REAL"}"; fi
  fi
  mkdir -p "${IDENTITY%/*}"
  # NAME and EMAIL are assigned indirectly by ask (printf -v / read).
  # shellcheck disable=SC2153
  {
    echo "# Local identity + commit signing (NOT in the dotfiles repo). Template: jj/identity.example.toml"
    echo; echo "[user]"; echo "name = $(toml "$NAME")"; echo "email = $(toml "$EMAIL")"
    if [[ -n $KEY ]]; then
      echo; echo "[signing]"; echo 'backend = "ssh"'; echo 'behavior = "own"'
      echo "key = $(toml "$KEY")"; echo "backends.ssh.program = $(toml "$PROG")"
      echo 'backends.ssh.allowed-signers = "~/.config/git/allowed_signers"'
    fi
    if [[ -n $PEMAIL ]]; then
      echo; echo "# Second identity for every repo under $PDIR (override elsewhere: sign-as personal)"
      echo '[[--scope]]'; echo "--when.repositories = [$(toml "$PDIR")]"
      echo '[--scope.user]'; echo "email = $(toml "$PEMAIL")"
      if [[ -n $PKEY ]]; then
        echo '[--scope.signing]'; echo "key = $(toml "$PKEY")"; echo "backends.ssh.program = $(toml "$PPROG")"
      fi
    fi
  } > "$IDENTITY"
  chmod 600 "$IDENTITY"
  echo "ok   wrote $IDENTITY"

  # git: same identity + SSH signing, only where git has nothing configured yet
  if ! git config --global user.signingkey >/dev/null 2>&1 && [[ -n $KEY ]]; then
    git config --global gpg.format ssh
    git config --global user.signingkey "$KEY"
    git config --global gpg.ssh.program "$PROG"
    # Literal ~ on purpose: git expands it when reading the value, keeping the config portable.
    # shellcheck disable=SC2088
    git config --global gpg.ssh.allowedSignersFile "~/.config/git/allowed_signers"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    echo "ok   git signing (default key)"
  fi
  mkdir -p "$HOME/.config/git"; (umask 077; touch "$HOME/.config/git/allowed_signers"); chmod 600 "$HOME/.config/git/allowed_signers"
  [[ -n $PUB ]]  && ! grep -qsF "$EMAIL "  "$HOME/.config/git/allowed_signers" && echo "$EMAIL namespaces=\"git\" $PUB"  >> "$HOME/.config/git/allowed_signers"
  [[ -n $PPUB ]] && ! grep -qsF "$PEMAIL " "$HOME/.config/git/allowed_signers" && echo "$PEMAIL namespaces=\"git\" $PPUB" >> "$HOME/.config/git/allowed_signers"
  if [[ -n $PEMAIL ]] && ! git config --global --get-all "includeIf.gitdir:$PDIR/.path" >/dev/null 2>&1; then
    PGIT=$HOME/.config/git/personal.gitconfig
    git config -f "$PGIT" user.email "$PEMAIL"
    if [[ -n $PKEY ]]; then
      git config -f "$PGIT" user.signingkey "$PKEY"
      git config -f "$PGIT" gpg.ssh.program "$PPROG"
    fi
    git config --global "includeIf.gitdir:$PDIR/.path" "$PGIT"
    echo "ok   git second identity for $PDIR ($PGIT)"
  fi
fi

# ~/.config/dotfiles/config: machine settings read by zshrc. DOTFILES_DIR is where this repo
# lives. DOTFILES_PERSONAL_DIR is the second identity's folder, taken from this run's answers
# or from an existing identity.toml.
echo "== machine settings (~/.config/dotfiles/config)"
CONF=$HOME/.config/dotfiles/config
if [[ -z ${PDIR_ABS:-} && -f $IDENTITY ]]; then
  PDIR_ABS=$(sed -n 's/^--when\.repositories = \["\(.*\)"\]$/\1/p' "$IDENTITY" | head -1)
  PDIR_ABS=${PDIR_ABS/#\~/$HOME}
  [[ $PDIR_ABS == */path/to/* ]] && PDIR_ABS=''   # still the template placeholder
fi
if (( DRY )); then
  echo "+ write $CONF (DOTFILES_DIR=$REPO${PDIR_ABS:+, DOTFILES_PERSONAL_DIR=$PDIR_ABS})"
else
  mkdir -p "${CONF%/*}"
  {
    echo "# Written by install.sh, read by zshrc. Re-run install.sh to update."
    printf 'DOTFILES_DIR=%q\n' "$REPO"
    [[ -n ${PDIR_ABS:-} ]] && printf 'DOTFILES_PERSONAL_DIR=%q\n' "$PDIR_ABS"
  } > "$CONF.tmp"
  if cmp -s "$CONF.tmp" "$CONF"; then rm -f "$CONF.tmp"; echo "ok   $CONF (unchanged)"
  else mv "$CONF.tmp" "$CONF"; echo "ok   wrote $CONF"; fi
fi

echo "== git identity (copy from jj config if git has none)"
if git config --global user.email >/dev/null 2>&1; then
  echo "ok   git identity"
elif ! command -v jj >/dev/null; then
  echo "skip git identity: jj not installed (run brew bundle) — set it with git config --global user.email" >&2
else
  # From /, so a --when.repositories scope (the personal folder) can never apply.
  name=${NAME:-$(cd / && jj config get user.name 2>/dev/null || true)}
  email=${EMAIL:-$(cd / && jj config get user.email 2>/dev/null || true)}
  # Never copy jj/identity.example.toml's placeholders into git.
  if [[ $email == you@work.example || $name == "Your Name" ]]; then
    echo "skip git identity: $IDENTITY still has placeholders — edit it, then re-run" >&2
  else
    [[ -n $name ]]  && run git config --global user.name "$name"
    [[ -n $email ]] && run git config --global user.email "$email"
  fi
fi
command -v difft >/dev/null && run git config --global alias.dft '-c diff.external=difft diff'

echo "== checks"
if command -v ghostty >/dev/null || [[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then
  G=$(command -v ghostty || echo /Applications/Ghostty.app/Contents/MacOS/ghostty)
  (( DRY )) || { "$G" +validate-config && echo "ok   ghostty config valid"; }
fi
(( DRY )) || rm -f "$HOME"/.zcompdump* 2>/dev/null || true   # pick up new completions on next shell
echo "done — open a new terminal tab (or: exec zsh)"
