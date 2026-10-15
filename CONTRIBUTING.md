# Contributing to dotfiles

These dotfiles install into a real `$HOME` and sign real commits, so the
repo holds itself to three rules: tests never touch the machine they run on,
nothing personal is committed, and every value in the docs matches the code.
This page is what you need to get a change through that.

## Which kind of change is yours

**A bug fix.** Open an issue with the bug form, or send the pull request
directly. Write the failing bats test first, in a fake `HOME`, then the
smallest change that makes it pass.

**A new tool, command or setting.** Open an issue first and describe the
problem, not only the tool you want. Decide where it belongs before writing
it: a tool whose version must match a project's CI goes in that project's
`mise.toml`, not here. Global tools are inspection and editor tools that
behave the same in every project.

**Docs, comments, anything with no change in behaviour.** Send the pull
request. If a test fails because of it, it changed behaviour after all.

## Setup

macOS on Apple Silicon with Homebrew at `/opt/homebrew`. From the checkout:

```sh
brew bundle      # everything in Brewfile, including bats-core, shellcheck, gitleaks, lychee, actionlint
just             # lists every recipe
```

You do not need to run `install.sh` to work on the repo. If you do, run
`./install.sh --dry-run` first and read what it would replace.

## The command to run before you push

```sh
just check       # lint, tests and the secret scan, the same as CI
```

| Recipe         | Runs                                                                                      |
| -------------- | ----------------------------------------------------------------------------------------- |
| `just lint`    | `shellcheck` on `install.sh`, `claude/statusline.sh` and `scripts/*.sh`, `zsh -n` on every zsh file, `docker compose config -q` on `infra/compose.yaml` when Docker is installed, and `lychee --offline` on every Markdown file in the repo. |
| `just test`    | `bats tests`.                                                                             |
| `just secrets` | `scripts/check-secrets.sh`, then `gitleaks dir . --config .gitleaks.toml` when gitleaks is installed. |
| `just commits` | `scripts/check-commits.sh`: every non-merge commit subject in `origin/main..HEAD` (or the range given, `just commits <range>`) follows Conventional Commits. |
| `just check`   | All four.                                                                                 |
| `just drift`   | Read-only: compares each file `install.sh` links with the repo copy. Not part of `check`. |

CI runs two jobs on every push to `main` and every pull request:

- `check` on `macos-latest`: installs `git just bats-core shellcheck jq
  lychee gitleaks mise navi` with Homebrew, installs jj 0.46.0 from its GitHub
  release with a pinned checksum, and runs `just check`. The commit check
  covers the pull request's commits, or the commits a push added.
- `history-secrets` on `ubuntu-latest`: downloads gitleaks 8.30.1, verifies
  its checksum, and scans every commit reachable from the checked-out ref.
  A secret removed in a later commit still fails it, so rewrite the history
  before pushing rather than after.

Run `actionlint` yourself after editing `.github/workflows/ci.yml`. CI does
not.

## Tests

The tests are bats suites in `tests/`, one per area: `install.bats`,
`jj.bats`, `sign.bats`, `drift.bats`, `statusline.bats`, `infra.bats`,
`navi.bats`, `commits.bats`. Each test calls the helpers in
`tests/helpers.bash`, and those helpers are what keep a test run away from
your machine:

- `fake_home` points `HOME` and `XDG_CONFIG_HOME` at a directory under
  `BATS_TEST_TMPDIR`. Nothing reads or writes the real home, so no
  `~/.config/jj/conf.d/identity.toml` and no 1Password signing config is
  ever loaded.
- jj reads only the repo's `jj/config.toml` (`JJ_CONFIG`), with identity from
  `JJ_USER` and `JJ_EMAIL`. git reads only the fake `~/.gitconfig`
  (`GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM=1`). Every `DOTFILES_*` variable
  and `JW_NO_SETUP` are unset.
- `copy_repo` copies the tree to `BATS_TEST_TMPDIR/dotfiles`, so `install.sh`
  links into the copy. A broken install test cannot rename a file in your
  checkout.
- `run_install` runs the copy with stdin from `/dev/null`, so it never
  prompts.

The rules for a new test:

- Call `fake_home` in `setup`. Never let a test read the real `HOME`.
- Never sign for real. Do not set `signing.*`, `commit.gpgsign` or
  `gpg.ssh.program` to a real key or to `op-ssh-sign` in a test. To test the
  signing code paths, check what `install.sh` writes, not whether a commit
  verifies.
- Write files only under `BATS_TEST_TMPDIR`. Remotes are bare repos there.
- End every `[[ ... ]]` and `! cmd` assert with `|| false`. bats runs under
  macOS's bash 3.2, which ignores those when they fail anywhere but on a
  test's last line. `just lint` checks it.
- A known bug gets a test with `skip "BUG: ..."` that says what is wrong,
  until the fix lands.

Try a shell function by hand the same way: in a `mktemp -d` directory with a
throwaway `jj git init --colocate` repo, never in a real one.

## Adding a workflow

