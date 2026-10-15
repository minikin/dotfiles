# reload: check every config, then restart zsh to apply the shell side.
# jj, mise and starship read their config on every command or prompt, so they need nothing.
# Ghostty is only validated: its reload action has no safe trigger from a shell.
reload() {
  local f ghostty=${GHOSTTY_BIN:-/Applications/Ghostty.app/Contents/MacOS/ghostty}
  (( $+commands[ghostty] )) && [[ -z ${GHOSTTY_BIN:-} ]] && ghostty=${commands[ghostty]}
  if [[ -x $ghostty ]]; then
    "$ghostty" +validate-config || return 1
    echo "ghostty: config valid, press cmd+shift+, to apply it"
  fi
  if (( $+commands[jj] )) && ! jj config list >/dev/null 2>&1; then
    echo "reload: jj config is invalid, see: jj config list" >&2; return 1
  fi
  # exec into a shell that cannot parse its rc files would leave a broken terminal.
  for f in ~/.zshrc ~/.config/zsh/*.zsh(N); do
    zsh -n "$f" 2>/dev/null || { echo "reload: syntax error in $f, see: zsh -n $f" >&2; return 1; }
  done
  rm -f ~/.zcompdump*(N)
  echo "zsh: restarting"
  exec zsh
}
