# Cheatsheet

One-page reference for this setup. `<x>` = required, `[x]` = optional. The full detail is in [shell commands](shell-commands.md), [keybindings](keybindings.md), [jj configuration](jj-config.md) and [install.sh](install-sh.md).

## Ghostty

| Key | Action |
|---|---|
| `` Cmd+` `` (global) | Toggle quick terminal (drops from top, works from any app) |
| `Cmd+D` / `Cmd+Shift+D` | New split right / down |
| `Cmd+Alt+H/J/K/L` | Go to split left / down / up / right |
| `Cmd+Shift+Enter` | Zoom current split (toggle) |
| `Cmd+Shift+E` | Equalize splits |
| `Cmd+Shift+S` | Write screen to a file and paste its path, to hand output to an agent |
| Left `Option` | Acts as `Alt`/Meta (needed for `Alt-C` and agent TUIs) |

A command that runs longer than 30s in an unfocused split sends a desktop notification and rings the bell.

## Shell

| Command / key | Action |
|---|---|
| `Ctrl-R` | fzf history search |
| `Ctrl-T` | fzf file picker, inserts path |
| `Alt-C` | fzf directory picker, `cd` into it |
| `cmd **<Tab>` | fzf completion, e.g. `vim **<Tab>`, `cd **<Tab>`, `kill -9 **<Tab>` |
| `z <dir>` / `z foo bar` | Jump to best-matching frecent dir |
| `z -` | Back to previous dir |
| `zi [query]` | Interactive dir picker (fzf) |

## Workflows (`zsh/navi.zsh`)

Guide: [Saved workflows](../guides/workflows.md).

| Command / key | Action |
|---|---|
| `Ctrl-G` | Open the navi palette, fill the arguments, insert the command at the prompt (never runs it) |
| `navi-trust` | Load this repo's `.navi/` workflows (repos under `$DOTFILES_PERSONAL_DIR`, the second identity's folder, are trusted already) |
| `navi-untrust` | Stop loading this repo's `.navi/` workflows |

## Agent workspaces (`zsh/jj.zsh`)

Workspaces live next to the repo at `<parent>/<repo>-ws/<name>`. Each is also a git worktree. Workflow: [Run parallel agents](../guides/parallel-agents.md).

| Command | Action |
|---|---|
| `jw <name> [rev]` | Create (or reuse) workspace and `cd` in. `rev` defaults to `trunk()`, or `@-` if no remote trunk. `/` in name becomes `-` |
| `jwc <name> [rev]` | `jw`, then start `claude` in it |
| `jws` | fzf-switch to a workspace (preview: `trunk()::@` log) |
| `jwl` | List workspaces (`jj workspace list`) |
| `jwrm [name...]` | Remove workspaces (fzf multi-pick if no args). Changes stay in the repo, only ignored files are lost |
| `jpush [bookmark]` | Push `work()` as a bookmark (default: workspace name). Creates it on first push, moves it forward after that. Refuses trunk and immutable names |
| `JW_NO_SETUP=1 jw <name>` | Skip auto-setup |

Auto-setup of a new workspace copies untracked `.env*` / `mise.local.toml` from the main checkout, then runs `just setup`, else `mise run setup`, else `mise install` + lockfile install (pnpm/bun/yarn/npm, `uv sync`, `poetry install`, `go mod download`, `bundle install`). A failed step warns and never blocks.

## jj daily

| Command | Action |
|---|---|
| `jj` / `jj log` | Log (bare `jj` = `log`) |
| `jj st` | Status of working copy `@` |
| `jj diff --git` | Diff of `@` in git format |
| `jj show [rev]` | Show a change |
| `jj describe -m "msg"` | Set description of `@` |
| `jj commit -m "msg"` | Finish `@`, start a new empty change on top |
| `jj new [rev]` | Start a new change (on `@` or `rev`) |
| `jj squash [paths]` | Move `@` (or paths) into its parent |
| `jj split -m "msg" <paths>` | Split `paths` out of `@` into a first change |
| `jj abandon [rev]` | Drop a change, rebase descendants onto its parent |
| `jj rebase -b @ -o <dest>` | Rebase current branch onto `dest` (`-d` is an alias of `-o`, also `-s`, `-r`) |
| `jj undo` | Revert the last jj operation |
| `jj op log` | Operation history (restore with `jj op restore <id>`) |
| `jj git fetch` | Fetch from remote |
| `jj bookmark set <name> -r <rev>` | Create or move a bookmark |
| `jj git push -b <name>` | Push a bookmark |
| `jj git push --named <name>=<rev>` | Create bookmark and push in one step |

Repo aliases (`jj/config.toml`):

| Alias / revset | Expands to | Use |
|---|---|---|
| `jj stack` | `log -r 'trunk()::@ \| @::'` | Your stack on top of trunk |
| `jj tug` | `bookmark move --from 'closest_bookmark(@)' --to 'work()'` | Move nearest bookmark up to latest work, then `jj git push` |
| `jj dft [args]` | `diff --tool difft` | Structural diff |
| `jj dshow [rev]` | `show --tool difft` | Structural show |
| `work()` | `heads(::@ & mutable() & ~empty())` | Latest non-empty change in your stack |
| `closest_bookmark(to)` | `heads(::to & bookmarks() & mutable())` | Nearest mutable bookmark (never trunk) |

## Review

| Command | Action |
|---|---|
| `jjui` | jj TUI (`?` for keys) |
| `jj dft` / `jj dshow [rev]` | difftastic diff / show |
| `git dft [args]` | difftastic for git (`-c diff.external=difft diff`) |

difftastic is opt-in. Agents use plain `jj diff --git`. See [Review and land agent work](../guides/review-and-land.md) and [why difftastic is opt-in](../explanation/design.md#why-difftastic-is-opt-in).

## Signing and identity

| Command | Action |
|---|---|
| `sign-as` / `sign-as status` | Show current jj + git email and key suffix |
| `sign-as personal` | Switch this repo (jj + git) to the second identity from `~/.config/git/personal.gitconfig`, also updates the author of `@`. Refuses when there is no second identity |
| `sign-as work` | Remove the per-repo override, back to the main identity |

The main identity applies everywhere. An optional second identity applies to every repo inside one folder you pick during install (`$DOTFILES_PERSONAL_DIR`, for example `~/src/personal`). On first run, `install.sh` prompts for full name, the email used in every repo and a signing key (SSH public key line or `.pub` path), then asks whether to use a second identity and, on yes, for its folder, email and key. It writes `~/.config/jj/conf.d/identity.toml`. Non-interactive: set `DOTFILES_NAME`, `DOTFILES_EMAIL`, `DOTFILES_SIGNING_KEY`, and for a second identity `DOTFILES_PERSONAL_DIR` and `DOTFILES_PERSONAL_EMAIL` (together, or it exits 2) plus optionally `DOTFILES_PERSONAL_KEY`. With neither a terminal nor those variables, it copies `jj/identity.example.toml` for hand editing (`--dry-run` writes no identity). git gets the same identity and SSH signing if it has none of its own. With a signing key, every commit you author is SSH-signed. See [Identity and signing](../guides/identity-and-signing.md).

## Local infra (`zsh/infra.zsh`)

Guide: [Local infrastructure](../guides/local-infra.md).

| Command | Action |
|---|---|
| `infra up [svc...]` | Start (detached), wait until healthy |
| `infra` / `infra ps` | Status |
| `infra logs -f [svc]` | Follow logs (any other `docker compose` subcommand passes through) |
| `infra down` | Stop, keep data |
| `infra reset` | Stop and DELETE data volumes |
| `infra kafka <script> [args]` | Run a Kafka CLI script inside the broker (`/opt/kafka/bin/`) |

| Service | Endpoint (loopback only) |
|---|---|
| Redis 8 | `redis://localhost:6379` |
| Kafka 4.1 (KRaft) | `localhost:9092` |
| kafka-ui | http://localhost:8088 |
| Jaeger UI | http://localhost:16686 |
| OTLP | `localhost:4317` (gRPC), `localhost:4318` (HTTP) |

