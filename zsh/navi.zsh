# navi: Ctrl-G opens the saved workflows (navi/*.cheat) and inserts the chosen
# command into the prompt without running it. Commands that use zsh functions
# (jw, jwc, jwrm, jpush, jland, infra) only work this way, because navi runs pickers in bash.
(( $+commands[navi] )) || return 0
eval "$(navi widget zsh)"

# Column widths: navi's defaults give the one-word group tag a quarter of the screen and
# cut long commands off. A config file of your own (navi info config-path) wins.
if [[ -z ${NAVI_CONFIG_YAML:-} && ! -f ${NAVI_CONFIG:-$HOME/.config/navi/config.yaml} ]]; then
  export NAVI_CONFIG_YAML='
style:
  tag:     { color: cyan, width_percentage: 10, min_width: 8 }
  comment: { color: blue, width_percentage: 40, min_width: 30 }
  snippet: { color: white }
finder:
  command: fzf
shell:
  command: bash
'
fi

# Per-project workflows: a repo's .navi/ folder is loaded only when the repo is
# trusted, because opening the palette runs the picker commands in those files.
# Trusted: the main checkout lives under $DOTFILES_PERSONAL_DIR (the second identity's
# folder chosen in install.sh, if any), or its path is listed in
# ~/.config/navi/trusted-repos (one per line, managed by navi-trust).
# NAVI_PATH replaces navi's default folder, so it always lists that folder first.
: "${NAVI_DEFAULT_PATH:=$HOME/.local/share/navi/cheats}"
NAVI_TRUST_FILE=${NAVI_TRUST_FILE:-$HOME/.config/navi/trusted-repos}

# Main checkout of the current repo (the same for every jj workspace of it).
_navi_main_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  print -r -- "${common:h}"
}

_navi_trusted() {
  local main=$1
  local own=${DOTFILES_PERSONAL_DIR:-}
  # :A resolves symlinks, since git reports the physical path
  [[ -n $own && ( $main == $own/* || $main == ${own:A}/* ) ]] && return 0
  [[ -f $NAVI_TRUST_FILE ]] && grep -qxF -- "$main" "$NAVI_TRUST_FILE"
}

_navi_update_path() {
  local top main
  top=$(git rev-parse --show-toplevel 2>/dev/null) && main=$(_navi_main_root) &&
    [[ -d $top/.navi ]] && _navi_trusted "$main" &&
    { export NAVI_PATH="$NAVI_DEFAULT_PATH:$top/.navi"; return; }
  unset NAVI_PATH
}

navi-trust() {
  local main
  main=$(_navi_main_root) || { echo "not in a git or jj repo" >&2; return 1; }
  mkdir -p "${NAVI_TRUST_FILE:h}"
  grep -qxF -- "$main" "$NAVI_TRUST_FILE" 2>/dev/null || print -r -- "$main" >> "$NAVI_TRUST_FILE"
  _navi_update_path
  echo "trusted: $main"
}
navi-untrust() {
  local main
  main=$(_navi_main_root) || { echo "not in a git or jj repo" >&2; return 1; }
  if [[ -f $NAVI_TRUST_FILE ]]; then
    { grep -vxF -- "$main" "$NAVI_TRUST_FILE" || true; } > "$NAVI_TRUST_FILE.tmp"
    mv "$NAVI_TRUST_FILE.tmp" "$NAVI_TRUST_FILE"
  fi
  _navi_update_path
  echo "untrusted: $main"
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _navi_update_path
_navi_update_path