A saved workflow is an entry in one of the `navi/*.cheat` files: a
`# description` line, the command, and a `$ name:` picker line for each
`<name>` argument that should offer choices. [Saved
workflows](docs/guides/workflows.md#write-your-own) has the format.
Add an entry only when it has a picker or a command line you would not
type from memory. A short command like `jj undo` is faster to type than to
find. Put the `%` group line on a meaningful category (`kafka`, `review`)
and order entries from most to least used.
`tests/navi.bats` enforces these rules:

- The description is unique across all cheats. Start it with the verb and
  the object you would search for ("Tail Kafka topic") and keep it short.
- Pickers run in bash, so they never call `jw`, `jwc`, `jws`, `jwl`, `jwrm`,
  `jpush`, `jland`, `reload`, `infra`, `sign-as`, `z` or `zi`. The command
  line may.
- Every `jj` picker passes `--ignore-working-copy`.
- An infra entry that deletes topics or Redis keys, resets consumer group
  offsets, flushes Redis or runs `infra reset` starts with `[LOCAL ONLY]`,
  and every `kcat`, `redis-cli` and Kafka command targets `localhost`.
- An entry that pushes straight to main starts with `[PERSONAL]`.

Run the suite before you push:

```sh
bats tests/navi.bats
```

The suite skips when `navi` is not installed, and the column test also
needs `expect`. Pickers
that call Docker, `kubectl`, `gh`, `go list` or `redis-cli` are skipped, so
try those by hand once.

## Docs

The docs follow the [Diátaxis](https://diataxis.fr/) split: guides for
tasks, reference for exact facts, explanation for reasons. A reference page states what the code does today,
including its quirks, with tables where the content is tabular. Every value
in it (a path, a key, a default, a port) must match the code. When you
change a value in the code, search the docs for it.

Prose goes through the human-writing checker before you push:

```sh
python3 path/to/human-writing/scripts/check.py README.md CHANGELOG.md CONTRIBUTING.md docs/**/*.md
```

It must report 0 hard findings and no semicolon warnings. The rules it
enforces: no em dashes, no curly quotes, no ellipsis character, no
semicolons in prose. Code spans and fenced blocks are not checked. CI does
not run it, so it is on you.

Leave `CHANGELOG.md` alone. The maintainer writes it for the release.

## jj and signed commits

The repo is colocated jj and git. Use jj for every write: no `git commit`,
`git add`, `git rebase` or `git checkout`. Read-only git is fine.

```sh
jj st
jj diff --git
jj commit -m "feat(ghostty): bump font size"
```

Messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):
`<type>(<scope>): <summary>`, with the summary in the imperative and in
lower case. The type is one of `feat`, `fix`, `docs`, `test`, `ci`,
`refactor`, `chore` or `perf`. The scope is the area the change touches:
`ghostty`, `zsh`, `jj`, `install`, `infra`, `claude`, `navi`, `mise`,
`starship`, `scripts` or `just`. Leave the scope out when the type already names the
area (`docs:`, `ci:`, `test:`). Mark a change that breaks an existing setup
with `!` after the scope and a `BREAKING CHANGE:` footer that says what to
do. One change per scope per commit.

Every commit must be signed. Never pass `--no-gpg-sign` or `-c commit.gpgsign=false`, and do not
change `signing.*` to get a commit through. If signing fails, fix the key or
the agent. Commits carry no `Co-Authored-By:` or other attribution trailers.

## No personal data

The repo is public. Nothing in it may identify you or your employer: no real
names, no email addresses outside `example.com`, `example.org`, `example.net`
and `*.example`, no absolute home paths (write `~/` or `$HOME`), no SSH
public key bodies (`AAAA...` placeholders are fine), no 1Password vault names
or secret references. Your identity lives in
`~/.config/jj/conf.d/identity.toml` and never in a tracked file.

`just secrets` catches these in the working tree, and the `history-secrets`
CI job catches them in every commit. Add the strings no regex can know to a
local denylist, one per line:

```sh
mkdir -p ~/.config/dotfiles
$EDITOR ~/.config/dotfiles/denylist.txt   # your name, employer, personal email
```

`scripts/check-secrets.sh` reads `${DOTFILES_DENYLIST:-~/.config/dotfiles/denylist.txt}`,
matches each line as a case-insensitive fixed string, and ignores blank lines
and lines starting with `#`. The denylist is outside the repo and is never
committed.

## Finding your way around

| Path                       | What it is                                                    |
| -------------------------- | ------------------------------------------------------------- |
| `install.sh`               | The installer: links, settings merge, identity                |
| `ghostty/`, `zsh/`, `starship/`, `jj/`, `mise/`, `claude/`, `infra/`, `navi/` | The configs it installs |
| `Brewfile`                 | Every package, including the tools the checks need            |
| `justfile`                 | Every check, local and CI                                     |
| `scripts/check-secrets.sh` | The personal-data scan                                        |
| `scripts/check-commits.sh` | The Conventional Commits check                                |
| `.gitleaks.toml`           | The same rules for gitleaks and the history scan              |
| `tests/`                   | bats suites and `helpers.bash`                                |
| `docs/`                    | The book: guides, reference, explanation                      |

[Files](docs/reference/files.md) lists every file with where it is installed.