```sh
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --list
infra kafka kafka-topics.sh --bootstrap-server localhost:9092 --create --topic demo
kcat -b localhost:9092 -L                               # metadata: brokers, topics, partitions
kcat -b localhost:9092 -C -t demo -o beginning -e       # consume all, exit at end
kcat -b localhost:9092 -C -t demo -o -10 -e -f '%k %s\n' # last 10 per partition, key + value
echo 'k1:hello' | kcat -b localhost:9092 -P -t demo -K:  # produce with key
redis-cli ping                                          # default host localhost:6379
redis-cli --scan --pattern 'session:*'                  # iterate keys (never KEYS * on big sets)
redis-cli monitor                                       # live command stream
```

## Go and TS tools (global via `mise/config.toml`)

| Tool | Typical use |
|---|---|
| `gopls` | Go language server for editors and agents, `gopls check <file.go>` |
| `dlv` | `dlv test ./pkg/x`, `dlv debug ./cmd/app -- <args>` |
| `gotestsum` | `gotestsum --format testname -- ./...`, `gotestsum --watch` |
| `govulncheck` | `govulncheck ./...` |
| `node` (LTS), `pnpm` (latest) | `pnpm install --frozen-lockfile`, `pnpm run <script>` |
| `mise` | `mise ls`, `mise install`, `mise tasks`, `mise run <task>` |
| `just` | `just --list`, `just <recipe>` |

