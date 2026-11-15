# remote-check: can the phone reach this Mac through Moshi right now? Run it after a reboot.
# "ok" is fine, "warn" sorts itself out on the next connection, "!!" needs you and makes it
# return 1. Read-only: it never starts or changes anything.
remote-check() {
  emulate -L zsh
  local fail=0 json out tool
  local plist=$HOME/Library/LaunchAgents/dev.osewa.server.plist devices=$HOME/.config/osewa/devices

  # The services below are per-user launch agents, and launchd starts those only at login.
  [[ $(fdesetup status 2>/dev/null) == 'FileVault is On.'* ]] &&
    print -r -- "note FileVault is on: after a reboot nothing below runs until you log in at the Mac"

  if (( ! $+commands[tailscale] )); then
    print -r -- "!!   tailscale: no CLI on PATH, turn it on in the Tailscale app's settings"; fail=1
  elif ! json=$(tailscale status --json 2>/dev/null) || [[ $(jq -r .BackendState <<<$json) != Running ]]; then
    print -r -- "!!   tailscale: not connected, fix: tailscale up"; fail=1
  else
    print -r -- "ok   tailscale: connected as $(jq -r '.Self.DNSName | rtrimstr(".")' <<<$json)"
    case $(jq -r 'if .ExitNodeStatus == null then "none" elif .ExitNodeStatus.Online then "online" else "offline" end' <<<$json) in
      online)  print -r -- "ok   tailscale: exit node online" ;;
      offline) print -r -- "warn tailscale: exit node offline, pick another in the Tailscale menu" ;;
    esac
  fi

  if nc -z -G 2 127.0.0.1 22 >/dev/null 2>&1; then
    print -r -- "ok   ssh: Remote Login is on"
  else
    print -r -- "!!   ssh: Remote Login is off, fix: moshi-hook host enable-ssh"; fail=1
  fi

  (( $+commands[moshi-hook] )) ||
    { print -r -- "!!   moshi-hook: not installed, fix: brew install rjyo/moshi/moshi-hook"; fail=1; }
  (( $+commands[osewa] )) ||
    { print -r -- "!!   osewa: not installed, fix: curl -fsSL https://osewa.dev/install.sh | sh"; fail=1; }

  # sshd hands a command an empty environment and a zsh that reads only ~/.zshenv. Moshi runs
  # moshi-hook and osewa that way, and falls back to mosh without a word when it can't.
  out=$(env -i HOME=$HOME /bin/zsh -c 'for t in moshi-hook osewa; do (( $+commands[$t] )) || print -r -- $t; done' 2>/dev/null)
  if [[ -z $out ]]; then
    print -r -- "ok   ssh: logins find moshi-hook and osewa"
  else
    print -r -- "!!   ssh: logins don't find ${(j:, :)${(f)out}}, fix: re-run install.sh (adds zsh/zshenv.snippet to ~/.zshenv)"; fail=1
  fi

  if (( $+commands[moshi-hook] )); then
    if [[ $(moshi-hook probe --json 2>/dev/null | jq -r .running 2>/dev/null) == true ]]; then
      print -r -- "ok   moshi-hook: daemon running"
    else
      print -r -- "!!   moshi-hook: daemon not running, fix: moshi-hook service install"; fail=1
    fi
    if moshi-hook status 2>/dev/null | grep -qE '^status:[[:space:]]+paired$'; then
      print -r -- "ok   moshi-hook: paired"
    else
      print -r -- "!!   moshi-hook: not paired, fix: moshi-hook pair, from the Moshi app's pairing screen"; fail=1
    fi
  fi

  if (( $+commands[moshi-hook] && $+commands[osewa] )); then
    json=$(moshi-hook osewa status 2>/dev/null)
    if [[ $(jq -r .running <<<$json 2>/dev/null) == true ]]; then
      print -r -- "ok   osewa: server running on port $(jq -r .port <<<$json)"
    elif [[ -f $plist ]]; then
      print -r -- "warn osewa: server not running, fix: launchctl kickstart gui/$UID/dev.osewa.server"
    else
      print -r -- "warn osewa: server not running, Moshi starts it on the next Osewa connection"
    fi
    if [[ -s $devices ]]; then
      print -r -- "ok   osewa: $(grep -c . $devices) device(s) enrolled"
    else
      print -r -- "warn osewa: no device enrolled, connect once from Moshi with Connection type Osewa"
    fi
  fi

  if (( $+commands[herdr] )); then
    if [[ $(herdr status server 2>/dev/null) == *'status: running'* ]]; then
      print -r -- "ok   herdr: server running"
    else
      print -r -- "warn herdr: server not running, the next herdr attach starts it"
    fi
  fi

  return $fail
}
