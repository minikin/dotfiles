#!/usr/bin/env bats
# bin/agent-preflight against stub moshi-hook, rex, claude, codex, launchctl, jj and agy.

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
  default='{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":36,"windowDurationMins":10080,"resetsAt":1795936747}}}}'
  echo "${STUB_LIMITS:-$default}"
  exit 0
fi
[[ -n ${OPENAI_API_KEY:-}${CODEX_API_KEY:-} ]] && { echo "Logged in using an API key - sk-test"; exit 0; }
echo "${STUB_CODEX:-Logged in using ChatGPT}"
EOF
  # STUB_JJ_<KEY>=none makes `config get` fail as for an unset key. STUB_JJ_ROOT is the main
  # checkout `workspace root --name default` prints, none outside a repo.
  stub jj <<'EOF'
echo "jj $*" >>"$STUB_LOG"
[[ $1 == --ignore-working-copy ]] || exit 9
get() { [[ $1 == none ]] && exit 1; echo "$1"; exit 0; }
case "$2 $3 $4" in
  "config get user.name") get "${STUB_JJ_NAME:-Example Person}" ;;
  "config get user.email") get "${STUB_JJ_EMAIL:-someone@example.com}" ;;
  "config get signing.behavior") get "${STUB_JJ_BEHAVIOR:-own}" ;;
  "config get signing.key") get "${STUB_JJ_KEY:-ssh-ed25519 AAAAtestnotakey}" ;;
  "workspace root --name") [[ -n ${STUB_JJ_ROOT:-} ]] || exit 1; echo "$STUB_JJ_ROOT" ;;
  *) exit 9 ;;
esac
EOF
}

# agy_ready: a stub agy plus the hooks.json, guard script and skill link install.sh would write.
agy_ready() {
  stub agy <<'EOF'
exit 0
EOF
  mkdir -p "$HOME/.gemini/config/hooks" "$HOME/.gemini/config/skills" "$HOME/skills-src/rex-orchestrator" "$HOME/.claude/skills"
  jq '. + {"other": {"enabled": false, "PreToolUse": []}}' "$REPO_ROOT/agy/hooks.fragment.json" >"$HOME/.gemini/config/hooks.json"
  printf '#!/bin/sh\n' >"$HOME/.gemini/config/hooks/dotfiles-guard-agents.zsh"
  chmod +x "$HOME/.gemini/config/hooks/dotfiles-guard-agents.zsh"
  ln -s "$HOME/skills-src/rex-orchestrator" "$HOME/.claude/skills/rex-orchestrator"
  ln -s "$(cd "$HOME/skills-src/rex-orchestrator" && pwd -P)" "$HOME/.gemini/config/skills/rex-orchestrator"
}

