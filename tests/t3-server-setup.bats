#!/usr/bin/env bats
# bin/t3-server-setup against a hermetic PATH with stub tailscale, loginctl, systemctl, ps, sudo, curl, t3, id, gh and toolchain binaries.

load helpers
bats_require_minimum_version 1.5.0

setup() {
  fake_home
  STUBS="$BATS_TEST_TMPDIR/stubs"
  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  STATE="$BATS_TEST_TMPDIR/state"
  STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$STUBS" "$TEST_BIN" "$STATE"
  : >"$STUB_LOG"

  local tool path
  for tool in jq sed grep cat mktemp chmod mv rm mkdir uname tr wc sh bash env head tail awk python3; do
    path=$(command -v "$tool" || true)
    if [[ -z $path ]]; then
      echo "missing required host tool for test harness: $tool" >&2
      return 1
    fi
    ln -sf "$path" "$TEST_BIN/$tool"
  done

  export T3_SETUP_OS=Linux
  export T3_SETUP_USER=alice
  export T3_SETUP_INSTALL_URL=https://t3.example.test/install.sh
  export T3_SETUP_TAILSCALE_APP="$BATS_TEST_TMPDIR/TailscaleApp"
  unset T3CODE_HOME ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CODEX_API_KEY CODEX_HOME

  cat >"$STATE/ts-status.json" <<'JSON'
{
  "BackendState": "Running",
  "MagicDNSSuffix": "tailnet.ts.net",
  "CurrentTailnet": { "MagicDNSEnabled": true },
  "Self": {
    "CapMap": { "https": {} },
    "KeyExpiry": "0001-01-01T00:00:00Z",
    "Tags": []
  }
}
JSON
  echo '{}' >"$STATE/ts-serve.json"
  echo '0' >"$STATE/ts-serve-fail"
  echo '{"OperatorUser":"alice"}' >"$STATE/ts-prefs.json"
  echo 'Linger=yes' >"$STATE/linger"
  echo '{"service":{"supported":true,"installed":true,"installedVersion":"0.1.13"},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  echo '0' >"$STATE/t3-status-fail"
  echo '0' >"$STATE/sudo-ok"
  echo '1000' >"$STATE/uid"
  echo '/usr/local/bin/t3 /usr/local/bin/t3 serve' >"$STATE/ps-cmd"
  echo '1' >"$STATE/ps-ppid"
  echo '1' >"$STATE/systemd-active"
  echo "$$" >"$STATE/systemd-pid"

  mkdir -p "$HOME/.t3/userdata"
  printf '{"pid":%d,"host":"0.0.0.0","origin":"http://127.0.0.1:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"

  stub id <<'EOF'
case "${1:-}" in
  -u) cat "$STATE/uid" ;;
  -un) echo "${T3_SETUP_USER:-alice}" ;;
  *) echo "uid=$(cat "$STATE/uid")(${T3_SETUP_USER:-alice})" ;;
esac
EOF

  stub ps <<'EOF'
if [[ $* == *"ppid="* ]]; then
  cat "$STATE/ps-ppid"
else
  cat "$STATE/ps-cmd"
fi
EOF

  stub systemctl <<'EOF'
if [[ $* == *"list-units"* ]]; then
  if [[ $(cat "$STATE/systemd-active") == 1 ]]; then
    echo "t3-code.service loaded active running T3 Code"
  fi
elif [[ $* == *"show -p MainPID"* ]]; then
  cat "$STATE/systemd-pid"
fi
EOF

  stub tailscale <<'EOF'
case "$1 ${2:-}" in
  "status --json") cat "$STATE/ts-status.json" ;;
  "serve status")
    if [[ $(cat "$STATE/ts-serve-fail") == 1 ]]; then exit 1; fi
    cat "$STATE/ts-serve.json" ;;
  "debug prefs") cat "$STATE/ts-prefs.json" ;;
  "set "*)
    echo "tailscale $*" >>"$STUB_LOG"
    echo "{\"OperatorUser\":\"${2#--operator=}\"}" >"$STATE/ts-prefs.json" ;;
  *) echo "tailscale $*" >>"$STUB_LOG" ;;
esac
EOF

  stub loginctl <<'EOF'
case "$1" in
  show-user) cat "$STATE/linger" ;;
  enable-linger)
    echo "loginctl $*" >>"$STUB_LOG"
    echo 'Linger=yes' >"$STATE/linger" ;;
  *) echo "loginctl $*" >>"$STUB_LOG" ;;
