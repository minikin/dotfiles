#!/usr/bin/env bats
# infra/compose.yaml: valid compose file, every published port bound to loopback.

load helpers

COMPOSE="$REPO_ROOT/infra/compose.yaml"

# published_ports: the list items under every `ports:` key, quotes stripped
published_ports() {
  awk '
    /^[[:space:]]*ports:[[:space:]]*$/ { inports = 1; next }
    inports && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); print; next }
    inports { inports = 0 }
  ' "$COMPOSE"
}

@test "infra: docker compose config is valid" {
  command -v docker >/dev/null || skip "docker not installed"
  # Fake HOME/DOCKER_CONFIG, but keep the compose plugin from the real one if that is where it lives
  fake_home
  mkdir -p "$DOCKER_CONFIG/cli-plugins"
  for p in "$ORIG_HOME/.docker/cli-plugins/docker-compose"; do
    [ -x "$p" ] && ln -s "$p" "$DOCKER_CONFIG/cli-plugins/docker-compose"
  done
  docker compose version >/dev/null 2>&1 || skip "docker compose plugin not available"
  docker info >/dev/null 2>&1 || skip "docker daemon not running (or not on the default socket)"
  run docker compose -f "$COMPOSE" config -q
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "infra: every published port binds to 127.0.0.1 or [::1]" {
  run published_ports
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 8 ]
  for p in "${lines[@]}"; do
    [[ $p == 127.0.0.1:* || $p == "[::1]:"* ]] || { echo "not loopback: $p"; return 1; }
  done
  # No long-syntax port entries (host_ip/published) that the grep above would miss
  ! grep -Eq '^[[:space:]]*(published|host_ip|target):' "$COMPOSE"
}
