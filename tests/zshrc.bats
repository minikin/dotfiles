#!/usr/bin/env bats
# zsh/zshrc: _cached_init, the cache for tool init scripts. The rest of zshrc needs the real
# tools, so only that function is loaded, cut out of the file.

load helpers

setup() {
  fake_home
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # Stub tool: logs each run and prints an init script that sets a variable.
  cat > "$BATS_TEST_TMPDIR/bin/tool" <<'STUB'
#!/bin/sh
echo run >> "$HOME/tool.log"
[ -z "$TOOL_FAIL" ] || exit 1
echo "TOOL_INIT='$*'"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/tool"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  sed -n '/^zmodload -F zsh\/stat/,/^}/p' "$REPO_ROOT/zsh/zshrc" > "$BATS_TEST_TMPDIR/cached_init.zsh"
  [ -s "$BATS_TEST_TMPDIR/cached_init.zsh" ]
}

cached() { run zsh -f -c "source '$BATS_TEST_TMPDIR/cached_init.zsh'; _cached_init $1; print -r -- \"init=\${TOOL_INIT-unset}\""; }
runs() { wc -l < "$HOME/tool.log" | tr -d ' '; }

@test "zshrc: _cached_init sources the output and runs the tool only once" {
  cached "tool init zsh"
  [ "$status" -eq 0 ]
  [ "$output" = "init=init zsh" ]
  cached "tool init zsh"
  [ "$output" = "init=init zsh" ]
  [ "$(runs)" = 1 ]
  [ -f "$HOME/.cache/zsh/init-tool.zsh" ]
}

@test "zshrc: _cached_init runs the tool again when its args or the binary change" {
  cached "tool init zsh"
  cached "tool init bash"
  [ "$output" = "init=init bash" ]
  [ "$(runs)" = 2 ]
  touch -t 203001010000 "$BATS_TEST_TMPDIR/bin/tool"
  cached "tool init bash"
  [ "$(runs)" = 3 ]
}

@test "zshrc: _cached_init keeps no cache when the tool fails, and skips a missing tool" {
  TOOL_FAIL=1 cached "tool init zsh"
  [ "$status" -eq 0 ]
  [ "$output" = "init=unset" ]
  [ ! -e "$HOME/.cache/zsh/init-tool.zsh" ]
  ! ls "$HOME/.cache/zsh/"init-tool.zsh.* 2>/dev/null || false
  cached "no-such-tool init"
  [ "$status" -eq 0 ]
  [ "$output" = "init=unset" ]
}
