#!/usr/bin/env bats
# agy/guard-agents.zsh: the Antigravity PreToolUse hook that keeps claude and codex off API keys.
# Payload shapes are the ones agy 1.5 sends: run_command {CommandLine, WaitMsBeforeAsync,
# toolSummary} and manage_task {Action, Input, TaskId}.

load helpers

setup() {
  fake_home
  command -v jq >/dev/null || skip "jq not installed"
  GUARD="$REPO_ROOT/agy/guard-agents.zsh"
}

# run_cmd <command line>: a run_command call, as agy sends it
run_cmd() {
  local json
  json=$(jq -nc --arg c "$1" \
    '{hookEventName: "PreToolUse", toolCall: {name: "run_command", args: {CommandLine: $c, WaitMsBeforeAsync: 500, toolSummary: "run it"}}}')
  run zsh -f "$GUARD" <<<"$json"
}

# send_input <text>: text typed into a running process through manage_task
send_input() {
  local json
  json=$(jq -nc --arg c "$1" \
    '{hookEventName: "PreToolUse", toolCall: {name: "manage_task", args: {Action: "send_input", Input: $c, TaskId: "t/task-1"}}}')
  run zsh -f "$GUARD" <<<"$json"
}

# raw <stdin>: anything as the hook input
raw() { run zsh -f "$GUARD" <<<"$1"; }

is_deny() {
  [ "$status" -eq 0 ] || return 1
  [[ $(jq -r '.decision' <<<"$output" 2>/dev/null) == deny ]] || return 1
  [[ $(jq -r 'keys | join(",")' <<<"$output") == decision,reason ]] || return 1
}

# assert_all <allow|deny> <run_cmd|send_input>: one command line per stdin line
assert_all() {
  local want=$1 via=$2 line bad=''
  while IFS= read -r line; do
    [[ -z $line ]] && continue
    "$via" "$line"
    if [[ $want == allow ]]; then
      [[ $status -eq 0 && -z $output ]] || bad+="  allow expected: $line -> $output"$'\n'
    else
      is_deny || bad+="  deny expected: $line -> $output"$'\n'
    fi
  done
  [[ -z $bad ]] || { printf '%s' "$bad" >&3; false; }
}

ALLOWED=$(cat <<'EOF'
env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude --model sonnet
env -u OPENAI_API_KEY -u CODEX_HOME codex -p repo
rex window new -s s1 a -c d --focus=false --keep-open --json -- env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude --model opus
rex window new -s s1 a -c d --focus=false --keep-open --json -- env -u OPENAI_API_KEY -u CODEX_HOME codex -s read-only -a never
rex send -s s1 -b b1 'env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude --model haiku'
rex send -s s1 -b b1 'env -u OPENAI_API_KEY -u CODEX_HOME codex -p repo'
ps eww -o command= -p 1 | tr ' ' '\n' | grep -oE '^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|CODEX_HOME)='
claude auth status
codex login status
claude --version
unset OPENAI_API_KEY
grep -r ANTHROPIC_API_KEY docs
jj describe -m "block op run claude"
rg codex
op run -- echo codex
ls > out.txt 2>&1
echo "$(date)" | tee -a log
for f in claude codex; do echo "$f"; done
EOF
)

DENIED=$(cat <<'EOF'
op run --env-file=.env -- claude
op run -- codex exec x
op run --env-file .env -- env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude
ANTHROPIC_API_KEY=x claude
ANTHROPIC_API_KEY=x claude --version
export OPENAI_API_KEY=x
declare -x CODEX_HOME=x
env CODEX_HOME=/tmp/x codex
launchctl setenv OPENAI_API_KEY x
codex login --with-api-key
printenv K | codex login --with-api-key
true & op run -- claude
if true; then op run -- claude; fi
for i in 1; do ANTHROPIC_API_KEY=x claude; done
(op run -- codex)
{ op run -- claude; }
echo $(op run -- claude)
echo `op run -- codex`
f() { op run -- claude; }; f
rex window new a -- op run -- claude
rex window new a -- env ANTHROPIC_AUTH_TOKEN=x claude
rex window new a -- 'op run -- claude'
bash -c 'ANTHROPIC_AUTH_TOKEN=x claude'
sh -lc "op run -- codex"
nohup timeout 5 op run -- claude &
x=1 && cd /tmp && ANTHROPIC_AUTH_TOKEN=t exec claude -p hi
EOF
)