Go itself comes from the official installer, and each project's `go.mod` `toolchain` picks the version. CI-pinned tools belong in the project, not globally. See [Per-project tools](../guides/project-tools.md).

## Kubernetes

| Command | Action |
|---|---|
| `k9s [-n ns] [--context ctx]` | Cluster TUI (`?` for keys, `:pods`, `:deploy`) |
| `kubectx` / `kubectx <ctx>` / `kubectx -` | List / switch / previous context |
| `kubens` / `kubens <ns>` | List / switch namespace |
| `stern <pod-regex> -n <ns> --since 10m` | Tail logs across pods (`-c <container>`, `-o json`) |

## APIs and diagrams

| Command | Action |
|---|---|
| `grpcurl -plaintext localhost:<port> list` | List services (needs reflection) |
| `grpcurl -plaintext -d '{"id":1}' localhost:<port> pkg.Svc/Method` | Call a method |
| `xh :8080/health` | GET `localhost:8080/health` |
| `xh post :8080/items name=x n:=1` | POST JSON (`:=` for non-string) |
| `hurl --test *.hurl` | Run HTTP test files (`--variable k=v`) |
| `d2 --watch in.d2 out.svg` | Render diagram with live preview |

## Claude Code integration (`claude/`)

Guide: [Claude Code](../guides/claude-code.md).

| Item | Detail |
|---|---|
| Status line | `dir · [workspace] change-id bookmarks CONFLICT description · model` (git branch outside jj). Read-only, never snapshots |
| Allowed without prompt | Read-only jj: `st`, `status`, `log`, `diff`, `show`, `op log`, `evolog`, `workspace list`, `bookmark list`, `dft` |
| Denied | `jj *--tool*`, `jj *--config*` |
| Env | `JJ_EDITOR=false`, so anything that opens an editor fails fast |

> **Agent etiquette**
> - Always pass `-m` (`jj describe -m`, `jj commit -m`, `jj split -m <paths>`). No editors, no `-i`, no `jj resolve`.
> - No git writes in jj repos (`commit`, `add`, `checkout`, `switch`, `rebase`, `stash`, `reset`, `branch`). Read-only git is fine.
> - Don't push or move bookmarks unless asked. Stay in your own workspace.
> - Point `redis-cli`, `kcat`, `grpcurl`, `xh`, `hurl` at local endpoints only, never staging or production.
> - Never run destructive infra commands unasked: `infra reset`, `FLUSHALL`/`FLUSHDB`, topic deletion.
