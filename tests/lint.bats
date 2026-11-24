#!/usr/bin/env bats
# scripts/check-prose.sh and scripts/check-brewfile.sh on the repo and on fixtures.

load helpers

setup() {
  fake_home
}

prose() { run "$REPO_ROOT/scripts/check-prose.sh" "$@"; }

@test "prose: the repo's README, CONTRIBUTING, SETUP_PROMPT and docs pass" {
  prose
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "prose: each forbidden character is reported with its file and line" {
  printf 'ok line\na \342\200\224 b\n\342\200\234q\342\200\235 and \342\200\230s\342\200\231\nwait\342\200\246\nsemi; colon\n' >a.md
  prose a.md
  [ "$status" -eq 1 ]
  [ "$output" = $'a.md:2: em dash\na.md:3: curly quote\na.md:4: ellipsis character\na.md:5: semicolon' ]
}

@test "prose: code, frontmatter, entities and quotes are skipped, line numbers kept" {
  cat >b.md <<'EOF'

---
title: a — b; c
---
`x — y; z` and ``a ` b; c`` are code
&amp; and &#8212; are entities
> a quoted source; keeps its punctuation
```sh
echo a; echo b
~~~
still in the block; yes
```
~~~~
tilde; block
~~~~~
after the blocks; reported
EOF
  prose b.md
  [ "$status" -eq 1 ]
  [ "$output" = "b.md:16: semicolon" ]
}

@test "prose: a quote marker still counts for the typography rules" {
  printf '> a \342\200\224 b\n' >q.md
  prose q.md
  [ "$status" -eq 1 ]
  [ "$output" = "q.md:1: em dash" ]
}

@test "prose: an unclosed fence in one file does not hide the next file" {
  printf '```\nnever closed; fine\n' >one.md
  printf 'second; file\n' >two.md
  prose one.md two.md
  [ "$status" -eq 1 ]
  [ "$output" = "two.md:1: semicolon" ]
}

@test "prose: a horizontal rule later in the file is not frontmatter" {
  printf 'text\n---\nsemi; here\n---\n' >hr.md
  prose hr.md
  [ "$status" -eq 1 ]
  [ "$output" = "hr.md:3: semicolon" ]
}

brewfile() { run "$REPO_ROOT/scripts/check-brewfile.sh" "$@"; }

# fixture <files.md row cell>: a Brewfile in the repo's formats and a files.md with one row.
fixture() {
  cat >Brewfile <<'EOF'
# Terminal
tap "acme/tap"
cask "ghostty"
cask "acme/tap/tool", trusted: true
brew "jq"                 # JSON
brew "acme/tap/cli", trusted: true  # comment
cask "claude-code@latest"

brew "git"
EOF
  printf '# Files\n\n| Repo file | Used by | Installs |\n| --- | --- | --- |\n| `Brewfile` | `brew bundle` | %s |\n' "$1" >files.md
}

@test "brewfile: the repo's Brewfile row matches its Brewfile" {
  brewfile
  [ "$status" -eq 0 ]
  [[ $output == *"matches"* ]] || false
}

@test "brewfile: trusted options, comments, qualified names and a different order pass" {
  fixture 'Taps: `acme/tap`. Casks: `claude-code@latest`, `ghostty`, `acme/tap/tool`. Formulae: `git`, `acme/tap/cli`, `jq`.'
  brewfile Brewfile files.md
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "brewfile: a missing cask and an extra formula are named" {
  fixture 'Taps: `acme/tap`. Casks: `ghostty`, `acme/tap/tool`. Formulae: `git`, `acme/tap/cli`, `jq`, `wget`.'
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *"Casks is missing claude-code@latest"* ]] || false
  [[ $output == *"Formulae lists wget, which Brewfile does not have as brew"* ]] || false
}

@test "brewfile: a package under the wrong kind fails on both kinds" {
  fixture 'Taps: `acme/tap`. Casks: `claude-code@latest`, `acme/tap/tool`. Formulae: `git`, `acme/tap/cli`, `jq`, `ghostty`.'
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *"Casks is missing ghostty"* ]] || false
  [[ $output == *"Formulae lists ghostty"* ]] || false
}

@test "brewfile: a name listed twice fails, in the row or in the Brewfile" {
  fixture 'Taps: `acme/tap`. Casks: `claude-code@latest`, `ghostty`, `ghostty`, `acme/tap/tool`. Formulae: `git`, `acme/tap/cli`, `jq`.'
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *"files.md lists Casks more than once: ghostty"* ]] || false

  fixture 'Taps: `acme/tap`. Casks: `claude-code@latest`, `ghostty`, `acme/tap/tool`. Formulae: `git`, `acme/tap/cli`, `jq`.'
  echo 'brew "jq"' >>Brewfile
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *"Brewfile lists brew more than once: jq"* ]] || false
}

@test "brewfile: a row without one of the three lists, or not exactly one row, fails" {
  fixture 'Taps: `acme/tap`. Casks: `claude-code@latest`, `ghostty`, `acme/tap/tool`.'
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *'no "Formulae:" list'* ]] || false

  fixture 'Taps: `acme/tap`. Casks: `ghostty`. Formulae: `jq`.'
  sed -n '$p' files.md >>files.md
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *"expected one row"*"found 2"* ]] || false
}

@test "brewfile: a Brewfile line that is not tap, cask or brew fails" {
  fixture 'Taps: `acme/tap`. Casks: `claude-code@latest`, `ghostty`, `acme/tap/tool`. Formulae: `git`, `acme/tap/cli`, `jq`.'
  echo 'mas "Xcode", id: 497799835' >>Brewfile
  brewfile Brewfile files.md
  [ "$status" -eq 1 ]
  [[ $output == *"not a tap, cask or brew line"* ]] || false
}