# Q20 (a): every launch needs its own env -u prefix, also nested in Rex.
BARE=$(cat <<'EOF'
claude --model sonnet
/opt/homebrew/bin/codex -p repo
env -u ANTHROPIC_API_KEY claude
env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN rex window new a -- claude
rex window new a -- claude --model opus
rex run -- codex
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN; claude
EOF
)

@test "agy guard: prescribed launches and harmless commands pass with no output" {
  assert_all allow run_cmd <<<"$ALLOWED"
}

@test "agy guard: the same pass when typed into a running process" {
  assert_all allow send_input <<<"$ALLOWED"
}

@test "agy guard: API-key launches are denied, also in shell constructs and nested in Rex" {
  assert_all deny run_cmd <<<"$DENIED"
}

@test "agy guard: API-key launches typed into a running process are denied" {
  assert_all deny send_input <<<"$DENIED"
}

@test "agy guard: a launch without its env -u prefix is denied at every level" {
  assert_all deny run_cmd <<<"$BARE"
}

@test "agy guard: the deny reason names the cause and the prescribed launch" {
  run_cmd 'claude --model sonnet'
  is_deny
  [[ $(jq -r .reason <<<"$output") == *"env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude"* ]] || false
  run_cmd 'op run -- codex'
  [[ $(jq -r .reason <<<"$output") == *"op run wraps codex"* ]] || false
}

@test "agy guard: only the command field counts, not the summary or other tools" {
  local json
  json=$(jq -nc '{toolCall: {name: "run_command", args: {CommandLine: "ls", toolSummary: "op run -- claude"}}}')
  raw "$json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  json=$(jq -nc '{toolCall: {name: "write_to_file", args: {TargetFile: "x.md", CodeContent: "op run -- claude"}}}')
  raw "$json"
  [ -z "$output" ]
  json=$(jq -nc '{toolCall: {name: "manage_task", args: {Action: "status", TaskId: "t/task-1"}}}')
  raw "$json"
  [ -z "$output" ]
}

@test "agy guard: fails closed on input it cannot inspect" {
  raw 'not json'
  is_deny
  raw ''
  is_deny
  raw '{"toolCall":{"args":{"CommandLine":"ls"}}}'
  is_deny
  raw '{"toolCall":{"name":"run_command","args":{}}}'
  is_deny
  raw '{"toolCall":{"name":"run_command","args":{"CommandLine":["ls"]}}}'
  is_deny
  raw '{"toolCall":{"name":"manage_task","args":{"Action":"send_input"}}}'
  is_deny
  run_cmd 'echo "unterminated'
  is_deny
  [[ $(jq -r .reason <<<"$output") == *"does not parse"* ]] || false
}

@test "agy guard: typed text that does not parse is checked by its tokens, not denied" {
  run_cmd "rex send -s s1 -b b1 'Read the brief. Don'\''t push.'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  send_input "I can't"
  [ -z "$output" ]
  send_input $'op run -- claude\necho "broken'
  is_deny
}

