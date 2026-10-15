# dotfiles

<p align="center">
  <a href="https://github.com/minikin/dotfiles/actions/workflows/ci.yml"><img src="https://github.com/minikin/dotfiles/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license MIT"></a>
</p>

<!-- hero: Ghostty with three agents in splits, light/dark picture -->

A macOS terminal setup for running several AI coding agents in parallel, each
in its own jj workspace. `jwc fix-retry` creates a workspace next to the repo,
copies the untracked `.env` files into it, runs the project's setup and starts
Claude Code there. The agents never share a working directory, and every
change they make is visible from the main checkout, where you review it and
push it as a bookmark named after the workspace.

The repo holds the configs for Ghostty, zsh, starship, jj (Jujutsu), mise,
just and Claude Code, plus a Docker Compose file for a local Redis, Kafka and
Jaeger stack. `install.sh` symlinks them into `$HOME`, so editing `~/.zshrc`
edits the repo. Your name, emails and signing keys never go into the repo:
they live in a local file that `install.sh` writes on the first run.

## Install

On an Apple Silicon Mac with [Homebrew](https://brew.sh):

Clone it anywhere you like. `~/src/dotfiles` is only an example. `install.sh`
records the location as `DOTFILES_DIR`.

```bash
git clone https://github.com/minikin/dotfiles ~/src/dotfiles
cd ~/src/dotfiles
brew bundle              # everything in the Brewfile
./install.sh --dry-run   # what it would link, and what it would back up
./install.sh             # link, merge Claude settings, ask for one identity or two
exec zsh
```

`install.sh` is safe to re-run. Whatever it replaces is moved to
`<file>.bak-<timestamp>`. You can also hand the whole thing to Claude Code:
run `claude` in the repo and paste [SETUP_PROMPT.md](SETUP_PROMPT.md). It
checks the machine, asks for your identity, shows you the dry run and waits
for your OK before it installs. [Install](docs/install.md) has both paths,
what gets backed up, how to verify and how to uninstall.

## Quick start

An agent workspace needs a jj repo. In an existing git repo, run this once.
jj lives next to `.git/`, and git, your IDE and CI keep working:

```bash
cd ~/repos/my-service
jj git init --colocate
```

Then start an agent. `jwc` creates the workspace (a slash in the name becomes
a dash), runs the setup and opens Claude Code in it:

```console
$ jwc feat/x
Created workspace in "../my-service-ws/feat-x"
copied .env
setup: just setup
```

Open a split with `cmd+d` and start the next one the same way. While they
work, review from the main checkout. Each workspace's working copy shows up
as `<name>@`, and `jj dft` is a structural diff through difftastic:

```bash
jj stack               # your stack on top of trunk
jj dft -r feat-x@      # what the agent has so far
```

When it looks right, `jpush` from inside the workspace pushes the agent's
latest non-empty change as the bookmark `feat-x`. `jws` switches to it with
fzf if you are not already there. Remove the workspace after the merge, and
the agent's changes stay in the repo:

```bash
jws                    # pick feat-x
jpush
gh pr create --head feat-x

# once the pull request is merged
jj git fetch
jwrm feat-x
```

For the commands you do not type every day, press `Ctrl-G`: it opens a
palette of saved workflows, fills their arguments from live pickers (jj
changes, Kafka topics, pods) and inserts the command into the prompt without
running it. See [Saved workflows](docs/guides/workflows.md).

[Getting started](docs/getting-started.md) walks through a first session
with two agents, including what the Claude Code status line shows.

## Local infra

`infra up` starts Redis on `localhost:6379`, a single-node Kafka on
`localhost:9092`, kafka-ui on http://localhost:8088 and Jaeger on
http://localhost:16686 with OTLP on 4317 and 4318, all bound to loopback and
run through Docker or OrbStack. `infra down` stops it and keeps the data,
`infra reset` deletes the data too. [Local infra](docs/guides/local-infra.md)
has the Kafka and Redis commands.

## Documentation

- Start with the [introduction](docs/introduction.md),
  [install](docs/install.md) and [getting started](docs/getting-started.md).
- Guides: [a day with parallel agents](docs/guides/daily-routine.md),
  [parallel agents](docs/guides/parallel-agents.md),
  [reviewing and landing their work](docs/guides/review-and-land.md),
  [identity and commit signing](docs/guides/identity-and-signing.md),
  [local infra](docs/guides/local-infra.md),
  [per-project tools and MCP servers](docs/guides/project-tools.md),
  [saved workflows with navi](docs/guides/workflows.md),
  [Claude Code integration](docs/guides/claude-code.md),
  [updating the dotfiles](docs/guides/updating.md).
- Reference: [install.sh](docs/reference/install-sh.md),
  [shell commands](docs/reference/shell-commands.md),
  [keybindings](docs/reference/keybindings.md),
  [jj config](docs/reference/jj-config.md),
  [files and where they go](docs/reference/files.md),
  [the cheatsheet](docs/reference/cheatsheet.md).
- How it works: [design](docs/explanation/design.md),
  [agents and PATH](docs/explanation/agents-and-path.md).
- [Troubleshooting](docs/troubleshooting.md) starts with the usual cause of
  wrong tool versions inside Claude Code.

## Development

The `justfile` holds the checks, and `brew bundle` installs what they need
(bats-core, shellcheck, gitleaks, lychee, actionlint). `just lint` runs
shellcheck, a check that bats asserts end in `|| false`, `zsh -n`, `docker compose config` when Docker is installed and an
offline link check. `just test` runs the bats tests in `tests/`,
`just secrets` scans for secrets and personal data, and `just commits` checks
that commit messages follow Conventional Commits. `just check` runs all four,
and CI runs them on every push to `main` and every pull request.

`just drift` compares each file `install.sh` links with the repo copy and
changes nothing:

```console
$ just drift
linked       ~/.config/ghostty/config
linked       ~/.zshrc
DIFFERS      ~/.claude/statusline.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before sending a change, and
[CHANGELOG.md](CHANGELOG.md) for what changed.

## License

MIT. See the [LICENSE](LICENSE) file.
