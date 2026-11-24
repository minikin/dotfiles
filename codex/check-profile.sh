#!/usr/bin/env bash
# check-profile.sh <profile.toml> <main checkout>: can a Codex writer started with this profile
# commit in a jj workspace of that checkout? Parses the TOML and checks that the top-level
# sandbox_mode is "workspace-write" and that [sandbox_workspace_write] writable_roots holds
# exactly <main checkout>/.jj and <main checkout>/.git. Comments and other keys do not count.
# Prints one reason per failed check, never a path, and exits 1 on any, 2 on bad usage or a file
# it cannot parse. Used by jwx (zsh/jj.zsh) and agent-preflight.
# It reads a subset of TOML: tables, bare and dotted keys, basic and literal strings, and arrays
# of strings over one or more lines. A profile outside that subset fails to parse.
set -euo pipefail

if (( $# != 2 )); then
  echo "usage: check-profile.sh <profile.toml> <main checkout>" >&2
  exit 2
fi
profile=$1 root=${2%/}
if [[ ! -f $profile || ! -r $profile ]]; then
  echo "cannot read the profile"
  exit 2
fi

values=$(awk '
  # nocomment: the line without a # comment outside strings.
  function nocomment(s,    out, i, c, q) {
    out = ""; q = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "") {
        if (c == "#") break
        if (c == "\"" || c == "\047") q = c
      } else if (q == "\"" && c == "\\") {
        out = out c; i++; c = substr(s, i, 1)
      } else if (c == q) q = ""
      out = out c
    }
    return out
  }
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  # depth: open brackets minus closed ones outside strings, -1 after an unterminated string.
  function depth(s,    i, c, q, d) {
    q = ""; d = 0
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (q == "") {
        if (c == "\"" || c == "\047") q = c
        else if (c == "[") d++
        else if (c == "]") d--
      } else if (q == "\"" && c == "\\") i++
      else if (c == q) q = ""
    }
    return q == "" ? d : -1
  }
  # roots: print each element of a one-level array of strings, fail on anything else.
  function roots(v,    i, c, q, cur, want) {
    v = trim(v)
    if (substr(v, 1, 1) != "[" || substr(v, length(v), 1) != "]") { bad = 1; return }
    v = substr(v, 2, length(v) - 2)
    q = ""; cur = ""; want = 1
    for (i = 1; i <= length(v); i++) {
      c = substr(v, i, 1)
      if (q == "") {
        if (c == "\"" || c == "\047") { if (!want) { bad = 1; return }; q = c; cur = "" }
        else if (c == ",") { if (want) { bad = 1; return }; want = 1 }
        else if (c !~ /[ \t]/) { bad = 1; return }
      } else if (q == "\"" && c == "\\") { i++; cur = cur substr(v, i, 1) }
      else if (c == q) { print "root\t" cur; q = ""; want = 0 }
      else cur = cur c
    }
    if (q != "") bad = 1
  }
  function string(v) {
    v = trim(v)
    if (v ~ /^"[^"\\]*"$/ || v ~ /^\047[^\047]*\047$/) return substr(v, 2, length(v) - 2)
    bad = 1
    return ""
  }
  function assign(key, v) {
    if (key == "sandbox_mode") print "mode\t" string(v)
    else if (key == "sandbox_workspace_write.writable_roots") roots(v)
  }
  {
    line = trim(nocomment($0))
    if (pending) {
      buf = buf " " line
      d = depth(buf)
      if (d == 0) { assign(pkey, buf); pending = 0 }
      else if (d < 0) bad = 1
      next
    }
    if (line == "") next
    if (line ~ /^\[\[/) { table = "\001"; next }
    if (line ~ /^\[/) {
      t = line; sub(/^\[[ \t]*/, "", t)
      if (t !~ /\]$/) { bad = 1; next }
      sub(/[ \t]*\]$/, "", t)
      table = t
      next
    }
    eq = index(line, "=")
    if (!eq) { bad = 1; next }
    key = trim(substr(line, 1, eq - 1)); v = trim(substr(line, eq + 1))
    if (key !~ /^[A-Za-z0-9_.-]+$/) { bad = 1; next }
    if (table != "") key = table "." key
    d = depth(v)
    if (d > 0) { pending = 1; pkey = key; buf = v }
    else if (d < 0) bad = 1
    else assign(key, v)
  }
  END { if (pending) bad = 1; exit bad }
' "$profile") || { echo "the profile is not TOML this check can read"; exit 2; }

fail=0
mode=$(sed -n 's/^mode	//p' <<<"$values" | tail -1)
if [[ $mode != workspace-write ]]; then
  echo 'sandbox_mode is not "workspace-write"'
  fail=1
fi
for dir in .jj .git; do
  if ! grep -qxF "root	$root/$dir" <<<"$values"; then
    echo "[sandbox_workspace_write] writable_roots does not name this checkout's $dir"
    fail=1
  fi
done
exit "$fail"