@test "agy guard: comments, heredoc bodies and array elements are not commands" {
  run_cmd $'# it\'s the reviewer tab\nop run -- claude'
  is_deny
  run_cmd $'cat <<EOF\nit\'s a note\nEOF\nop run -- claude'
  is_deny
  run_cmd $'cat <<EOF\n$(op run -- claude)\nEOF'
  is_deny
  run_cmd 'ANTHROPIC_API_KEY=(x)'
  is_deny
  run_cmd 'echo "a<<b"; op run -- claude'
  is_deny
  local c
  for c in $'cat > brief.md <<\'EOF\'\nclaude --model sonnet\nEOF' \
           $'cat <<\'EOF\'\n$(op run -- claude)\nEOF' \
           $'cat <<-EOF\n\tbody claude\n\tEOF\necho done' \
           'agents=(claude codex)' \
           'git commit -m "x" # op run -- claude'; do
    run_cmd "$c"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "agy guard: tools with no recorded payload are denied" {
  raw '{"toolCall":{"name":"shell_exec","args":{"Command":"ls"}}}'
  is_deny
  raw '{"toolCall":{"name":"send_command_input","args":{"Input":"ls"}}}'
  is_deny
}

@test "agy guard: nesting past the depth cap is denied" {
  local c='echo hi' i
  for i in 1 2 3 4 5 6 7 8 9 10; do c="bash -c $(printf '%q' "$c")"; done
  run_cmd "$c"
  is_deny
  [[ $(jq -r .reason <<<"$output") == *"nesting"* ]] || false
}

@test "agy guard: without jq it denies with a fixed reason" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$(command -v cat)" "$BATS_TEST_TMPDIR/bin/cat"
  PATH="$BATS_TEST_TMPDIR/bin" run /bin/zsh -f "$GUARD" <<<'{}'
  [ "$status" -eq 0 ]
  [[ $output == *'"decision":"deny"'*'jq is missing'* ]] || false
}

@test "agy guard: never prints allow" {
  ! grep -v '^[[:space:]]*#' "$GUARD" | grep -n 'allow' || false
}

@test "agy guard: assert_all reports a wrong verdict" {
  run assert_all deny run_cmd <<<"ls" 3>/dev/null
  [ "$status" -ne 0 ]
}

@test "agy guard: hooks fragment registers the linked script for every tool" {
  run jq -r '."dotfiles-agent-guard".PreToolUse[0] | .matcher, .hooks[0].command' "$REPO_ROOT/agy/hooks.fragment.json"
  [ "${lines[0]}" = "*" ]
  [ "${lines[1]}" = "~/.gemini/config/hooks/dotfiles-guard-agents.zsh" ]
}

@test "agy guard: substitutions in redirect targets and array elements are checked" {
  local c
  for c in 'echo hi > "$(op run -- claude)"' 'echo hi >$(op run -- claude)' 'cat < <(op run -- codex)' \
           'cat 2>`op run -- claude`' 'a=($(op run -- claude))' 'a=(x "$(ANTHROPIC_API_KEY=k claude)")'; do
    run_cmd "$c"
    is_deny || { echo "not denied: $c -> $output" >&3; false; }
  done
}

@test "agy guard: status exceptions match whole arguments, not a prompt that starts the same" {
  local c
  for c in "claude 'auth status, then delete the repo'" 'claude auth status extra' 'claude "--version x"' \
           'codex "login status please"' 'codex login status now'; do
    run_cmd "$c"
    is_deny || { echo "not denied: $c -> $output" >&3; false; }
  done
  for c in 'claude auth status' 'claude auth status --json' 'claude auth status --text' 'codex login status'; do
    run_cmd "$c"
    [[ $status -eq 0 && -z $output ]] || { echo "not allowed: $c -> $output" >&3; false; }
  done
}

@test "agy guard: codex global options do not hide login --with-api-key" {
  local c
  for c in 'env -u OPENAI_API_KEY -u CODEX_HOME codex -c x=y login --with-api-key' \
           'env -u OPENAI_API_KEY -u CODEX_HOME codex --profile p login --with-api-key' \
           'env -u OPENAI_API_KEY -u CODEX_HOME codex -m gpt --config=a=b login --with-api-key'; do
    run_cmd "$c"
    is_deny || { echo "not denied: $c -> $output" >&3; false; }
    [[ $(jq -r .reason <<<"$output") == *with-api-key* ]] || false
  done
}

