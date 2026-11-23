#!/usr/bin/env bats
# bin/agent-preflight against stub moshi-hook, rex, claude, codex and launchctl.

load helpers

setup() {
  fake_home
  command -v jq >/dev/null || skip "jq not installed"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  ln -s "$(command -v jq)" "$STUBS/jq"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$STUB_LOG"

  stub moshi-hook <<'EOF'
printf 'status:       %s\nhost id:      host_0000\ndisplay name: Example-Host-Of-Someone\n' "${STUB_MOSHI:-paired}"
EOF
  stub rex <<'EOF'
echo "rex $*" >>"$STUB_LOG"
[[ $1 == --autostart=false ]] || exit 9
[[ ${STUB_REX:-up} == up ]] && echo '{"account":"someone"}' || exit 4
EOF
  stub launchctl <<'EOF'
[[ $1 == getenv && $2 == "${STUB_LAUNCHD_VAR:-none}" ]] && echo test-not-a-key
exit 0
EOF
  stub claude <<'EOF'
echo "claude $* key=${ANTHROPIC_API_KEY:-unset}" >>"$STUB_LOG"
method=${STUB_CLAUDE_METHOD:-claude.ai}
[[ -n ${ANTHROPIC_API_KEY:-} ]] && method=apiKey
printf '{"loggedIn":%s,"authMethod":"%s","email":"someone@example.com","subscriptionType":"max"}\n' "${STUB_CLAUDE_LOGGED:-true}" "$method"
EOF
  stub codex <<'EOF'
echo "codex $* key=${OPENAI_API_KEY:-unset}" >>"$STUB_LOG"
if [[ $1 == app-server ]]; then
  cat >/dev/null &
  echo '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":36,"windowDurationMins":10080,"resetsAt":1795936747}}}}'
  exit 0
fi
[[ -n ${OPENAI_API_KEY:-} ]] && { echo "Logged in using an API key - sk-test"; exit 0; }
echo "${STUB_CODEX:-Logged in using ChatGPT}"
EOF
}

# stub <name>: an executable in $STUBS with the body from stdin
stub() {
  { echo '#!/bin/bash'; cat; } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

preflight() {
  PATH="$STUBS:/usr/bin:/bin" AGENT_PREFLIGHT_WAIT=0 run "$REPO_ROOT/bin/agent-preflight" "$@"
}

@test "preflight: everything in order passes, one ok line per check" {
  preflight
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 6 ]
  [[ $output != *FAIL* ]] || false
  [[ $output == *"claude: logged in to claude.ai (max)"* ]] || false
}

@test "preflight: rex is asked without autostart" {
  preflight
  grep -qx 'rex --autostart=false whoami --json' "$STUB_LOG"
}

@test "preflight: an unpaired Moshi fails" {
  STUB_MOSHI=unpaired preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  moshi: unpaired"* ]] || false
}

@test "preflight: no Rex server fails" {
  STUB_REX=down preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  rex:"* ]] || false
}

@test "preflight: a key in the shell fails by name, and claude and codex still run without it" {
  ANTHROPIC_API_KEY=test-not-a-key OPENAI_API_KEY=test-not-a-key preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: set in this shell: ANTHROPIC_API_KEY OPENAI_API_KEY"* ]] || false
  [[ $output == *"ok    claude: logged in to claude.ai"* ]] || false
  [[ $output == *"ok    codex: logged in with ChatGPT"* ]] || false
  ! grep -q 'key=test-not-a-key' "$STUB_LOG" || false
}

@test "preflight: a key in launchd fails by name" {
  STUB_LAUNCHD_VAR=CODEX_HOME preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: set in launchd: CODEX_HOME"* ]] || false
}

@test "preflight: claude on an API key or logged out fails" {
  STUB_CLAUDE_METHOD=apiKey preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  claude: logged in with apiKey"* ]] || false
  STUB_CLAUDE_LOGGED=false preflight
  [[ $output == *"FAIL  claude: not logged in"* ]] || false
}

@test "preflight: codex without the ChatGPT login fails" {
  STUB_CODEX='Not logged in' preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  codex: not logged in with ChatGPT"* ]] || false
}

@test "preflight: never prints a value, an email or the Moshi host name" {
  ANTHROPIC_API_KEY=test-not-a-key STUB_LAUNCHD_VAR=OPENAI_API_KEY preflight --limits
  [[ $output != *test-not-a-key* ]] || false
  [[ $output != *example.com* ]] || false
  [[ $output != *Example-Host* ]] || false
  [[ $output != *sk-test* ]] || false
}

@test "preflight: --limits prints the codex weekly limit and says claude has no command" {
  preflight --limits
  [ "$status" -eq 0 ]
  [[ $output == *"codex limit: 36 percent used of 7-day window"* ]] || false
  [[ $output == *"claude limit: no command reads it"* ]] || false
}

@test "preflight: an unknown argument exits 2" {
  preflight --bogus
  [ "$status" -eq 2 ]
}

@test "preflight: a launchd check that cannot run fails instead of reporting ok" {
  stub launchctl <<'STUB'
exit 3
STUB
  preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: cannot check launchd (launchctl getenv failed)"* ]] || false
  [[ $output != *"no API-key variables in launchd"* ]] || false

  rm "$STUBS/launchctl"
  local tools="$BATS_TEST_TMPDIR/tools" t
  mkdir -p "$tools"
  for t in sed head grep env sleep tr cat; do ln -s "$(command -v "$t")" "$tools/$t"; done
  PATH="$STUBS:$tools" AGENT_PREFLIGHT_WAIT=0 run /bin/bash "$REPO_ROOT/bin/agent-preflight"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: cannot check launchd (launchctl not found)"* ]] || false
}