esac
EOF

  stub sudo <<'EOF'
if [[ ${1:-} == -n ]]; then
  shift
  if [[ $(cat "$STATE/sudo-ok") != 1 ]]; then exit 1; fi
  echo "sudo -n $*" >>"$STUB_LOG"
  exec "$@"
fi
echo "sudo $*" >>"$STUB_LOG"
exec "$@"
EOF

  stub curl <<'EOF'
echo "curl $*" >>"$STUB_LOG"
out=""
while (( $# )); do
  if [[ $1 == -o ]]; then out=$2; shift 2; continue; fi
  shift
done
if [[ ${STUB_EMPTY_INSTALLER:-0} == 1 ]]; then
  : >"$out"
  exit 0
fi
cat >"$out" <<'SH'
#!/bin/sh
mkdir -p "$HOME/.t3/bin"
cat >"$HOME/.t3/bin/t3" <<'T3EOF'
#!/bin/bash
if [[ $1 == --version ]]; then echo "0.1.13"; exit 0; fi
if [[ $1 == status ]]; then
  if [[ $(cat "$STATE/t3-status-fail") == 1 ]]; then exit 1; fi
  cat "$STATE/t3-status.json"
  exit 0
fi
echo "t3 $*" >>"$STUB_LOG"
if [[ $1 == service && $2 == install ]]; then
  echo '{"service":{"supported":true,"installed":true,"installedVersion":"0.1.13"},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
fi
T3EOF
chmod +x "$HOME/.t3/bin/t3"
SH
EOF

  stub t3 <<'EOF'
if [[ $1 == --version ]]; then echo "0.1.13"; exit 0; fi
if [[ $1 == status ]]; then
  if [[ $(cat "$STATE/t3-status-fail") == 1 ]]; then exit 1; fi
  cat "$STATE/t3-status.json"
  exit 0
fi
echo "t3 $*" >>"$STUB_LOG"
if [[ $1 == service && $2 == install ]]; then
  echo '{"service":{"supported":true,"installed":true,"installedVersion":"0.1.13"},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
fi
EOF

  stub gh <<'EOF'
exit 0
EOF
  for tool in claude codex git jj sccache cargo-nextest mold; do
    stub "$tool" <<'EOF'
exit 0
EOF
  done
}

stub() {
  { echo '#!/bin/bash'; cat; } >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

run_setup() {
  PATH="$STUBS:$TEST_BIN" STATE="$STATE" STUB_LOG="$STUB_LOG" \
    run "$REPO_ROOT/bin/t3-server-setup" "$@" </dev/null
}

run_setup_pty() {
  local pty_stdout=$1
  shift
  PATH="$STUBS:$TEST_BIN" STATE="$STATE" STUB_LOG="$STUB_LOG" \
    run "$TEST_BIN/python3" -c '
import os, pty, select, subprocess, sys

pty_stdout = sys.argv[1] == "1"
cmd = sys.argv[2:]
master_in, slave_in = pty.openpty()
if pty_stdout:
    stdout_fd = slave_in
    out_r = out_w = None
else:
    out_r, out_w = os.pipe()
    stdout_fd = out_w

proc = subprocess.Popen(
    cmd,
    stdin=slave_in,
    stdout=stdout_fd,
    stderr=subprocess.STDOUT if pty_stdout else subprocess.PIPE,
    close_fds=True,
)
os.close(slave_in)
if out_w is not None:
    os.close(out_w)

chunks = []
watch_fds = [master_in] + ([out_r] if out_r is not None else [])
err_fd = proc.stderr.fileno() if proc.stderr is not None else None
if err_fd is not None:
    watch_fds.append(err_fd)

while watch_fds:
    r, _, _ = select.select(watch_fds, [], [], 5.0)
    if not r and proc.poll() is not None:
        break
    for fd in list(r):
        try:
            data = os.read(fd, 4096)
        except OSError:
            data = b""
        if not data:
            watch_fds.remove(fd)
            continue
        chunks.append(data)

rc = proc.wait()
os.close(master_in)
if out_r is not None:
    os.close(out_r)
if proc.stderr is not None:
    proc.stderr.close()
sys.stdout.buffer.write(b"".join(chunks))
sys.exit(rc)
' "$pty_stdout" "$REPO_ROOT/bin/t3-server-setup" "$@"
}

@test "t3-server-setup: --help works, port normalization handles boundaries and leading zeroes, invalid flags exit 2" {
  run_setup --help
  [ "$status" -eq 0 ]
  [[ $output == *"Usage: t3-server-setup"* ]] || false

  run_setup --port=0443 --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Serve port 443 is free"* ]] || false

  run_setup --port 65535 --dry-run
  [ "$status" -eq 0 ]
  [[ $output == *"Serve port 65535 is free"* ]] || false

  for bad in "--unknown" "--port 0" "--port 0000" "--port 65536" "--port 70000" "--port 99999999999999999999" "--port abc" "--check --pair" "--check --protect"; do
    # shellcheck disable=SC2086
    run_setup $bad
    [ "$status" -eq 2 ]
  done
}

@test "t3-server-setup: Linux fresh bootstrap installs t3, sets operator and linger, installs service" {
  rm -f "$STUBS/t3" "$HOME/.t3/userdata/server-runtime.json"
  echo '{}' >"$STATE/ts-prefs.json"
  echo 'Linger=no' >"$STATE/linger"
  echo '{"service":{"supported":true,"installed":false,"installedVersion":null},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  echo '1' >"$STATE/sudo-ok"

  run_setup
  [ "$status" -eq 0 ]
  grep -q 'sudo -n .*/tailscale set --operator=alice' "$STUB_LOG"
  grep -q 'sudo -n loginctl enable-linger alice' "$STUB_LOG"
  grep -q '^curl --proto =https --tlsv1.2 -fsSL ' "$STUB_LOG"
  grep -qx 't3 service install' "$STUB_LOG"
  [[ $output == *"run directly in your terminal (once per client): t3 pair --base-dir $HOME/.t3 --tailscale"* ]] || false
}

@test "t3-server-setup: UID 0 skips sudo and interactive PTY uses plain sudo" {
  echo '0' >"$STATE/uid"
  echo '{}' >"$STATE/ts-prefs.json"
  echo 'Linger=no' >"$STATE/linger"

  run_setup
  [ "$status" -eq 0 ]
  ! grep -q '^sudo' "$STUB_LOG" || false
  grep -q 'tailscale set --operator=alice' "$STUB_LOG"
  grep -q 'loginctl enable-linger alice' "$STUB_LOG"

  : >"$STUB_LOG"
  echo '1000' >"$STATE/uid"
  echo '{}' >"$STATE/ts-prefs.json"
  echo 'Linger=no' >"$STATE/linger"
  run_setup_pty 1
  [ "$status" -eq 0 ]
  grep -q '^sudo .*/tailscale set --operator=alice' "$STUB_LOG"
  ! grep -q '^sudo -n ' "$STUB_LOG" || false
}

@test "t3-server-setup: Linux re-run is idempotent and ignores unrelated node/ubuntu recycled PIDs" {
  run_setup
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
  [[ $output == *"t3 service already installed (0.1.13) and running (http://127.0.0.1:3773)"* ]] || false

  echo '{"service":{"supported":true,"installed":true,"installedVersion":"0.1.13","otherBaseDir":"/alt/.t3"},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  for fake_proc in "/bin/sleep 60" "/srv/ubuntu/worker --flag" "/usr/bin/node_exporter" "electron /tmp/other.js"; do
    printf '%s\n' "$fake_proc" >"$STATE/ps-cmd"
    run_setup
    [ "$status" -eq 0 ]
    [[ $output == *"another T3 service is installed for base dir: /alt/.t3"* ]] || false
    [[ $output == *"t3 service already installed (0.1.13), not currently running"* ]] || false
  done
}

@test "t3-server-setup: --dry-run, --no-install, and empty installer behavior" {
  rm -f "$STUBS/t3" "$HOME/.t3/userdata/server-runtime.json"
  echo '{}' >"$STATE/ts-prefs.json"
  echo 'Linger=no' >"$STATE/linger"
  echo '{"service":{"supported":true,"installed":false,"installedVersion":null},"lan":{"enabled":false}}' >"$STATE/t3-status.json"

  run_setup --dry-run --protect --pair
  [ "$status" -eq 0 ]
  [ ! -s "$STUB_LOG" ]
  [ ! -e "$HOME/.t3/bin/t3" ]
  [[ $output == *"+ sudo "* ]] || false
  [[ $output == *"+ curl --proto '=https' --tlsv1.2 -fsSL "* ]] || false
  [[ $output == *"+ t3 service install"* ]] || false
  [[ $output == *"+ t3 service protect"* ]] || false
  [[ $output == *"+ t3 pair --base-dir $HOME/.t3 --tailscale"* ]] || false

  echo '{"OperatorUser":"alice"}' >"$STATE/ts-prefs.json"
  echo 'Linger=yes' >"$STATE/linger"
  run_setup --no-install
  [ "$status" -eq 1 ]
  [[ $output == *"--no-install set"* ]] || false

  STUB_EMPTY_INSTALLER=1 run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"downloaded t3 installer"* ]] || false
}

