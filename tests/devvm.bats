#!/usr/bin/env bats
# bin/devvm against stub aws, ssh and open. The aws stub keeps the VM state and the SSO sign-in
# in files under BATS_TEST_TMPDIR.

load helpers
bats_require_minimum_version 1.5.0

setup() {
  fake_home
  STUBS="$BATS_TEST_TMPDIR/stubs"
  export STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$STUBS" "$STATE"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : >"$STUB_LOG"
  echo stopped >"$STATE/vm"
  export DEVVM_POLL=0
  unset DEVVM_HOST DEVVM_PROFILE DEVVM_REGION DEVVM_SIGNIN_URL DEVVM_WAIT DEVVM_READY
  stub aws <<'EOF'
args=" $* "
log() { echo "aws $*" >>"$STUB_LOG"; }
case $args in
  *" configure get region "*) [[ -n ${STUB_REGION:-} ]] && echo "$STUB_REGION" && exit 0; exit 1 ;;
  *" sts get-caller-identity "*) [[ -f $STATE/signed ]] && exit 0; exit 255 ;;
  *" sso login "*) log "$@"; [[ -n ${STUB_LOGIN_FAIL:-} ]] && exit 1; touch "$STATE/signed" ;;
  *" ec2 describe-instances "*)
    [[ -n ${STUB_EC2_FAIL:-} ]] && exit 1
    cat "$STATE/vm" ;;
  *" ec2 start-instances "*) log "$@"; echo pending >"$STATE/vm" ;;
  *" ec2 wait instance-running "*) echo running >"$STATE/vm" ;;
  *" ec2 wait instance-stopped "*) log "$@"; echo stopped >"$STATE/vm" ;;
  *" ec2 stop-instances "*) log "$@"; echo stopping >"$STATE/vm" ;;
  *" ssm describe-instance-information "*)
    [[ -n ${STUB_SSM_FAIL:-} ]] && exit 1
    n=$(( $(cat "$STATE/pings" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$STATE/pings"
    if [[ $(cat "$STATE/vm") == running && $n -gt ${STUB_PING_AFTER:-0} ]]; then echo Online; else echo None; fi ;;
  *" ssm start-session "*) log "$@" ;;
  *) log "UNEXPECTED $*"; exit 99 ;;
esac
EOF
  stub ssh <<'EOF'
if [[ $1 == -G ]]; then
  override=""
  shift
  while (( $# )); do
    case $1 in
      -o)
        [[ ${2:-} == HostName=* ]] && override=${2#HostName=}
        shift 2 ;;
      -oHostName=*)
        override=${1#-oHostName=}
        shift ;;
      *) shift ;;
    esac
  done
  echo "user ubuntu"
  echo "hostname ${override:-${STUB_HOSTNAME-i-0123456789abcdef0}}"
  exit 0
fi
echo "ssh $* ready=${DEVVM_READY:-}" >>"$STUB_LOG"
EOF
  stub open <<'EOF'
echo "open $*" >>"$STUB_LOG"
EOF
}

stub() {
  { echo '#!/bin/bash'; cat; } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

devvm() {
  PATH="$STUBS:/usr/bin:/bin" run "$REPO_ROOT/bin/devvm" "$@" </dev/null
}

@test "devvm: signs in, starts a stopped VM, waits for SSM and connects" {
  export STUB_REGION=eu-west-1 STUB_PING_AFTER=2
  devvm
  [ "$status" -eq 0 ]
  expected="aws sso login --profile dev-vm
aws --profile dev-vm --region eu-west-1 ec2 start-instances --instance-ids i-0123456789abcdef0
ssh dev-vm ready=i-0123456789abcdef0"
  [ "$(cat "$STUB_LOG")" = "$expected" ]
  [[ $output == *"waiting for the SSM agent"* ]] || false
}

@test "devvm: a signed-in session and a running VM go straight to ssh with its arguments" {
  touch "$STATE/signed"; echo running >"$STATE/vm"
  DEVVM_REGION=us-east-1 devvm connect -L 3000:localhost:3000
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "ssh -L 3000:localhost:3000 dev-vm ready=i-0123456789abcdef0" ]
}

@test "devvm: an ssh option as the first argument means connect" {
  touch "$STATE/signed"; echo running >"$STATE/vm"
  DEVVM_REGION=us-east-1 devvm -A
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "ssh -A dev-vm ready=i-0123456789abcdef0" ]
}

@test "devvm: connect resolves ssh -G with caller options and ties DEVVM_READY to the resolved instance" {
  touch "$STATE/signed"
  DEVVM_REGION=us-east-1 devvm connect -o HostName=i-99999999999999999
  [ "$status" -eq 0 ]
  grep -q 'ec2 start-instances --instance-ids i-99999999999999999' "$STUB_LOG"
  grep -qx 'ssh -o HostName=i-99999999999999999 dev-vm ready=i-99999999999999999' "$STUB_LOG"

  : >"$STUB_LOG"
  echo stopped >"$STATE/vm"
  DEVVM_REGION=us-east-1 DEVVM_READY=i-other devvm proxy i-0123456789abcdef0 22
  [ "$status" -eq 0 ]
  grep -q 'ec2 start-instances --instance-ids i-0123456789abcdef0' "$STUB_LOG"
}

@test "devvm: a stopping VM is waited for, then started" {
  touch "$STATE/signed"; echo stopping >"$STATE/vm"
  DEVVM_REGION=us-east-1 devvm start
  [ "$status" -eq 0 ]
  run cut -d' ' -f7-8 "$STUB_LOG"
  [ "$output" = $'wait instance-stopped\nstart-instances --instance-ids' ]
}

