#!/usr/bin/env bats
# zsh/remote.zsh: remote-check reports what the phone needs to reach this Mac through Moshi.
# Every tool it calls is a stub, so it never reads the real Tailscale, launchd or Moshi state.

load helpers

setup() {
  fake_home
  STUBS="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS" "$HOME/.config/osewa"
  ln -s "$(command -v jq)" "$STUBS/jq"

  cat > "$STUBS/tailscale" <<'EOF'
#!/bin/sh
case ${TS_EXIT:-none} in
  none) node=null ;;
  online) node='{"Online":true}' ;;
  offline) node='{"Online":false}' ;;
esac
printf '{"BackendState":"%s","Self":{"DNSName":"mac.tail0.ts.net."},"ExitNodeStatus":%s}\n' "${TS_STATE:-Running}" "$node"
EOF
  cat > "$STUBS/nc" <<'EOF'
#!/bin/sh
[ -z "$NC_FAIL" ]
EOF
  cat > "$STUBS/fdesetup" <<'EOF'
#!/bin/sh
echo "FileVault is ${FV:-Off}."
EOF
  cat > "$STUBS/moshi-hook" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "probe --json") printf '{"installed":true,"running":%s}\n' "${MH_RUNNING:-true}" ;;
  "osewa status") printf '{"installed":true,"running":%s,"port":7322}\n' "${OSEWA_RUNNING:-true}" ;;
  "status ") echo "status:       ${MH_PAIRING:-paired}" ;;
esac
EOF
  cat > "$STUBS/herdr" <<'EOF'
#!/bin/sh
[ "$1 $2" = "status server" ] && echo "status: ${HERDR:-running}"
EOF
  printf '#!/bin/sh\n' > "$STUBS/osewa"
  chmod +x "$STUBS"/*

  # What install.sh's snippet does for ssh logins, pointed at the stubs.
  printf 'path=(%s $path)\n' "$STUBS" > "$HOME/.zshenv"
  printf '{"name":"phone","key":"AAAA"}\n' > "$HOME/.config/osewa/devices"
  # No /opt/homebrew or /usr/local: the real moshi-hook, herdr and tailscale live there.
  export PATH="$STUBS:/usr/bin:/bin"
}

run_check() {
  run zsh -f -c "source '$REPO_ROOT/zsh/remote.zsh'; remote-check"
}

@test "remote-check: everything up prints only ok lines and returns 0" {
  run_check
  [ "$status" -eq 0 ]
  [[ $output != *'!!'* && $output != *warn* && $output != *note* ]] || false
  [[ $output == *"ok   tailscale: connected as mac.tail0.ts.net"* ]] || false
  [[ $output == *"ok   ssh: logins find moshi-hook and osewa"* ]] || false
  [[ $output == *"ok   osewa: server running on port 7322"* ]] || false
  [[ $output == *"ok   osewa: 1 device(s) enrolled"* ]] || false
  [[ $output == *"ok   herdr: server running"* ]] || false
}

@test "remote-check: Tailscale stopped fails with the fix" {
  TS_STATE=Stopped run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   tailscale: not connected, fix: tailscale up"* ]] || false
}

@test "remote-check: no tailscale CLI fails" {
  rm "$STUBS/tailscale"
  run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   tailscale: no CLI on PATH"* ]] || false
}

@test "remote-check: an offline exit node only warns, an online one is ok" {
  TS_EXIT=offline run_check
  [ "$status" -eq 0 ]
  [[ $output == *"warn tailscale: exit node offline"* ]] || false
  TS_EXIT=online run_check
  [[ $output == *"ok   tailscale: exit node online"* ]] || false
}

@test "remote-check: Remote Login off fails" {
  NC_FAIL=1 run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   ssh: Remote Login is off, fix: moshi-hook host enable-ssh"* ]] || false
}

@test "remote-check: ssh logins without the .zshenv PATH fail and name both tools" {
  rm "$HOME/.zshenv"
  run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   ssh: logins don't find moshi-hook, osewa, fix: re-run install.sh"* ]] || false
}

@test "remote-check: a stopped or unpaired moshi-hook fails" {
  MH_RUNNING=false run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   moshi-hook: daemon not running"* ]] || false
  MH_PAIRING="not paired" run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   moshi-hook: not paired"* ]] || false
}

@test "remote-check: osewa not installed fails" {
  rm "$STUBS/osewa"
  run_check
  [ "$status" -eq 1 ]
  [[ $output == *"!!   osewa: not installed"* ]] || false
}

@test "remote-check: a stopped osewa server only warns, with launchctl when its agent exists" {
  OSEWA_RUNNING=false run_check
  [ "$status" -eq 0 ]
  [[ $output == *"warn osewa: server not running, Moshi starts it"* ]] || false
  mkdir -p "$HOME/Library/LaunchAgents"
  touch "$HOME/Library/LaunchAgents/dev.osewa.server.plist"
  OSEWA_RUNNING=false run_check
  [[ $output == *"fix: launchctl kickstart gui/"*"/dev.osewa.server"* ]] || false
}

@test "remote-check: no enrolled device and a stopped herdr only warn" {
  rm "$HOME/.config/osewa/devices"
  HERDR=stopped run_check
  [ "$status" -eq 0 ]
  [[ $output == *"warn osewa: no device enrolled"* ]] || false
  [[ $output == *"warn herdr: server not running"* ]] || false
}

@test "remote-check: FileVault on adds a note about logging in after a reboot" {
  FV=On run_check
  [ "$status" -eq 0 ]
  [[ $output == "note FileVault is on"* ]] || false
}
