# Usage guide

Step-by-step workflows for this setup: installing it, running parallel Claude Code agents in jj workspaces, reviewing and landing their work, local infrastructure, and keeping it all up to date.

- [README.md](../README.md) is the overview: what each file is and where it is installed.
- [CHEATSHEET.md](../CHEATSHEET.md) is the one-page command reference.

This guide assumes macOS on Apple Silicon (Homebrew at `/opt/homebrew`).

## Contents

1. [Install on a new Mac](#1-install-on-a-new-mac)
2. [Enable a repo for agents, and the jj you need](#2-enable-a-repo-for-agents-and-the-jj-you-need)
3. [Run parallel agents](#3-run-parallel-agents)
4. [Review and land agent work](#4-review-and-land-agent-work)
5. [Commit identity and signing](#5-commit-identity-and-signing)
6. [Local infrastructure](#6-local-infrastructure)
7. [Per-project tools and MCP servers](#7-per-project-tools-and-mcp-servers)
8. [Claude Code integration](#8-claude-code-integration)
9. [Update the dotfiles](#9-update-the-dotfiles)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Install on a new Mac

### Prerequisites

- Homebrew. After installing it, make sure `brew` is on `PATH` for the current shell:

  ```sh
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ```

  The repo's `zshrc` adds it permanently. On Intel Macs, change `HOMEBREW_PREFIX` in `zsh/zshrc` and the paths in `zsh/zprofile.snippet` first.
- Docker (Docker Desktop or OrbStack) if you want the local infrastructure from [section 6](#6-local-infrastructure).
- Go comes from the official installer, not Homebrew or mise (see [section 7](#7-per-project-tools-and-mcp-servers)).

### Path A: manual

```sh
git clone https://github.com/minikin/dotfiles ~/repos/personal/dotfiles
cd ~/repos/personal/dotfiles
brew bundle                 # everything in Brewfile: ghostty, jj, jjui, mise, just, claude-code, ...
./install.sh --dry-run      # preview: lists every symlink and every file it would back up
./install.sh                # do it
exec zsh
```

What `install.sh` does (safe to re-run):

1. Symlinks the configs into `$HOME` (`~/.zshrc`, `~/.config/ghostty/config`, `~/.config/jj/config.toml`, `~/.config/mise/config.toml`, `~/.config/starship.toml`, `~/.config/zsh/*.zsh`, `~/.config/devinfra/compose.yaml`, `~/.claude/CLAUDE.md`, `~/.claude/statusline.sh`). Anything in the way is moved to `<file>.bak-<timestamp>`.
2. Moves aside `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`. Ghostty reads that file after the XDG config, so it would silently override it.
3. Appends the mise shims line (`zsh/zprofile.snippet`) to `~/.zprofile` if missing, so non-interactive shells (scripts, IDE tasks) also see mise tools.
4. Merges `claude/settings.fragment.json` into `~/.claude/settings.json`: keys from the fragment win (`env.JJ_EDITOR`, `statusLine`), permission `allow`/`deny` lists are unioned, everything else is kept. The old file is backed up first.
5. Sets up your commit identity (next step).
6. Copies `user.name`/`user.email` from jj into global git config if git has none, and adds a `git dft` alias (difftastic).
7. Validates the Ghostty config and clears the zsh completion cache.

### Commit identity: `~/.config/jj/conf.d/identity.toml`

Identity and signing are not in the repo. They live in a local-only file, `~/.config/jj/conf.d/identity.toml`, which jj loads in addition to `~/.config/jj/config.toml`.

On the first interactive run, if that file is missing, `install.sh` asks for:

| Prompt | Example of what to enter |
|---|---|
| Full name | `Jane Doe` |
| Default (work) email | `jane@work.example` |
| Signing key | an SSH public key line (`ssh-ed25519 AAAA...`, signed through an agent) or a path to a `.pub` file (signed with `ssh-keygen`). Empty means no signing |
| Personal email (optional) | `jane@personal.example`. Empty skips the personal identity |
| Personal signing key (optional) | public key line or `.pub` path. Empty means the same key as the default |

It then writes `conf.d/identity.toml` (mode 600). The personal email and key, if given, apply automatically to every repo under `~/repos/personal` (including its `<repo>-ws/` workspaces). A public key line uses the 1Password SSH agent's `op-ssh-sign` if 1Password is installed, otherwise `/usr/bin/ssh-keygen`.

On the same run it also sets up git to match, without overwriting anything git already has:

- Global SSH commit and tag signing with the default key, if git has no `user.signingkey` yet.
- Your public keys in `~/.config/git/allowed_signers`, so signatures verify locally.
- `~/.config/git/personal.gitconfig` plus an `includeIf "gitdir:~/repos/personal/"` in the global git config, if you gave a personal email.

To run without prompts (for example from Claude Code), pass the values as environment variables:

```sh
DOTFILES_NAME="Jane Doe" DOTFILES_EMAIL=jane@work.example \
DOTFILES_SIGNING_KEY=~/.ssh/id_ed25519_work.pub \
DOTFILES_PERSONAL_EMAIL=jane@personal.example DOTFILES_PERSONAL_KEY=~/.ssh/id_ed25519_personal.pub \
./install.sh
```

With no terminal and no `DOTFILES_NAME`, it copies `jj/identity.example.toml` into place instead. Replace the placeholders by hand before committing:

```sh
$EDITOR ~/.config/jj/conf.d/identity.toml
```

`--dry-run` only reports that it would create the file.

For commits to show as verified on GitHub, add each public key under GitHub Settings, SSH and GPG keys, as a **Signing key** (a key added only as an authentication key does not count).

`identity.toml` is never committed: it is not a symlink into the repo. To redo the prompts, delete it and run `./install.sh` again. See [section 5](#5-commit-identity-and-signing) for how identities are chosen per repo.

### Path B: let Claude Code do it

```sh
git clone https://github.com/minikin/dotfiles ~/repos/personal/dotfiles
cd ~/repos/personal/dotfiles
claude
```

Paste everything below the line in [`SETUP_PROMPT.md`](../SETUP_PROMPT.md). Claude then runs a preflight check, runs `brew bundle`, shows you the `./install.sh --dry-run` output and waits for your OK. It asks you for the identity values, passes them to `install.sh` as `DOTFILES_*` environment variables, runs the install, verifies everything, and does an end-to-end workspace test in a `mktemp -d` directory. It stops on the first error and never pushes.

### Verify

```sh
exec zsh
ghostty +validate-config                               # no output means OK
ghostty +list-fonts | grep 'JetBrainsMono Nerd Font Mono'
/usr/bin/time zsh -i -c exit                           # no errors, roughly 150 ms or less
type jw jwc jws jwl jwrm jpush sign-as infra z zi      # all defined
jj config get user.email                               # default (work) identity
git config --global user.email
jj --version; mise --version; just --version; jjui --version; difft --version
echo '{"workspace":{"current_dir":"'$PWD'"},"model":{"display_name":"test"}}' | ~/.claude/statusline.sh
```

The last command should print something like `~/repos/personal/dotfiles · xyzw main ... · test`.

### Manual steps afterwards

- Restart Ghostty and Claude Code.
- Give Ghostty Accessibility permission (System Settings, Privacy and Security, Accessibility) so the global `` cmd+` `` quick terminal works.
- Run `jj git init --colocate` in each repo you want to use with agents ([section 2](#2-enable-a-repo-for-agents-and-the-jj-you-need)).

---

## 2. Enable a repo for agents, and the jj you need

### Turn an existing git repo into a jj repo

```sh
cd ~/repos/my-service
jj git init --colocate
```

This adds a `.jj/` directory next to `.git/`. Both stay in sync: git tools, your IDE, CI, and `gh` keep working, and jj becomes the way you (and agents) write history. `git status` now shows a detached HEAD, which is normal.

If you run `jw` in a plain git repo, it tells you to run `jj git init --colocate` first.

### The mental model

- **No staging area.** Every file edit is automatically part of the working-copy change, `@`. There is no `add`.
- **Changes, not branches.** Each change has a stable change ID (for example `yxnm`) that survives rewrites. Bookmarks (jj's branches) are only needed when pushing.
- **Everything is undoable.** Each jj command is recorded in the operation log.

### The handful of commands an agent-heavy workflow needs

```sh
jj                      # bare jj = jj log (ui.default-command)
jj st                   # what changed in @
jj diff --git           # plain diff (what agents should read)
jj describe -m "Add retry to the order consumer"   # name the current change
jj commit -m "Add retry to the order consumer"     # name it AND start a new empty change on top
jj new                  # start a new change without describing the current one
jj squash               # fold @ into its parent
jj undo                 # revert the last jj operation
jj op log               # every operation, newest first
jj op restore <op-id>   # put the whole repo back to an earlier operation
```

A typical loop: edit files, `jj commit -m "..."`, edit again, `jj commit -m "..."`. Each commit leaves an empty `@` on top, ready for the next step.

Always pass `-m`. Commands that open an editor will fail for agents on purpose (`JJ_EDITOR=false`, [section 8](#8-claude-code-integration)).

### Revsets and aliases from `jj/config.toml`

| Name | Meaning |
|---|---|
| `work()` | Latest non-empty mutable change in your stack: where an agent's work actually is, even if `@` is an empty change on top |
| `closest_bookmark(@)` | Nearest mutable bookmark below `@` (never trunk) |
| `jj stack` | Log of just `trunk()::@ \| @::`, your stack on top of trunk |
| `jj tug` | Move `closest_bookmark(@)` up to `work()` |
| `jj dft` / `jj dshow` | `diff` / `show` through difftastic |

---

## 3. Run parallel agents

Each agent gets its own jj workspace. A workspace is a separate working directory with its own `@`, sharing the same repo (and it is a real git worktree, so git-based tools work inside it). Agents never trip over each other's files, and all their changes are visible from every workspace.

### Layout

Workspaces live next to the repo, never inside it:

```text
~/repos/
  my-service/                 # main checkout ("default" workspace)
  my-service-ws/
    fix-retry/                # workspace "fix-retry"
    add-metrics/              # workspace "add-metrics"
```

Slashes in names become dashes (`jw feat/login` creates `my-service-ws/feat-login`).

### Commands

| Command | What it does |
|---|---|
| `jwc <name> [rev]` | `jw`, then starts `claude` in the workspace |
| `jw <name> [rev]` | Create the workspace (or reuse it if it exists) and `cd` into it |
| `jws` | fzf picker over workspaces, with a log preview, then `cd` |
| `jwl` | List workspaces (`jj workspace list`) |
| `jwrm [name...]` | Remove workspaces. Without arguments, opens an fzf multi-picker. `cd`s you back to the main checkout if you are inside one |
| `jpush [bookmark]` | Push `work()` as a bookmark named after the workspace (see [section 4](#4-review-and-land-agent-work)) |

`rev` defaults to `trunk()` (for example `main@origin`). If the repo has no remote trunk, it uses `@-` instead. Start from somewhere else with, for example, `jw hotfix release-1.4@origin` or `jw followup fix-retry@` (on top of another agent's working copy).

### Example: three agents on one repo

```sh
cd ~/repos/my-service
jwc fix-retry          # split 1
# cmd+d in Ghostty, then:
cd ~/repos/my-service && jwc add-metrics
# cmd+shift+d, then:
cd ~/repos/my-service && jwc bump-deps
```

Each `jwc` prints something like:

```text
Created workspace in "../my-service-ws/fix-retry"
copied .env
setup: just setup
...
```

and drops you into Claude Code running in that directory.

### What runs when a workspace is created

`_jw_setup` makes a fresh workspace runnable. It never blocks: a failing step prints a warning and continues.

1. **Copy local env files** from the main checkout if they are not already present (untracked files are not in the new working copy). `node_modules` is skipped.
   - At the root: `.env*`, `mise.local.toml`, `.mise.local.toml`
   - One level down: `.env*`, `mise.local.toml`
   - Two levels down (monorepo packages): `.env*`
2. **Run the project's setup**, first match wins:
   1. `just setup` if there is a `justfile` with a `setup` recipe.
   2. `mise run setup` if there is a `mise.toml` with a `setup` task.
   3. Otherwise `mise install` (if there is a `mise.toml`), then lockfile installs:
      - `pnpm install --frozen-lockfile`, `bun install --frozen-lockfile`, `yarn install --frozen-lockfile` or `npm ci` (first lockfile found)
      - `uv sync` (`uv.lock`), `poetry install` (`poetry.lock`), `go mod download` (`go.mod`), `bundle install` (`Gemfile.lock`)

A project with special needs defines a `setup` recipe or task, which replaces the automatic steps entirely:

```just
# justfile
setup:
    mise install
    pnpm install --frozen-lockfile
    cp -n config/local.example.yaml config/local.yaml
```

Skip setup for a quick look:

```sh
JW_NO_SETUP=1 jw peek
```

Setup runs only when the workspace is created, not when `jw` reuses it. mise trust in the main checkout carries over to workspaces, so you are not asked to re-trust.

### Ghostty layout for agents

| Key | Action |
|---|---|
| `cmd+d` / `cmd+shift+d` | New split right / down |
| `cmd+alt+h/j/k/l` | Move between splits |
| `cmd+shift+enter` | Zoom the current split (toggle) |
| `cmd+shift+e` | Equalize splits |
| `cmd+shift+s` | Write the screen contents to a file and paste its path (hand long output to an agent) |
| `` cmd+` `` | Global quick terminal (drops down from the top) |

A practical layout: one tab per repo, the main checkout in the left split for review (`jjui`), and agents in splits to the right. Unfocused splits are dimmed. Left Option acts as Alt, which agent TUIs and fzf (`Alt-C`) need. Scrollback is 100 MB, so long agent sessions do not lose history.

### Notifications

Ghostty tells you when an agent needs attention:

- A bell from any split (for example, Claude Code waiting for input) triggers a system notification, a dock bounce, a marker in the tab title and a border flash.
- A command that runs longer than 30 seconds in an unfocused split sends a notification and a bell when it finishes.

Allow notifications for Ghostty in macOS System Settings the first time it asks.

### Cleaning up

```sh
cd ~/repos/my-service
jwrm fix-retry add-metrics      # or just `jwrm` to pick with fzf
```

jj snapshots the working copy before removing, so the agents' changes stay in the repo (`jj log` still shows them). Only ignored files are lost (`node_modules`, `.env`, build output). If you deleted a workspace directory by hand, `jw <same-name>` detects the stale entry, forgets it and recreates the workspace.

---

## 4. Review and land agent work

### See what agents did

From the main checkout, every workspace's working copy is visible as `<name>@`:

```sh
jj log                         # all workspaces show up, marked fix-retry@, add-metrics@, ...
jj stack                       # only your stack on top of trunk
jj diff --git -r fix-retry@    # what that agent has in its current change
jj dft -r fix-retry@-          # structural diff (difftastic) of the change below it
jj dshow <change-id>           # show one change with difftastic
jjui                           # interactive TUI: browse, diff, describe, squash, rebase
```

`git dft` is the git equivalent (`git dft main...HEAD`).

difftastic is opt-in because agents read diffs without colour, and without colour its side-by-side output has no `+`/`-` markers. Agents use `jj diff --git`, you use `jj dft`.

### Tidy up before pushing

Work from inside the agent's workspace (`jws`, pick it):

```sh
jj stack                               # check the stack
jj squash                              # fold a fix-up change into its parent
jj describe -r <change-id> -m "..."    # reword
jj abandon <change-id>                 # drop a change
jj rebase -d 'trunk()'                 # after `jj git fetch`, move the stack onto the latest trunk
```

### Push: `jpush`

```sh
jpush                 # inside workspace "fix-retry": pushes work() as bookmark "fix-retry"
jpush retry-backoff   # or choose the bookmark name
```

- First push: creates the bookmark at `work()` (`jj git push --named fix-retry=work()`).
- Later pushes: moves the bookmark forward to `work()` and pushes it (`jj bookmark set` + `jj git push -b`).
- `work()` is the latest non-empty change, so the empty `@` that `jj commit` leaves on top is never pushed.

Then open a pull request as usual, for example `gh pr create --head fix-retry`.

Guards:

- `jpush` refuses to push to a trunk bookmark (a workspace named `main`, for instance) or to any immutable bookmark, and asks for another name.
- In the `default` workspace it requires an explicit name: `jpush <bookmark>`.

### Push manually: `jj tug`

If the change already has a bookmark (for example, you checked out a PR branch):

```sh
jj tug           # move the nearest mutable bookmark up to work()
jj git push      # push it
```

`closest_bookmark` only considers mutable bookmarks, so `jj tug` never drags `main` onto agent work.

### After the merge

```sh
jj git fetch
jwrm fix-retry
```

---

## 5. Commit identity and signing

### How identity is chosen

| Where the repo is | Identity | Source |
|---|---|---|
| Anywhere (default) | Work | `[user]` and `[signing]` in `~/.config/jj/conf.d/identity.toml` |
| Under `~/repos/personal` (and its `-ws` workspaces) | Personal | A `--when.repositories = ["~/repos/personal"]` scope in the same file |
| A repo where you ran `sign-as` | Whatever you chose | Per-repo jj config and local git config |

Every commit you author is signed (`signing.behavior = "own"`), including commits agents make in your name and working-copy snapshots. Agents are told never to change identity or bypass signing ([section 8](#8-claude-code-integration)).

### Per-machine prerequisites

`install.sh` writes the config (identity.toml, git signing, `allowed_signers`, `personal.gitconfig`), but the keys themselves are per machine and never in the repo:

- The work signing key, either in an SSH agent (for example the 1Password SSH agent, signing through `op-ssh-sign`) or as a key file on disk.
- For personal repos, the personal key (for example `~/.ssh/id_ed25519_personal`, signed with `/usr/bin/ssh-keygen`).
- Both public keys added to GitHub as **Signing keys**.

`sign-as personal` reads `user.email`, `user.signingkey`, `gpg.ssh.program` and (optionally) `core.sshCommand` from `~/.config/git/personal.gitconfig`, and refuses to run until that file has a real `user.email`.

If you have no signing key yet, leave the key prompt empty (or remove the `[signing]` section from `identity.toml`) and add it later.

### `sign-as`: override per repo

```sh
cd ~/repos/side-project-outside-personal
sign-as status       # show the current jj and git identity and key (last 12 chars)
sign-as personal     # use the personal identity in this repo
sign-as work         # remove the override; back to the default
```

`sign-as personal|work` writes per-repo jj config (shared by all workspaces of that repo) and local git config, then updates the author of the current change `@` if it no longer matches. Example output:

```text
jj:  you@personal.example  key ...ersonal.pub
     updated author of @
git: you@personal.example  key ...ersonal.pub
```

---

## 6. Local infrastructure

`infra` wraps `docker compose -f ~/.config/devinfra/compose.yaml` (project name `devinfra`). All ports bind to loopback only (IPv4 and IPv6).

| Service | Endpoint |
|---|---|
| Redis 8 | `localhost:6379` |
| Apache Kafka 4.1 (KRaft, single node, 3 partitions per topic by default) | `localhost:9092` |
| kafka-ui | http://localhost:8088 |
| Jaeger UI | http://localhost:16686 |
| OTLP gRPC / HTTP (into Jaeger) | `localhost:4317` / `localhost:4318` |

### Lifecycle

```sh
infra up              # start everything, wait until healthy
infra up redis        # start only Redis
infra ps              # status (also what bare `infra` does)
infra logs -f kafka   # follow logs; any docker compose subcommand works
infra restart kafka-ui
infra down            # stop, keep data
infra reset           # stop and delete the data volumes (fresh Redis and Kafka)
```

### Redis

```sh
redis-cli ping                     # PONG
redis-cli set session:42 '{"user":1}' EX 300
redis-cli --scan --pattern 'session:*'
redis-cli monitor                  # watch every command your service sends
```

Redis Insight (installed by the Brewfile) connects to `localhost:6379` for a GUI.

### Kafka with the bundled CLI: `infra kafka ...`

`infra kafka <script> ...` runs `/opt/kafka/bin/<script>` inside the broker container:

```sh
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --create --topic orders --partitions 3
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic orders
infra kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
infra kafka kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group order-service
infra kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic orders --from-beginning
```

### Kafka with kcat (from the host)

```sh
kcat -b localhost:9092 -L                                   # brokers, topics, partitions
echo 'order-1:{"id":1,"total":42}' | kcat -b localhost:9092 -t orders -P -K:   # produce key:value
kcat -b localhost:9092 -t orders -C -o beginning -e         # consume everything, then exit
kcat -b localhost:9092 -t orders -C -o -5 -e \
  -f 'p%p o%o key=%k %s\n'                                  # last 5 per partition, with metadata
```

### kafka-ui

Open http://localhost:8088. The cluster is preconfigured as `local`, and dynamic config is enabled, so you can add clusters from the UI.

### Tracing with Jaeger

Point any OpenTelemetry SDK at the local collector:

```sh
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318   # HTTP; use :4317 for gRPC
export OTEL_SERVICE_NAME=my-service
```

Put these in the project's `mise.toml` `[env]` section so every shell and agent in that project gets them. Then open http://localhost:16686.

### Other inspection tools (all global)

`grpcurl` (gRPC), `xh` (HTTP), `hurl` (HTTP tests as files), `d2` (diagrams), `k9s`, `kubectx`, `stern` (Kubernetes).

Agents may use these only against local or dev endpoints, and never run destructive commands (`FLUSHALL`, topic deletion, `infra reset`) unless you ask.

---

## 7. Per-project tools and MCP servers

### The rule

- **Global** (`Brewfile`, `mise/config.toml`): tools that behave the same in every project, such as inspection and debugging tools, `node` (LTS), `pnpm`, `gopls`, `dlv`, `gotestsum` and `govulncheck`.
- **Per project**: anything whose version must match CI, such as linters, formatters, compilers and code generators. Put them in the project's `mise.toml`, `package.json`, or the `tool` directive in `go.mod`. Agents in that project then use exactly the version CI uses.
- **Go** comes from the official installer. Each `go.mod` `toolchain` line selects the version.

### Example `mise.toml`

```toml
[tools]
node = "22"
golangci-lint = "2.5.0"
biome = "2.2.4"
buf = "1.57.2"

[env]
OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318"

[tasks.setup]
run = ["mise install", "pnpm install --frozen-lockfile"]

[tasks.lint]
run = ["golangci-lint run ./...", "biome check ."]
```

```sh
mise trust          # once, in the main checkout (workspaces inherit it)
mise install
mise run lint
mise tasks          # list tasks
```

Because the file has a `setup` task, `jw` runs `mise run setup` in every new workspace.

For JavaScript tooling pinned in `package.json` (`typescript`, `tsx`, eslint), run it through the package manager (`pnpm exec tsc`). For Go tools, use the `tool` directive:

```sh
go get -tool github.com/bufbuild/buf/cmd/buf@v1.57.2
go tool buf lint
```

### MCP servers: per project, local, read-only

Add MCP servers for Redis, Kafka and similar per project, in a checked-in `.mcp.json`. Never add them globally, and never point them at production. Point them at the `infra` endpoints and enable read-only mode where the server supports it. The shape:

```json
{
  "mcpServers": {
    "redis-local": {
      "command": "<redis MCP server command>",
      "args": ["<flags for read-only mode>"],
      "env": { "REDIS_URL": "redis://localhost:6379" }
    }
  }
}
```

Or let Claude Code write it: `claude mcp add --scope project <name> -- <command> [args...]`. Claude Code asks you to approve project servers the first time it starts in that repo.

---

## 8. Claude Code integration

### Global rules: `~/.claude/CLAUDE.md`

Symlinked from `claude/CLAUDE.md`. It tells every agent to:

- In repos with `.jj/`:
  - use jj for all writes and only read-only git commands
  - always pass `-m`, never open editors or interactive UIs
  - use `jj undo` after a mistake
  - never push or move bookmarks unless asked
  - stay inside its workspace
- Prefer `just` recipes and `mise run` tasks, and not install global toolchains.
- Use the local infrastructure and inspection tools only against local or dev endpoints, with no destructive commands unless asked.
- Never change authorship, add attribution trailers, or bypass signing. Stop and report if signing fails. Switch identity only via `sign-as`, and only when asked.

Project-specific rules go in the project's own `CLAUDE.md`.

### Status line

`~/.claude/statusline.sh` shows `directory · [workspace] change-id bookmarks description · model`, for example:

```text
~/repos/my-service-ws/fix-retry · [fix-retry] yxnm Add retry to the order consumer · Opus
```

It shows `CONFLICT` if the change has conflicts and `(empty)` for an empty change. Outside jj repos, it shows `git:<branch>`. It uses `--ignore-working-copy`, so frequent refreshes never snapshot or add to the op log.

### Permissions

The settings fragment pre-allows read-only jj commands so agents do not prompt for them: `jj st`, `jj status`, `jj log`, `jj diff`, `jj show`, `jj op log`, `jj evolog`, `jj workspace list`, `jj bookmark list`, `jj dft`. It denies any jj command containing `--tool` or `--config`, because those can run arbitrary programs. Everything else (`jj commit`, `jj git push`, ...) still asks. Your existing allow and deny entries are kept when `install.sh` merges.

### `JJ_EDITOR=false`

Set in Claude Code's `env`. A jj command that would open an editor (`jj describe` without `-m`, `jj split` without paths) fails immediately instead of hanging the agent.

### Launch from the project directory

Claude Code inherits `PATH` from the shell that starts it, and mise sets `PATH` per directory. Always `cd` into the project first (`jwc` does this for you). The tool versions stay fixed for that session.

---

## 9. Update the dotfiles

After installation, the live config files are symlinks into the repo:

```sh
ls -l ~/.zshrc
# ~/.zshrc -> ~/repos/personal/dotfiles/zsh/zshrc
```

Editing `~/.zshrc`, `~/.config/ghostty/config` or `~/.config/jj/config.toml` edits the repo. Commit with jj:

```sh
cd ~/repos/personal/dotfiles
jj st
jj diff --git
jj commit -m "ghostty: bump font size"
jj bookmark set master -r @- && jj git push -b master   # @- is the change you just committed (this repo's branch is master)
```

The dotfiles repo is under `~/repos/personal`, so these commits use the personal identity automatically.

Exceptions:

- `~/.claude/settings.json` is merged, not linked. After changing `claude/settings.fragment.json`, run `./install.sh` again.
- `~/.zprofile` gets a one-time append. Edit `zsh/zprofile.snippet` and fix `~/.zprofile` by hand.
- `~/.config/jj/conf.d/identity.toml` is local only and never in the repo.

Pull updates on another machine:

```sh
cd ~/repos/personal/dotfiles
jj git fetch
jj new 'trunk()'
./install.sh               # picks up new files; existing links print "ok"
exec zsh
```

New packages in the `Brewfile` need `brew bundle`. New global mise tools need `mise install`. Reload Ghostty with `cmd+shift+,`.

---

## 10. Troubleshooting

**Wrong tool versions inside Claude Code** (for example the global `node` instead of the project's). Claude Code was started from another directory, or before `mise.toml` changed. Quit, `cd` into the project (or the workspace), and start `claude` again. Check with `mise current` in the same directory. If mise refuses the config, run `mise trust` in the main checkout.

**"The working copy is stale"** in a workspace (another workspace rewrote its change):

```sh
jj workspace update-stale
```

**Workspace directory deleted by hand.** Run `jw <name>` again. It forgets the stale entry, prunes the git worktree and recreates the workspace. To drop it entirely: `jj workspace forget <name>`, then `git worktree prune`.

**`jw`: "git repo without jj"**. Run `jj git init --colocate` in the main checkout.

**Setup failed in a new workspace.** Warnings start with `setup step failed:`, and the workspace is still created. Fix the cause, then run `just setup`, `mise run setup` or the install command in the workspace yourself.

**Ghostty ignores config changes.**

1. `ghostty +validate-config` to find typos.
2. Check that `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` does not exist (it overrides the XDG config, and `install.sh` moves it aside).
3. Reload with `cmd+shift+,`, or restart Ghostty. Some settings, such as `macos-option-as-alt`, only apply to new windows.
4. The quick terminal needs Accessibility permission.

**zsh starts slowly.**

```sh
/usr/bin/time zsh -i -c exit          # target: roughly 150 ms or less
rm -f ~/.zcompdump* && exec zsh       # rebuild a stale completion cache
zsh -i -x -c exit 2>&1 | tail -40     # trace startup to find the slow line
```

`HOMEBREW_PREFIX` is hardcoded to avoid running `brew --prefix` on every split. On Intel Macs, fix it in `zsh/zshrc`.

**Commit signing fails.** Check `sign-as status`, make sure the SSH agent is unlocked (1Password must be running for `op-ssh-sign`), and check that the key in `identity.toml` matches the agent's key. Agents are told to stop and report rather than work around it.

**`jpush` refuses.** You are pushing to trunk or an immutable bookmark, or you are in the `default` workspace without a name. Use `jpush <bookmark>`.

**Undo anything in jj.** `jj undo`, or `jj op log` and then `jj op restore <op-id>`.
