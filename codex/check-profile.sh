#!/usr/bin/env bash
# check-profile.sh <profile.toml> <main checkout>: can a Codex writer started with this profile
# commit in a jj workspace of that checkout? Decodes the TOML with Python's tomllib and checks that
# the top-level sandbox_mode is "workspace-write" and that [sandbox_workspace_write]
# writable_roots is exactly <main checkout>/.jj and <main checkout>/.git, nothing more.
# Prints one reason per failed check, never a path, and exits 1 on any. Exits 2 on bad usage, a
# file it cannot read, invalid TOML (duplicate keys, a bare word as a value) or no Python 3.11+.
# Used by jwx (zsh/jj.zsh) and agent-preflight.
set -euo pipefail

if (( $# != 2 )); then
  echo "usage: check-profile.sh <profile.toml> <main checkout>" >&2
  exit 2
fi

# macOS's /usr/bin/python3 is 3.9, which has no tomllib, so a newer one on PATH comes first.
py=''
for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null && "$candidate" -I -c 'import tomllib' 2>/dev/null; then
    py=$candidate
    break
  fi
done
if [[ -z $py ]]; then
  echo "cannot check the profile: no python3 with tomllib (Python 3.11 or later) on PATH"
  exit 2
fi

"$py" -I - "$1" "${2%/}" <<'PY'
import sys
import tomllib

path, root = sys.argv[1], sys.argv[2]
try:
    with open(path, "rb") as f:
        profile = tomllib.load(f)
except OSError:
    print("cannot read the profile")
    sys.exit(2)
except (tomllib.TOMLDecodeError, UnicodeDecodeError):
    print("the profile is not valid TOML")
    sys.exit(2)

failed = False
if profile.get("sandbox_mode") != "workspace-write":
    print('sandbox_mode is not "workspace-write"')
    failed = True

table = profile.get("sandbox_workspace_write")
roots = table.get("writable_roots") if isinstance(table, dict) else None
want = {root + "/.jj", root + "/.git"}
if not isinstance(roots, list) or not all(isinstance(r, str) for r in roots):
    print("[sandbox_workspace_write] writable_roots is not a list of paths")
    failed = True
else:
    for name in (".jj", ".git"):
        if root + "/" + name not in roots:
            print(f"[sandbox_workspace_write] writable_roots does not name this checkout's {name}")
            failed = True
    extra = set(roots) - want
    if extra:
        print(f"[sandbox_workspace_write] writable_roots has {len(extra)} root(s) besides this checkout's .jj and .git")
        failed = True

sys.exit(1 if failed else 0)
PY