# hooks_set <jq filter>: rewrite the fake hooks.json with a filter on the dotfiles entry.
hooks_set() {
  local f="$HOME/.gemini/config/hooks.json"
  jq "$1" "$f" >"$f.new" && mv "$f.new" "$f"
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
  [ "${#lines[@]}" -eq 7 ]
  [[ $output == *"ok    jj: identity set, signing configured"* ]] || false
  [[ $output != *agy:* && $output != *"codex profile"* ]] || false
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
  ANTHROPIC_API_KEY=test-not-a-key OPENAI_API_KEY=test-not-a-key CODEX_API_KEY=test-not-a-key preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: set in this shell: ANTHROPIC_API_KEY OPENAI_API_KEY CODEX_API_KEY"* ]] || false
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

@test "preflight: never prints a value, a name, an email, a key, a home path or the Moshi host name" {
  agy_ready
  mkdir -p "$HOME/src/app"
  ANTHROPIC_API_KEY=test-not-a-key STUB_LAUNCHD_VAR=OPENAI_API_KEY STUB_JJ_ROOT="$HOME/src/app" preflight --limits
  [[ $output != *test-not-a-key* ]] || false
  [[ $output != *example.com* ]] || false
  [[ $output != *Example-Host* ]] || false
  [[ $output != *"Example Person"* ]] || false
  [[ $output != *AAAAtestnotakey* ]] || false
  [[ $output != *sk-test* ]] || false
  [[ $output != *"$HOME"* ]] || false
  STUB_JJ_EMAIL=you@work.example preflight
  [[ $output != *you@work.example* ]] || false
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
  [[ $output == *"FAIL  env: cannot check launchd for ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CODEX_API_KEY CODEX_HOME (launchctl getenv failed)"* ]] || false
  [[ $output != *"no API-key variables in launchd"* ]] || false

  rm "$STUBS/launchctl"
  local tools="$BATS_TEST_TMPDIR/tools" t
  mkdir -p "$tools"
  for t in sed head grep env sleep tr cat; do ln -s "$(command -v "$t")" "$tools/$t"; done
  PATH="$STUBS:$tools" AGENT_PREFLIGHT_WAIT=0 run /bin/bash "$REPO_ROOT/bin/agent-preflight"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: cannot check launchd (launchctl not found)"* ]] || false
}

@test "preflight: --limits picks the weekly window by duration, primary or secondary" {
  STUB_LIMITS='{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":1795936747},"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1795936747}}}}' \
    preflight --limits
  [[ $output == *"codex limit: 12 percent used of 7-day window"* ]] || false
  [[ $output != *"0-day"* ]] || false
  STUB_LIMITS='{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":1795936747}}}}' \
    preflight --limits
  [[ $output == *"codex limit: no weekly window in the answer"* ]] || false
}

@test "preflight: a failed launchd lookup still reports the names the other lookups found" {
  stub launchctl <<'STUB'
[[ $2 == ANTHROPIC_API_KEY ]] && exit 3
[[ $2 == OPENAI_API_KEY ]] && echo test-not-a-key
exit 0
STUB
  preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  env: set in launchd: OPENAI_API_KEY"* ]] || false
  [[ $output == *"FAIL  env: cannot check launchd for ANTHROPIC_API_KEY (launchctl getenv failed)"* ]] || false
  [[ $output != *test-not-a-key* ]] || false
}

@test "preflight: the codex app-server stub prints one valid JSON value, default or custom" {
  run bash -c '"$1" app-server </dev/null | jq -e -s "length == 1 and .[0].id == 2"' _ "$STUBS/codex"
  [ "$status" -eq 0 ]
  STUB_LIMITS='{"id":2,"result":{}}' run bash -c '"$1" app-server </dev/null | jq -e -s "length == 1 and .[0].id == 2"' _ "$STUBS/codex"
  [ "$status" -eq 0 ]
}

@test "preflight: jj is asked read-only, never snapshotting a working copy" {
  preflight
  [ "$status" -eq 0 ]
  ! grep '^jj ' "$STUB_LOG" | grep -v '^jj --ignore-working-copy ' || false
}

@test "preflight: jj without an identity, with template placeholders or without signing fails" {
  STUB_JJ_EMAIL=none preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  jj: no user.name or user.email"* ]] || false
  STUB_JJ_NAME='Your Name' preflight
  [[ $output == *"FAIL  jj: identity has template placeholders"* ]] || false
  STUB_JJ_EMAIL=you@personal.example preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  jj: identity has template placeholders"* ]] || false
  STUB_JJ_BEHAVIOR=none preflight
  [[ $output == *"FAIL  jj: commit signing is not configured"* ]] || false
  STUB_JJ_BEHAVIOR=drop preflight
  [[ $output == *"FAIL  jj: commit signing is not configured"* ]] || false
  STUB_JJ_KEY='ssh-ed25519 AAAA...your-work-key' preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  jj: commit signing is not configured"* ]] || false
  STUB_JJ_BEHAVIOR=force preflight
  [ "$status" -eq 0 ]
}

@test "preflight: no jj on PATH fails" {
  rm "$STUBS/jj"
  preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  jj: not installed"* ]] || false
  [[ $output != *"codex profile"* ]] || false
}

@test "preflight: agy with its guard hook and Rex skill in place passes, an unrelated disabled hook too" {
  agy_ready
  preflight
  [ "$status" -eq 0 ]
  [[ $output == *"ok    agy: guard hook registered"* ]] || false
  [[ $output == *"ok    agy: rex-orchestrator skill linked to Claude's"* ]] || false
  [ "${#lines[@]}" -eq 9 ]
}

@test "preflight: an agy guard entry that is missing, disabled, unmatched or another command fails" {
  agy_ready
  local filter
  for filter in 'del(.["dotfiles-agent-guard"])' \
                '.["dotfiles-agent-guard"].enabled = false' \
                '.["dotfiles-agent-guard"].PreToolUse[0].matcher = "run_command"' \
                '.["dotfiles-agent-guard"].PreToolUse[0].hooks[0].type = "script"' \
                '.["dotfiles-agent-guard"].PreToolUse[0].hooks[0].command = "~/other.zsh"' \
                '.["dotfiles-agent-guard"] = []'; do
    cp "$REPO_ROOT/agy/hooks.fragment.json" "$HOME/.gemini/config/hooks.json"
    hooks_set "$filter"
    preflight
    [ "$status" -eq 1 ] || { echo "passed with: $filter"; return 1; }
    [[ $output == *"FAIL  agy: guard hook dotfiles-agent-guard missing, disabled or changed"* ]] || false
  done
}

@test "preflight: agy with no hooks.json, invalid JSON, a missing guard script or no jq fails" {
  agy_ready
  printf '{"dotfiles-agent-guard": ' >"$HOME/.gemini/config/hooks.json"
  preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  agy: ~/.gemini/config/hooks.json is not valid JSON"* ]] || false

  rm "$HOME/.gemini/config/hooks.json"
  preflight
  [[ $output == *"FAIL  agy: no ~/.gemini/config/hooks.json"* ]] || false

  cp "$REPO_ROOT/agy/hooks.fragment.json" "$HOME/.gemini/config/hooks.json"
  chmod -x "$HOME/.gemini/config/hooks/dotfiles-guard-agents.zsh"
  preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  agy: guard hook script ~/.gemini/config/hooks/dotfiles-guard-agents.zsh is missing or not executable"* ]] || false

  rm "$STUBS/jq"
  local tools="$BATS_TEST_TMPDIR/tools" t
  mkdir -p "$tools"
  for t in sed head grep env sleep tr cat readlink; do ln -s "$(command -v "$t")" "$tools/$t"; done
  PATH="$STUBS:$tools" AGENT_PREFLIGHT_WAIT=0 run /bin/bash "$REPO_ROOT/bin/agent-preflight"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  agy: jq is missing"* ]] || false
}

@test "preflight: agy's Rex skill linked elsewhere fails, no Claude skill or no agy says nothing" {
  agy_ready
  rm "$HOME/.gemini/config/skills/rex-orchestrator"
  ln -s "$HOME/elsewhere" "$HOME/.gemini/config/skills/rex-orchestrator"
  preflight
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  agy: ~/.gemini/config/skills/rex-orchestrator does not link to Claude's skill"* ]] || false

  rm "$HOME/.claude/skills/rex-orchestrator"
  preflight
  [ "$status" -eq 0 ]
  [[ $output != *rex-orchestrator* ]] || false

  rm "$STUBS/agy"
  printf 'broken' >"$HOME/.gemini/config/hooks.json"
  preflight
  [ "$status" -eq 0 ]
  [[ $output != *agy:* ]] || false
}

@test "preflight: in a jj repo the Codex profile is information, by the main checkout's name" {
  mkdir -p "$HOME/src/app" "$HOME/.codex"
  STUB_JJ_ROOT="$HOME/src/app" preflight
  [ "$status" -eq 0 ]
  [[ $output == *"info  codex profile: no ~/.codex/app.config.toml, jwx will not start Codex here"* ]] || false

  sed 's|/path/to/<repo>|/path/to/app|' "$REPO_ROOT/codex/repo-profile.example.toml" >"$HOME/.codex/app.config.toml"
  STUB_JJ_ROOT="$HOME/src/app" preflight
  [ "$status" -eq 0 ]
  [[ $output == *"info  codex profile: ~/.codex/app.config.toml names no writable root for this checkout's .jj"* ]] || false

  sed "s|/path/to/<repo>|$HOME/src/app|" "$REPO_ROOT/codex/repo-profile.example.toml" >"$HOME/.codex/app.config.toml"
  STUB_JJ_ROOT="$HOME/src/app" preflight
  [ "$status" -eq 0 ]
  [[ $output == *"ok    codex profile: ~/.codex/app.config.toml"* ]] || false

  # The same rule as jwx: only the absolute path counts, a ~/ root is not known to work in Codex.
  printf 'writable_roots = ["~/src/app/.jj"]\n' >"$HOME/.codex/app.config.toml"
  STUB_JJ_ROOT="$HOME/src/app" preflight
  [[ $output == *"info  codex profile: ~/.codex/app.config.toml names no writable root"* ]] || false
}

@test "preflight: --help shows the usage and the new checks" {
  preflight --help
  [ "$status" -eq 0 ]
  [[ $output == *"Usage: agent-preflight [--limits] | --help"* ]] || false
  [[ $output == *"jj identity and signing configured"* ]] || false
  [[ $output != *set\ -uo* ]] || false
}