@test "t3-server-setup: --check verifies prerequisites, unit MainPID correlation, stale/desktop/foreground runtimes without mutating" {
  rm -f "$STUBS/t3" "$HOME/.t3/userdata/server-runtime.json"
  echo '{}' >"$STATE/ts-prefs.json"
  echo 'Linger=no' >"$STATE/linger"

  run_setup --check
  [ "$status" -eq 1 ]
  [ ! -s "$STUB_LOG" ]
  [[ $output == *"fail Tailscale operator is not alice"* ]] || false
  [[ $output == *"fail systemd linger disabled for alice"* ]] || false
  [[ $output == *"fail t3 CLI is not installed"* ]] || false

  stub t3 <<'EOF'
if [[ $1 == --version ]]; then echo "0.1.13"; exit 0; fi
if [[ $1 == status ]]; then
  if [[ $(cat "$STATE/t3-status-fail") == 1 ]]; then exit 1; fi
  cat "$STATE/t3-status.json"
  exit 0
fi
echo "t3 $*" >>"$STUB_LOG"
EOF
  echo '{"OperatorUser":"alice"}' >"$STATE/ts-prefs.json"
  echo 'Linger=yes' >"$STATE/linger"

  # Installed service with no runtime fails --check.
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"installed (0.1.13) but not running"* ]] || false

  # Installed service whose unit is inactive OR whose MainPID does not match runtime PID fails --check.
  printf '{"pid":%d,"host":"0.0.0.0","origin":"http://127.0.0.1:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"
  echo '0' >"$STATE/systemd-active"
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"but not active"* ]] || false
  echo '1' >"$STATE/systemd-active"

  # Service unit MainPID matching launcher parent PID passes --check; unrelated PID fails --check.
  echo '49704' >"$STATE/systemd-pid"
  echo '49704' >"$STATE/ps-ppid"
  run_setup --check
  [ "$status" -eq 0 ]
  [[ $output == *"all prerequisite checks passed"* ]] || false
  echo '1' >"$STATE/ps-ppid"

  echo '999999' >"$STATE/systemd-pid"
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"but not active"* ]] || false
  echo "$$" >"$STATE/systemd-pid"

  # Recycled non-T3 PID fails --check.
  echo '/srv/ubuntu/worker --serve' >"$STATE/ps-cmd"
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"installed (0.1.13) but not running"* ]] || false
  echo '/usr/local/bin/t3 /usr/local/bin/t3 serve' >"$STATE/ps-cmd"

  # Unsupported background service and uninstalled service fail --check; t3 status failure records failure.
  echo '{"service":{"supported":false,"installed":false,"installedVersion":null},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  rm -f "$HOME/.t3/userdata/server-runtime.json"
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"not supported on this host"* ]] || false

  echo '{"service":{"supported":true,"installed":false,"installedVersion":null},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"service is not installed"* ]] || false

  echo '1' >"$STATE/t3-status-fail"
  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"fail t3 status --json failed"* ]] || false
  echo '0' >"$STATE/t3-status-fail"

  # Active foreground server, running desktop app, and active installed service pass --check.
  printf '{"pid":%d,"host":"0.0.0.0","origin":"http://127.0.0.1:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"
  run_setup --check
  [ "$status" -eq 0 ]
  [[ $output == *"T3 server is already running"* ]] || false
  [[ $output == *"all prerequisite checks passed"* ]] || false

  : >"$HOME/.t3/userdata/desktop-settings.json"
  echo '/Applications/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)' >"$STATE/ps-cmd"
  run_setup --check
  [ "$status" -eq 0 ]
  [[ $output == *"owned by a running T3 desktop app"* ]] || false

  rm -f "$HOME/.t3/userdata/desktop-settings.json"
  echo '/usr/local/bin/t3 /usr/local/bin/t3 serve' >"$STATE/ps-cmd"
  echo '{"service":{"supported":true,"installed":true,"installedVersion":"0.1.13"},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  run_setup --check
  [ "$status" -eq 0 ]
  [[ $output == *"all prerequisite checks passed"* ]] || false
}