@test "devvm: a terminated VM fails without starting anything" {
  touch "$STATE/signed"; echo terminated >"$STATE/vm"
  DEVVM_REGION=us-east-1 devvm
  [ "$status" -eq 1 ]
  [[ $output == *"is terminated, cannot connect"* ]] || false
  [ ! -s "$STUB_LOG" ]
}

@test "devvm: gives up when the SSM agent stays offline" {
  touch "$STATE/signed"; echo running >"$STATE/vm"
  DEVVM_REGION=us-east-1 DEVVM_WAIT=0 STUB_PING_AFTER=99 devvm
  [ "$status" -eq 1 ]
  [[ $output == *"SSM agent is not online after 0s"* ]] || false
}

@test "devvm: stop signs in and stops the VM" {
  DEVVM_REGION=us-east-1 devvm stop
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/vm")" = stopping ]
  [[ $(tail -1 "$STUB_LOG") == *"ec2 stop-instances --instance-ids i-0123456789abcdef0"* ]] || false
}

@test "devvm: status reports the sign-in, the VM state and SSM" {
  touch "$STATE/signed"; echo running >"$STATE/vm"
  DEVVM_REGION=us-east-1 devvm status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "signed in: yes (profile dev-vm)" ]
  [ "${lines[1]}" = "i-0123456789abcdef0: running, ssm: Online" ]
}

@test "devvm: status fails when signed out" {
  DEVVM_REGION=us-east-1 devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"signed in: no, run devvm login"* ]] || false
}

@test "devvm: a failed sign-in points at the work Google account" {
  DEVVM_REGION=us-east-1 STUB_LOGIN_FAIL=1 devvm login
  [ "$status" -eq 1 ]
  [[ $output == *"work Google account"* ]] || false
  [[ $output == *"Amazon tile"* ]] || false
}

@test "devvm: DEVVM_SIGNIN_URL is opened before aws sso login" {
  DEVVM_REGION=us-east-1 DEVVM_SIGNIN_URL=https://idp.example.com/app devvm login
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = $'open https://idp.example.com/app\naws sso login --profile dev-vm' ]
}

@test "devvm: proxy signs in, starts the VM and keeps stdout for the ssh channel" {
  export STUB_REGION=us-east-1
  PATH="$STUBS:/usr/bin:/bin" run --separate-stderr "$REPO_ROOT/bin/devvm" proxy i-0123456789abcdef0 22 </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ $(tail -1 "$STUB_LOG") == *"ssm start-session --target i-0123456789abcdef0 --document-name AWS-StartSSHSession --parameters portNumber=22 --profile dev-vm --region us-east-1" ]] || false
  grep -q 'ec2 start-instances' "$STUB_LOG"
}

@test "devvm: status fails when EC2 or SSM lookups fail" {
  touch "$STATE/signed"; echo running >"$STATE/vm"
  DEVVM_REGION=us-east-1 STUB_EC2_FAIL=1 devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"failed to read EC2 state"* ]] || false

  DEVVM_REGION=us-east-1 STUB_SSM_FAIL=1 devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"failed to read SSM status"* ]] || false
}

@test "devvm: proxy skips the checks under matching DEVVM_READY" {
  DEVVM_REGION=us-east-1 DEVVM_READY=i-0123456789abcdef0 devvm proxy i-0123456789abcdef0 22
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 1 ]
  grep -q 'ssm start-session' "$STUB_LOG"
}

@test "devvm: settings come from ~/.config/devvm/config, preserve trailing '=' and the environment wins" {
  mkdir -p "$XDG_CONFIG_HOME/devvm"
  printf 'DEVVM_HOST=box\nDEVVM_PROFILE="work"\nDEVVM_REGION=ap-south-1\nDEVVM_SIGNIN_URL=https://idp.example.com/?t=abc=\n' >"$XDG_CONFIG_HOME/devvm/config"
  touch "$STATE/signed"; echo running >"$STATE/vm"
  export DEVVM_PROFILE=other
  devvm
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "ssh box ready=i-0123456789abcdef0" ]
  devvm status
  [ "${lines[0]}" = "signed in: yes (profile other)" ]

  : >"$STUB_LOG"
  DEVVM_REGION=ap-south-1 devvm login
  [ "$status" -eq 0 ]
  [[ $(head -n 1 "$STUB_LOG") == "open https://idp.example.com/?t=abc=" ]] || false
}

@test "devvm: non-numeric DEVVM_WAIT or missing aws CLI fails clearly" {
  DEVVM_REGION=us-east-1 DEVVM_WAIT=abc devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"DEVVM_WAIT must be a non-negative integer"* ]] || false

  rm "$STUBS/aws"
  devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"aws CLI not found on PATH"* ]] || false
}

@test "devvm: an ssh host without an instance ID fails" {
  DEVVM_REGION=us-east-1 STUB_HOSTNAME=dev.example.com devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"no instance ID as HostName (got 'dev.example.com')"* ]] || false
}

@test "devvm: no region fails with a hint" {
  devvm status
  [ "$status" -eq 1 ]
  [[ $output == *"set DEVVM_REGION"* ]] || false
}

@test "devvm: --help works without AWS config, an unknown command exits 2" {
  devvm --help
  [ "$status" -eq 0 ]
  [[ ${lines[1]} == "Usage: devvm [connect]"* ]] || false
  devvm reboot
  [ "$status" -eq 2 ]
}
