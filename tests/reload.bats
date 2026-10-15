#!/usr/bin/env bats
# zsh/reload.zsh: validate every config, then restart zsh. A broken config never restarts.

load helpers

setup() {
  fake_home
  mkdir -p "$HOME/.config/zsh" "$BATS_TEST_TMPDIR/bin"
  printf 'true\n' > "$HOME/.zshrc"
  printf 'true\n' > "$HOME/.config/zsh/jj.zsh"
  touch "$HOME/.zcompdump" "$HOME/.zcompdump-host-5.9"
  # Stub ghostty: records the call, fails when GHOSTTY_FAIL is set.
  cat > "$BATS_TEST_TMPDIR/bin/ghostty" <<'EOF'
#!/bin/sh
echo "ghostty $*" >> "$HOME/ghostty.log"
[ -z "$GHOSTTY_FAIL" ] || { echo "config error: font-size" >&2; exit 1; }
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/ghostty"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GHOSTTY_BIN="$BATS_TEST_TMPDIR/bin/ghostty"
}

# reload in a zsh without rc files; `exec zsh` then reads stdin (/dev/null) and exits 0.
run_reload() {
  run zsh -f -c "source '$REPO_ROOT/zsh/reload.zsh'; reload; echo AFTER-EXEC" </dev/null
}

@test "reload: valid configs clear completions and restart zsh" {
  run_reload
  [ "$status" -eq 0 ]
  [[ $output == *"ghostty: config valid, press cmd+shift+, to apply it"* ]] || false
  [[ $output == *"zsh: restarting"* ]] || false
  [[ $output != *AFTER-EXEC* ]] || false
  grep -qx 'ghostty +validate-config' "$HOME/ghostty.log"
  ! ls "$HOME"/.zcompdump* 2>/dev/null || false
}

@test "reload: a zsh syntax error stops before the restart" {
  printf 'if then fi {\n' > "$HOME/.config/zsh/jj.zsh"
  run_reload
  [[ $output == *"reload: syntax error in"*"jj.zsh"* ]] || false
  [[ $output == *AFTER-EXEC* ]] || false
  [[ $output != *"zsh: restarting"* ]] || false
  [ -f "$HOME/.zcompdump" ]
}

@test "reload: an invalid Ghostty config stops before the restart" {
  GHOSTTY_FAIL=1 run_reload
  [[ $output == *"config error: font-size"* ]] || false
  [[ $output == *AFTER-EXEC* ]] || false
}

@test "reload: an invalid jj config stops before the restart" {
  export JJ_CONFIG="$BATS_TEST_TMPDIR/bad.toml"
  printf '[ui\n' > "$JJ_CONFIG"
  run_reload
  [[ $output == *"reload: jj config"* ]] || false
  [[ $output == *AFTER-EXEC* ]] || false
}

@test "reload: without Ghostty it still restarts zsh" {
  export GHOSTTY_BIN="$BATS_TEST_TMPDIR/none"
  rm "$BATS_TEST_TMPDIR/bin/ghostty"
  run_reload
  [[ $output == *"zsh: restarting"* ]] || false
  [[ $output != *AFTER-EXEC* ]] || false
}
