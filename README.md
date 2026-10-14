# dotfiles

A macOS (Apple Silicon) terminal setup built for running several AI coding agents in parallel: Ghostty, zsh, starship, jj (Jujutsu) workspaces with one workspace per agent, mise, just, and Claude Code, plus a local Redis / Kafka / Jaeger stack in Docker.

- **[docs/GUIDE.md](docs/GUIDE.md)**: step-by-step usage and workflows.
- **[CHEATSHEET.md](CHEATSHEET.md)**: one-page command reference.

## Quick start

```sh
git clone https://github.com/minikin/dotfiles ~/repos/personal/dotfiles
cd ~/repos/personal/dotfiles
brew bundle                 # install everything in Brewfile
./install.sh --dry-run      # preview: what gets linked, what gets backed up
./install.sh                # symlink configs, merge Claude settings, ask for your identity
exec zsh
```

Or let Claude Code do it: run `claude` in the repo and paste [`SETUP_PROMPT.md`](SETUP_PROMPT.md). It runs preflight checks, asks you for your identity values, waits for your OK after the dry run, and verifies the result.

How `install.sh` works:

- **Idempotent.** You can re-run it safely. Anything it replaces is moved to `<file>.bak-<timestamp>`.
- **Symlinks.** Installed configs link back into the repo, so editing `~/.zshrc` edits the repo. Commit with `jj`.
- **Claude settings are merged.** Keys from the fragment (`env.JJ_EDITOR`, `statusLine`) win, permission allow/deny lists are unioned, and all other keys are kept.
- **Identity stays local.** See [Identity and commit signing](#identity-and-commit-signing).

## What's inside

| Path | Installed to | Notes |
|---|---|---|
| `Brewfile` | n/a | `brew bundle`: Ghostty, shell tools, jj/jjui/difftastic, mise, just, Claude Code, redis-cli/kcat, grpcurl/xh/hurl/d2, k9s/kubectx/stern |
| `ghostty/config` | `~/.config/ghostty/config` | Catppuccin, 100MB scrollback, bell/notifications when an agent needs attention, split keybinds |
| `zsh/zshrc` | `~/.zshrc` | completions, autosuggestions, fzf, starship, zoxide, mise, sources the files below |
| `zsh/jj.zsh` | `~/.config/zsh/jj.zsh` | `jw` / `jwc` / `jws` / `jwl` / `jwrm` / `jpush`: workspace-per-agent helpers |
| `zsh/sign.zsh` | `~/.config/zsh/sign.zsh` | `sign-as work\|personal\|status`: per-repo commit identity and signing key |
| `zsh/infra.zsh` | `~/.config/zsh/infra.zsh` | `infra` command for the local stack |
| `zsh/zprofile.snippet` | appended to `~/.zprofile` | Homebrew PATH and mise shims for non-interactive shells |
| `infra/compose.yaml` | `~/.config/devinfra/compose.yaml` | Redis 8, Apache Kafka 4.1 (KRaft, single node), kafka-ui, Jaeger, published on loopback only |
| `mise/config.toml` | `~/.config/mise/config.toml` | global node (LTS), pnpm, gopls, delve, gotestsum, govulncheck |
| `starship/starship.toml` | `~/.config/starship.toml` | Catppuccin prompt with a jj segment (`custom.jj`) |
| `jj/config.toml` | `~/.config/jj/config.toml` | aliases `tug` `stack` `dft` `dshow`, `work()` revset, difftastic tool (no identity or signing: see `jj/identity.example.toml`) |
| `jj/identity.example.toml` | template for `~/.config/jj/conf.d/identity.toml` (local only, not tracked) | placeholders: name, work email, signing key, personal email/key scoped to `~/repos/personal` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | agent rules: jj instead of git, always `-m`, prefer just/mise tasks, local infra only, signed commits |
| `claude/statusline.sh` | `~/.claude/statusline.sh` | dir · [workspace] change description · model |
| `claude/settings.fragment.json` | merged into `~/.claude/settings.json` | read-only jj commands allowlisted (`--tool`/`--config` denied because they can run programs), `JJ_EDITOR=false`, statusLine |
| `SETUP_PROMPT.md` | n/a | paste into Claude Code to install and verify |

## At a glance

The core loop, with each step covered in [docs/GUIDE.md](docs/GUIDE.md):

```sh
jwc fix-login        # new jj workspace at <repo>-ws/fix-login, copy .env*, run setup, start claude
jws                  # fzf-switch between agent workspaces
jj stack             # review the stack (or jjui, jj dft)
jpush                # push the agent's latest work as a bookmark named after the workspace
jwrm fix-login       # remove the workspace; its changes stay in the repo
```

A new workspace runs `just setup`, or else `mise run setup`, or else `mise install` plus a lockfile install (pnpm/bun/yarn/npm/uv/poetry/go/bundler). Set `JW_NO_SETUP=1` to skip it.

### Local infra

Runs on Docker or OrbStack.

| Command | |
|---|---|
| `infra up` / `infra down` / `infra reset` | start and wait until healthy / stop, keep data / stop and delete data |
| `infra ps`, `infra logs -f kafka` | any `docker compose` subcommand |
| `infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --list` | Kafka CLI tools inside the broker |
| Endpoints | Redis `localhost:6379` · Kafka `localhost:9092` · kafka-ui http://localhost:8088 · Jaeger http://localhost:16686 · OTLP `:4317`/`:4318` |

MCP servers for Redis or Kafka belong in each project's `.mcp.json`, pointed at these local endpoints and read-only where the server supports it. Don't configure them globally, and never point them at production.

### Global vs per-project tools

- **Global** (`Brewfile`, `mise/config.toml`): inspection tools that behave the same everywhere, such as `redis-cli`, `kcat`, `grpcurl`, `xh`, `hurl`, `d2`, `k9s`, `kubectx`, `stern`, gopls and delve.
- **Per project**: anything that must match CI (`golangci-lint`, `biome`/eslint, `typescript`, `tsx`, `buf`) goes in the project's `mise.toml`, `package.json` or a `tool` directive in `go.mod`, so agents use the project's version.
- **Go** comes from the official installer, and the `toolchain` line in each `go.mod` picks the version.

## Identity and commit signing

The repo contains no identity. Your name, emails and signing settings live in `~/.config/jj/conf.d/identity.toml`, which jj loads automatically and which stays on your machine (mode 600). With a signing key configured, every commit you author is SSH-signed (`signing.behavior = "own"`), including agent-made ones.

On first run, if that file is missing, `install.sh` fills it from the first source available:

- **Environment variables:** with `DOTFILES_NAME` set, it reads your values from `DOTFILES_NAME`, `DOTFILES_EMAIL`, `DOTFILES_SIGNING_KEY`, `DOTFILES_PERSONAL_EMAIL`, `DOTFILES_PERSONAL_KEY`. Claude runs it this way from `SETUP_PROMPT.md`.
- **Interactive terminal:** it asks for your full name, default (work) email, default signing key (an SSH public key line, e.g. from the 1Password SSH agent, or a path to a `.pub` file), and optionally a personal email and key that apply to every repo under `~/repos/personal`.
- **Neither:** it copies `jj/identity.example.toml` there for you to edit.

`--dry-run` only reports what it would do.

It then mirrors the identity into git where git has none: user/email, SSH signing (`gpg.format ssh`, `commit.gpgsign`, `tag.gpgsign`), `~/.config/git/allowed_signers`, and `~/.config/git/personal.gitconfig` with an `includeIf` for `~/repos/personal/`.

Still manual: add your public key(s) on GitHub as **Signing keys**. In a repo, `sign-as status` shows which email and key it will use, and `sign-as personal|work` overrides that one repo.

## Gotchas

- Claude Code inherits `PATH` from the shell that launches it. `cd` into the project first (`jwc` does this) so mise picks the right tool versions. They stay fixed for that session.
- difftastic is opt-in on purpose. When piped without color its output has no `+`/`-` markers, so agents misread it.
- `JJ_EDITOR=false` in the Claude settings makes `jj describe` without `-m` fail fast instead of hanging an agent.
- mise trust in the main checkout extends to git worktrees, so jj workspaces don't need to be trusted again.
- On macOS, Ghostty also reads `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` *after* the XDG config. `install.sh` moves it aside.
- Paths assume Homebrew at `/opt/homebrew` (Apple Silicon). On Intel, change `HOMEBREW_PREFIX` in `zsh/zshrc` and the path in `zsh/zprofile.snippet`.
- The global `` cmd+` `` quick terminal needs Accessibility permission for Ghostty.
- Agent workspaces need a jj repo. In an existing git repo, run `jj git init --colocate` once.

## Requirements

- macOS on Apple Silicon
- [Homebrew](https://brew.sh) at `/opt/homebrew`
- Docker or OrbStack, for `infra`
- An SSH signing key, for signed commits
- Go from the official installer, if you work in Go