@test "t3-server-setup: rejects broken Tailscale baseline, invalid Serve output, Funnel, bind mismatches and collisions without reset" {
  echo '{"BackendState":"Stopped","MagicDNSSuffix":"x","CurrentTailnet":{"MagicDNSEnabled":true},"Self":{"CapMap":{"https":{}}}}' >"$STATE/ts-status.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"BackendState is 'Stopped'"* ]] || false

  echo '{"BackendState":"Running","MagicDNSSuffix":"tailnet.ts.net","CurrentTailnet":{"MagicDNSEnabled":false},"Self":{"CapMap":{"https":{}}}}' >"$STATE/ts-status.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"MagicDNS is disabled"* ]] || false

  echo '{"BackendState":"Running","MagicDNSSuffix":"","CurrentTailnet":{"MagicDNSEnabled":true},"Self":{"CapMap":{"https":{}}}}' >"$STATE/ts-status.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"MagicDNS is disabled"* ]] || false

  echo '{"BackendState":"Running","MagicDNSSuffix":"tailnet.ts.net","CurrentTailnet":{"MagicDNSEnabled":true},"Self":{"CapMap":{}}}' >"$STATE/ts-status.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"HTTPS Certificates disabled"* ]] || false

  cat >"$STATE/ts-status.json" <<'JSON'
{"BackendState":"Running","MagicDNSSuffix":"tailnet.ts.net","CurrentTailnet":{"MagicDNSEnabled":true},"Self":{"CapMap":{"https":{}}}}
JSON

  # Serve status error, empty output, and non-object JSON all fail closed.
  echo '1' >"$STATE/ts-serve-fail"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"tailscale serve status --json failed"* ]] || false
  echo '0' >"$STATE/ts-serve-fail"

  : >"$STATE/ts-serve.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"returned empty output"* ]] || false

  echo 'null' >"$STATE/ts-serve.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"non-object JSON"* ]] || false

  # IPv4 runtime accepts 127.0.0.1 with HTTPS=true and AllowFunnel=false, but rejects [::1].
  cat >"$STATE/ts-serve.json" <<'JSON'
{"AllowFunnel":{"vm.tailnet.ts.net:443":false},"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3773"}}}}}
JSON
  run_setup
  [ "$status" -eq 0 ]
  [[ $output == *"already proxies this T3 server (http://127.0.0.1:3773)"* ]] || false

  # Omitted host (as written by t3 service on Linux) accepts exact runtime origin host and rejects cross-family proxies.
  printf '{"pid":%d,"port":3773,"origin":"http://127.0.0.1:3773","serviceManaged":true}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"
  run_setup
  [ "$status" -eq 0 ]
  [[ $output == *"already proxies this T3 server (http://127.0.0.1:3773)"* ]] || false

  cat >"$STATE/ts-serve.json" <<'JSON'
{"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://[::1]:3773"}}}}}
JSON
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"--port 8443"* ]] || false

  cat >"$STATE/ts-serve.json" <<'JSON'
{"AllowFunnel":{"vm.tailnet.ts.net:443":false},"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3773"}}}}}
JSON

  # Explicit non-loopback recorded bind host rejects loopback proxy even when origin is loopback.
  printf '{"pid":%d,"host":"10.0.0.5","origin":"http://127.0.0.1:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"--port 8443"* ]] || false
  printf '{"pid":%d,"host":"0.0.0.0","origin":"http://127.0.0.1:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"

  cat >"$STATE/ts-serve.json" <<'JSON'
{"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://[::1]:3773"}}}}}
JSON
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"--port 8443"* ]] || false

  # IPv6-only bind accepts [::1] and rejects 127.0.0.1; dual-stack :: accepts both.
  printf '{"pid":%d,"host":"::1","origin":"http://[::1]:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"
  run_setup
  [ "$status" -eq 0 ]
  [[ $output == *"already proxies this T3 server (http://[::1]:3773)"* ]] || false

  cat >"$STATE/ts-serve.json" <<'JSON'
{"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3773"}}}}}
JSON
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"--port 8443"* ]] || false

  printf '{"pid":%d,"host":"::","origin":"http://127.0.0.1:3773"}\n' "$$" >"$HOME/.t3/userdata/server-runtime.json"
  for target in "http://127.0.0.1:3773" "http://[::1]:3773" "http://localhost:3773"; do
    cat >"$STATE/ts-serve.json" <<JSON
{"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"$target"}}}}}
JSON
    run_setup
    [ "$status" -eq 0 ]
    [[ $output == *"already proxies this T3 server ($target)"* ]] || false
  done

  # Missing HTTPS listener, wrong loopback port, Funnel (top-level or Foreground), non-root path, Foreground Web/TCP and TCP forward collide.
  for bad_serve in \
    '{"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3773"}}}}}' \
    '{"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8080"}}}}}' \
    '{"AllowFunnel":{"vm.tailnet.ts.net:443":true},"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3773"}}}}}' \
    '{"Foreground":{"sess1":{"AllowFunnel":{"vm.tailnet.ts.net:443":true},"TCP":{"443":{"HTTPS":true}}}}}' \
    '{"TCP":{"443":{"HTTPS":true}},"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/api":{"Proxy":"http://127.0.0.1:3773"}}}}}' \
    '{"Foreground":{"sess1":{"Web":{"vm.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}}}}}' \
    '{"Foreground":{"sess1":{"TCP":{"443":{"TCPForward":"127.0.0.1:8443"}}}}}' \
    '{"TCP":{"443":{"TCPForward":"127.0.0.1:8443"}}}'; do
    printf '%s\n' "$bad_serve" >"$STATE/ts-serve.json"
    run_setup
    [ "$status" -eq 1 ]
    [[ $output == *"--port 8443"* ]] || false
    ! grep -q 'reset' "$STUB_LOG" || false
  done

  echo '{"TCP":{"8443":{"TCPForward":"127.0.0.1:9000"}}}' >"$STATE/ts-serve.json"
  run_setup --port 8443
  [ "$status" -eq 1 ]
  [[ $output == *"--port 8444"* ]] || false
}

