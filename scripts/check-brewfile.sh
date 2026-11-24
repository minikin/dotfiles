#!/usr/bin/env bash
# check-brewfile.sh [Brewfile] [files.md]: the Brewfile row of docs/reference/files.md lists the
# same taps, casks and formulae as the Brewfile, each once. Order does not matter. Exits 1 with
# the names missing from or extra in the row, per kind, and with any name listed twice.
# The backticks in the patterns below are Markdown code spans, not command substitutions.
# shellcheck disable=SC2016
set -euo pipefail

(( $# )) || cd "$(dirname "$0")/.."
brewfile=${1:-Brewfile} doc=${2:-docs/reference/files.md}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bad=0
err() { echo "check-brewfile: $*" >&2; bad=1; }

# Brewfile: tap "x", cask "x", brew "x", with options and comments after the name.
awk -v dir="$tmp" '
  /^[ \t]*(#|$)/ { next }
  match($0, /^[ \t]*(tap|cask|brew)[ \t]+"[^"]+"/) {
    split(substr($0, RSTART, RLENGTH), f, "\"")
    kind = $1
    print f[2] > (dir "/file." kind)
    next
  }
  { printf "check-brewfile: %s:%d: not a tap, cask or brew line: %s\n", FILENAME, FNR, $0 > "/dev/stderr"; bad = 1 }
  END { exit bad }
' "$brewfile" || bad=1

rows=$(grep -c '^| `Brewfile`' "$doc" || true)
if [[ $rows != 1 ]]; then
  err "$doc: expected one row starting with | \`Brewfile\` |, found $rows"
  exit 1
fi
# The row's last cell: "Taps: `a`, `b`. Casks: `c`. Formulae: `d`, `e`."
cell=$(grep '^| `Brewfile`' "$doc" | awk -F'|' '{ print $(NF-1) }')
for label in Taps Casks Formulae; do
  [[ $cell == *"$label: "* ]] || err "$doc: the Brewfile row has no \"$label:\" list"
done
(( bad )) && exit 1
list() {  # list <label>: the backticked names between "<label>: " and the next label or the end
  local rest=${cell#*"$1: "}
  rest=${rest%%Taps: *} rest=${rest%%Casks: *} rest=${rest%%Formulae: *}
  grep -o '`[^`]*`' <<<"$rest" | tr -d '`' || true
}
list Taps >"$tmp/doc.tap"
list Casks >"$tmp/doc.cask"
list Formulae >"$tmp/doc.brew"

for kind in tap cask brew; do
  touch "$tmp/file.$kind"
  case $kind in tap) label=Taps ;; cask) label=Casks ;; brew) label=Formulae ;; esac
  for side in file doc; do
    dups=$(sort "$tmp/$side.$kind" | uniq -d | paste -sd ' ' -)
    if [[ -n $dups ]]; then
      if [[ $side == file ]]; then err "$brewfile lists $kind more than once: $dups"
      else err "$doc lists $label more than once: $dups"; fi
    fi
  done
  sort -u "$tmp/file.$kind" >"$tmp/file.$kind.s"
  sort -u "$tmp/doc.$kind" >"$tmp/doc.$kind.s"
  missing=$(comm -23 "$tmp/file.$kind.s" "$tmp/doc.$kind.s" | paste -sd ' ' -)
  extra=$(comm -13 "$tmp/file.$kind.s" "$tmp/doc.$kind.s" | paste -sd ' ' -)
  [[ -z $missing ]] || err "$doc: $label is missing $missing"
  [[ -z $extra ]] || err "$doc: $label lists $extra, which $brewfile does not have as $kind"
done
(( bad )) && exit 1
echo "check-brewfile: $doc matches $brewfile"