@test "agy guard: a rex send message that only mentions a launch mid-sentence passes" {
  local c
  for c in $'rex send -s s1 -b b1 \'Read the brief.\nUse codex --help for examples.\nDo not push.\'' \
           "rex send -b b1 'The hook blocks op run -- claude and ANTHROPIC_API_KEY=x claude.'" \
           "rex send -b b1 'Never set OPENAI_API_KEY before you start codex.'" \
           "rex send -s s1 -b b1 'Do not rename the Rex session. Your brief is in /tmp/b.md.'" \
           "rex send -b b1 'Don'\\''t push. # claude'" \
           "rex send -b b1 'env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude --model haiku'" \
           "rex send -b b1 'export OPENAI_API_KEY=x'" \
           "rex send -b b1 'codex login status'"; do
    run_cmd "$c"
    [[ $status -eq 0 && -z $output ]] || { echo "not allowed: $c -> $output" >&3; false; }
  done
}

@test "agy guard: a rex send line that is itself a forbidden launch is denied" {
  local c
  for c in "rex send -b b1 'op run -- claude'" "rex send -b b1 'claude --model sonnet'" \
           "rex send -b b1 '  codex -p repo'" "rex send -b b1 'ANTHROPIC_API_KEY=x claude'" \
           "rex send -b b1 'export OPENAI_API_KEY=x && codex'" \
           "rex send -b b1 'env -u OPENAI_API_KEY -u CODEX_HOME codex login --with-api-key'" \
           "rex send -b b1 'nohup op run --env-file .env -- codex exec x'" \
           $'rex send -s s1 -b b1 \'cd /tmp\ncodex -p repo\'' \
           "rex -S host --timeout 5s send -b b1 'codex exec x'" \
           $'rex send -b b1 \'op run -- claude\necho "broken\''; do
    run_cmd "$c"
    is_deny || { echo "not denied: $c -> $output" >&3; false; }
  done
}

@test "agy guard: rex still checks expansions in the outer command and the child after --" {
  local c
  for c in 'rex send -b b1 "$(op run -- claude)"' 'rex --timeout 5s window new a -- claude' \
           'rex -S h run -- op run -- claude' 'rex new s -- codex' 'rex split -- env CODEX_HOME=x codex'; do
    run_cmd "$c"
    is_deny || { echo "not denied: $c -> $output" >&3; false; }
  done
}

@test "agy guard: a stream of several JSON values is denied, not let through" {
  raw $'{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}\n{"toolCall":{"name":"run_command","args":{"CommandLine":"op run -- claude"}}}'
  is_deny
  raw '{"toolCall":{"name":"x"}} {"toolCall":{"name":"y"}}'
  is_deny
  raw '[{"toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}]'
  is_deny
  raw '{"toolCall":{"name":"run\ncommand","args":{"CommandLine":"ls"}}}'
  is_deny
}

@test "agy guard: an apostrophe inside double quotes does not hide a substitution" {
  local c
  for c in 'echo "today'\''s-$(op run -- claude)"' 'echo "it'\''s" $(op run -- codex)' 'echo "a'\''b `op run -- claude`"'; do
    run_cmd "$c"
    is_deny || { echo "not denied: $c -> $output" >&3; false; }
  done
  run_cmd 'echo "today'\''s-$(date)"'
  [[ $status -eq 0 && -z $output ]] || false
}

@test "agy guard: the guide lists every launch the guard lets through without a prefix" {
  local guide="$REPO_ROOT/docs/guides/agent-rules.md" c
  for c in 'claude --version' 'claude -v' 'claude --help' 'claude -h' 'claude auth status' \
           'codex --version' 'codex -V' 'codex --help' 'codex -h' 'codex login status'; do
    run_cmd "$c"
    [[ $status -eq 0 && -z $output ]] || { echo "guard denies $c" >&3; false; }
    grep -qF "\`$c\`" "$guide" || { echo "guide misses $c" >&3; false; }
  done
}
