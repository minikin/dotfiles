#!/usr/bin/env bash
# check-prose.sh [file...]: the repo's prose rules, without the human-writing plugin, so CI can
# run them. Reports file:line for each em dash, curly quote, ellipsis character and semicolon in
# Markdown prose and exits 1 on any. Default files: README.md, CONTRIBUTING.md, SETUP_PROMPT.md
# and every .md under docs/.
# Skipped like the human-writing checker does: frontmatter (a leading --- block that has its
# closing ---), fenced code (``` or ~~~, closed by a fence of the same character at least as long;
# a ``` line with another backtick after it is inline code, not a fence), inline code spans of any
# backtick count, also across the lines of one paragraph but never across headings, setext
# underlines, thematic breaks, list items, table rows (with or without outer pipes) or blockquote
# edges, HTML entities such as &amp; for the
# semicolon rule, and blockquote lines (a quoted source keeps its own punctuation) for the
# semicolon rule.
set -euo pipefail

if (( $# )); then
  files=("$@")
else
  cd "$(dirname "$0")/.."
  files=(README.md CONTRIBUTING.md SETUP_PROMPT.md)
  while IFS= read -r f; do files+=("$f"); done < <(find docs -name '*.md' | sort)
fi

awk '
  # strip_code: drop every inline code span, a run of n backticks up to the next run of exactly
  # n. Newlines inside a span are kept, so the text still splits into its source lines. A run
  # with no closing run is literal text.
  function strip_code(s,    out, i, n, rest, j, m, endat, span, k) {
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
      if (endat) {
        span = substr(rest, 1, endat - 1)
        for (k = 1; k <= length(span); k++) if (substr(span, k, 1) == "\n") out = out "\n"
        s = substr(rest, endat + n)
      } else { out = out substr(s, 1, n); s = rest }
    }
    return out s
  }
  function report(line, what) { printf "%s:%d: %s\n", name, line, what; bad = 1 }
  function check(p, line, quote,    q) {
    if (index(p, "\342\200\224")) report(line, "em dash")
    if (index(p, "\342\200\230") || index(p, "\342\200\231") || index(p, "\342\200\234") || index(p, "\342\200\235")) report(line, "curly quote")
    if (index(p, "\342\200\246")) report(line, "ellipsis character")
    q = p
    gsub(/&#?[A-Za-z0-9_]+;/, "", q)
    if (index(q, ";") && !quote) report(line, "semicolon")
  }
  # flush: check the paragraph gathered so far, with code spans resolved across its lines.
  function flush(    text, i, k, parts) {
    if (np == 0) return
    text = pl[1]
    for (i = 2; i <= np; i++) text = text "\n" pl[i]
    k = split(strip_code(text), parts, "\n")
    for (i = 1; i <= k; i++) check(parts[i], pn[i], pq[i])
    np = 0
  }
  function trimmed(s) { sub(/^[ \t]+/, "", s); return s }
  # rule: three or more of one of * - _, spaces allowed between them, and nothing else.
  function rule(t,    c, rest) {
    c = substr(t, 1, 1)
    if (c != "*" && c != "-" && c != "_") return 0
    rest = t
    gsub(/[ \t]/, "", rest)
    if (length(rest) < 3) return 0
    gsub(c == "*" ? "[*]" : c, "", rest)
    return rest == ""
  }
  # delimiter: a table delimiter row such as |---|:--:| or --- | ---.
  function delimiter(t) {
    return index(t, "-") && index(t, "|") && t ~ /^[|]?[ \t]*:?-+:?[ \t]*([|][ \t]*:?-+:?[ \t]*)*[|]?[ \t]*$/
  }
  # doc: one whole file, buffered in L[1..n], so frontmatter can be told from a leading rule.
  function doc(    i, start, f, j, t, fence, c, k, rest, quote, heading, intable) {
    start = 1
    for (f = 1; f <= n && L[f] ~ /^[ \t]*$/; f++) ;
    if (f <= n && L[f] == "---")
      for (j = f + 1; j <= n; j++) if (L[j] == "---") { start = j + 1; break }
    fence = ""; np = 0
    for (i = start; i <= n; i++) {
      t = trimmed(L[i])
      if (fence != "") {
        if (index(t, fence) == 1) {
          rest = substr(t, length(fence) + 1)
          c = substr(fence, 1, 1)
          while (substr(rest, 1, 1) == c) rest = substr(rest, 2)
          if (rest ~ /^[ \t]*$/) fence = ""
        }
        continue
      }
      if (t ~ /^(```|~~~)/) {
        intable = 0
        c = substr(t, 1, 1); k = 0
        while (substr(t, k + 1, 1) == c) k++
        if (!(c == "`" && index(substr(t, k + 1), "`"))) {
          flush()
          fence = substr(t, 1, k)
          continue
        }
      }
      if (t == "") { flush(); intable = 0; continue }
      # A thematic break (***, ---, ___) or a setext underline (=== or --- under text) ends the
      # block before it and holds no prose of its own.
      if (rule(t) || t ~ /^=+[ \t]*$/ || (np && t ~ /^-+[ \t]*$/)) { flush(); continue }
      # A table starts at a row with a | over a delimiter row, outer pipes or not, and runs to the
      # next blank line. Each row is a block: cells end code spans.
      if (!intable && index(t, "|") && i < n && delimiter(trimmed(L[i + 1]))) intable = 1
      if (intable) {
        flush()
        if (!delimiter(t)) { np = 1; pl[1] = L[i]; pn[1] = i; pq[1] = 0; flush() }
        continue
      }
      # A code span never crosses a block: a heading, a list item, a table row, or the start or
      # end of a blockquote begins a new one, and a heading is a block of its own.
      quote = (t ~ /^>/)
      heading = (t ~ /^#+([ \t]|$)/)
      if (np && (heading || t ~ /^([-*+]|[0-9]+[.)])([ \t]|$)/ || t ~ /^[|]/ || quote != pq[np])) flush()
      np++; pl[np] = L[i]; pn[np] = i; pq[np] = quote
      if (heading) flush()
    }
    flush()
  }
  FNR == 1 && NR > 1 { doc() }
  FNR == 1 { name = FILENAME; n = 0; split("", L) }
  { L[++n] = $0 }
  END { if (NR) doc(); exit bad }
' "${files[@]}"