@test "t3-server-setup: non-interactive sudo fails cleanly with exact manual command" {
  echo '{}' >"$STATE/ts-prefs.json"
  echo '0' >"$STATE/sudo-ok"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"non-interactive sudo failed (run manually: sudo "* ]] || false
  [[ $output == *"set --operator=alice"* ]] || false
}

@test "t3-server-setup: --pair refuses piped stdin or piped stdout before mutations and runs with full PTY" {
  echo '{}' >"$STATE/ts-prefs.json"
  echo '1' >"$STATE/sudo-ok"

  run_setup --pair
  [ "$status" -eq 1 ]
  [[ $output == *"stdin and stdout are an interactive terminal"* ]] || false
  [ ! -s "$STUB_LOG" ]

  run_setup_pty 0 --pair
  [ "$status" -eq 1 ]
  [[ $output == *"stdin and stdout are an interactive terminal"* ]] || false
  [ ! -s "$STUB_LOG" ]

  echo '{"OperatorUser":"alice"}' >"$STATE/ts-prefs.json"
  run_setup_pty 1 --pair --port=8443 --base-dir="$HOME/.t3-alt"
  [ "$status" -eq 0 ]
  grep -qx "t3 pair --base-dir $HOME/.t3-alt --tailscale --tailscale-serve-port 8443" "$STUB_LOG"

  : >"$STUB_LOG"
  T3CODE_HOME="$HOME/.t3-env" run_setup_pty 1 --pair
  [ "$status" -eq 0 ]
  grep -qx "t3 pair --base-dir $HOME/.t3-env --tailscale" "$STUB_LOG"

  : >"$STUB_LOG"
  run_setup_pty 1 --pair
  [ "$status" -eq 0 ]
  grep -qx "t3 pair --base-dir $HOME/.t3 --tailscale" "$STUB_LOG"
}

