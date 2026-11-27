#!/usr/bin/env bash
# linux-brewfile.sh [Brewfile]: print the Brewfile without the lines Linuxbrew cannot install,
# every cask and every line tagged "# macos-only". install.sh --brew and just doctor pipe it into
# brew bundle --file=- on Linux.
set -euo pipefail
brewfile=${1:-$(cd "$(dirname "$0")/.." && pwd)/Brewfile}
grep -vE '^[[:space:]]*cask[[:space:]]|# macos-only' "$brewfile"
