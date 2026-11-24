#!/usr/bin/env bash
# check-prose.sh [file...]: the repo's prose rules, without the human-writing plugin, so CI can
# run them. Reports file:line for each em dash, curly quote, ellipsis character and semicolon in
# Markdown prose and exits 1 on any. Default files: README.md, CONTRIBUTING.md, SETUP_PROMPT.md
# and every .md under docs/.
# Skipped like the human-writing checker does: frontmatter, fenced code (``` or ~~~, closed by a
# fence of the same character at least as long), inline code spans of any backtick count, HTML
# entities such as &amp; for the semicolon rule, and blockquote lines (a quoted source keeps its
# own punctuation) for the semicolon rule.
set -euo pipefail

if (( $# )); then
  files=("$@")
else
  cd "$(dirname "$0")/.."
  files=(README.md CONTRIBUTING.md SETUP_PROMPT.md)
  while IFS= read -r f; do files+=("$f"); done < <(find docs -name '*.md' | sort)
fi

awk '
  # strip_code: remove every inline code span, a run of n backticks up to the next run of exactly n.
  function strip_code(s,    out, i, n, rest, j, m, endat) {
    out = ""
    while ((i = index(s, "`")) > 0) {
      out = out substr(s, 1, i - 1)
      s = substr(s, i)
      n = 0
      while (substr(s, n + 1, 1) == "`") n++
      rest = substr(s, n + 1)
      endat = 0
      j = 1
      while (j <= length(rest)) {
        if (substr(rest, j, 1) == "`") {
          m = 0
          while (substr(rest, j + m, 1) == "`") m++
          if (m == n) { endat = j; break }
          j += m
        } else j++
      }
      if (endat) s = substr(rest, endat + n)
      else { out = out substr(s, 1, n); s = rest }
    }
    return out s
  }
  function report(what) { printf "%s:%d: %s\n", FILENAME, FNR, what; bad = 1 }
  FNR == 1 { fence = ""; fm = 1; infm = 0 }
  {
    line = $0
    if (fm) {
      if (line ~ /^[ \t]*$/) next
      fm = 0
      if (line == "---") { infm = 1; next }
    }
    if (infm) { if (line == "---") infm = 0; next }
    t = line
    sub(/^[ \t]+/, "", t)
    if (fence != "") {
      if (index(t, fence) == 1) {
        rest = substr(t, length(fence) + 1)
        c = substr(fence, 1, 1)
        while (substr(rest, 1, 1) == c) rest = substr(rest, 2)
        if (rest ~ /^[ \t]*$/) fence = ""
      }
      next
    }
    if (t ~ /^(```|~~~)/) {
      c = substr(t, 1, 1); n = 0
      while (substr(t, n + 1, 1) == c) n++
      fence = substr(t, 1, n)
      next
    }
    p = strip_code(line)
    if (index(p, "\342\200\224")) report("em dash")
    if (index(p, "\342\200\230") || index(p, "\342\200\231") || index(p, "\342\200\234") || index(p, "\342\200\235")) report("curly quote")
    if (index(p, "\342\200\246")) report("ellipsis character")
    q = p
    gsub(/&#?[A-Za-z0-9_]+;/, "", q)
    if (index(q, ";") && t !~ /^>/) report("semicolon")
  }
  END { exit bad }
' "${files[@]}"