@test "t3-server-setup: --check records missing tailscale and loginctl without aborting early" {
  rm -f "$STUBS/tailscale" "$STUBS/loginctl" "$HOME/.t3/userdata/server-runtime.json"
  echo '{"service":{"supported":true,"installed":true,"installedVersion":"0.1.13"},"lan":{"enabled":false}}' >"$STATE/t3-status.json"

  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"fail tailscale CLI not found on PATH"* ]] || false
  [[ $output == *"fail loginctl not found"* ]] || false
  [[ $output == *"== T3 Code CLI & service"* ]] || false
  [[ $output == *"check failed"* ]] || false
}

@test "t3-server-setup: --protect refuses non-TTY before mutations, runs on PTY for service, skips cleanly on foreground and Darwin" {
  echo '{}' >"$STATE/ts-prefs.json"

  run_setup --protect
  [ "$status" -eq 1 ]
  [[ $output == *"requires an interactive terminal"* ]] || false
  [ ! -s "$STUB_LOG" ]

  echo '{"OperatorUser":"alice"}' >"$STATE/ts-prefs.json"
  run_setup_pty 1 --protect
  [ "$status" -eq 0 ]
  grep -qx 't3 service protect' "$STUB_LOG"

  # Foreground runtime (no installed service) skips --protect both non-interactively and in --dry-run.
  : >"$STUB_LOG"
  echo '{"service":{"supported":true,"installed":false,"installedVersion":null},"lan":{"enabled":false}}' >"$STATE/t3-status.json"
  run_setup --protect
  [ "$status" -eq 0 ]
  [[ $output == *"skip --protect: no installed T3 background service"* ]] || false
  [ ! -s "$STUB_LOG" ]

  run_setup --dry-run --protect
  [ "$status" -eq 0 ]
  [[ $output == *"skip --protect: no installed T3 background service"* ]] || false
  [[ $output != *"+ t3 service protect"* ]] || false

  T3_SETUP_OS=Darwin run_setup --protect
  [ "$status" -eq 0 ]
  [[ $output == *"skip --protect: Linux systemd only"* ]] || false
  [ ! -s "$STUB_LOG" ]
}

@test "t3-server-setup: desktop-owned ~/.t3 blocks install even when quit or named via --base-dir" {
  export T3_SETUP_OS=Darwin
  mv "$STUBS/tailscale" "$T3_SETUP_TAILSCALE_APP"
  chmod +x "$T3_SETUP_TAILSCALE_APP"
  echo '{"service":{"supported":true,"installed":false,"installedVersion":null},"lan":{"enabled":false}}' >"$STATE/t3-status.json"

  # Running foreground server without desktop-settings.json skips install without desktop claim.
  run_setup
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/tailscale" ]
  [ ! -L "$HOME/.local/bin/tailscale" ]
  [[ $output == *"T3 server is already running"* ]] || false
  [ ! -s "$STUB_LOG" ]

  # Running desktop app skips install safely.
  : >"$HOME/.t3/userdata/desktop-settings.json"
  echo '/Applications/T3 Code (Beta).app/Contents/MacOS/T3 Code (Beta)' >"$STATE/ps-cmd"
  run_setup
  [ "$status" -eq 0 ]
  [[ $output == *"owned by a running T3 desktop app"* ]] || false
  [ ! -s "$STUB_LOG" ]

  # Quit desktop app refuses overwriting ~/.t3 on bootstrap, --check, and even explicit --base-dir="$HOME/.t3".
  rm -f "$HOME/.t3/userdata/server-runtime.json"
  run_setup
  [ "$status" -eq 1 ]
  [[ $output == *"desktop-owned (desktop-settings.json present) and the desktop app is not running"* ]] || false
  [[ $output == *"--base-dir"* ]] || false

  run_setup --base-dir="$HOME/.t3"
  [ "$status" -eq 1 ]
  [[ $output == *"desktop-owned (desktop-settings.json present) and the desktop app is not running"* ]] || false

  run_setup --check
  [ "$status" -eq 1 ]
  [[ $output == *"desktop-owned (desktop-settings.json present) and the desktop app is not running"* ]] || false

  mv "$T3_SETUP_TAILSCALE_APP" "$STUBS/tailscale"
  T3_SETUP_OS=Linux run_setup --base-dir="$HOME/.t3-srv"
  [ "$status" -eq 0 ]
  grep -qx "t3 service install --base-dir $HOME/.t3-srv" "$STUB_LOG"
}

@test "t3-server-setup: warns on forbidden API key env vars without printing values" {
  OPENAI_API_KEY=secret-value-xyz run_setup
  [ "$status" -eq 0 ]
  [[ $output == *"warn OPENAI_API_KEY is set"* ]] || false
  [[ $output != *"secret-value-xyz"* ]] || false
}
