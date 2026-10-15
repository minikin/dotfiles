# Shell commands

The zsh functions this repo defines, and the two zoxide commands `zshrc`
sets up. `<x>` is required, `[x]` is optional.

| Command            | Defined in       | Arguments            | Does                                                          |
| ------------------ | ---------------- | -------------------- | ------------------------------------------------------------- |
| `jw`               | `zsh/jj.zsh`     | `<name> [rev]`       | Create or reuse a workspace at `<repo>-ws/<name>`, `cd` into it. |
| `jwc`              | `zsh/jj.zsh`     | `<name> [rev]`       | `jw`, then start `claude` there.                              |
| `jws`              | `zsh/jj.zsh`     | none                 | Pick a workspace with fzf and `cd` into it.                   |
| `jwl`              | `zsh/jj.zsh`     | none                 | `jj workspace list`.                                          |
| `jwrm`             | `zsh/jj.zsh`     | `[name...]`          | Remove workspaces. fzf multi-pick without arguments.          |
| `jpush`            | `zsh/jj.zsh`     | `[bookmark]`         | Push `work()` as a bookmark named after the workspace.        |
| `sign-as`          | `zsh/sign.zsh`   | `[work\|personal\|status]` | Show this repo's commit identity, or switch it between the main and the second identity. |
| `infra`            | `zsh/infra.zsh`  | `[subcommand] [args...]` | Drive the local Docker stack.                             |
| `reload`           | `zsh/reload.zsh` | none                 | Check every config, then restart zsh. Tells you to press `cmd+shift+,` for Ghostty. |
| `navi-trust`       | `zsh/navi.zsh`   | none                 | Load this repo's `.navi/` workflows from now on.              |
| `navi-untrust`     | `zsh/navi.zsh`   | none                 | Stop loading this repo's `.navi/` workflows.                  |
| `z`                | zoxide           | `<query...>` or `-`  | Jump to the best-matching directory you visited.              |
| `zi`               | zoxide           | `[query...]`         | Pick a directory with fzf.                                    |

| Variable      | Read by | Effect                                                         |
| ------------- | ------- | -------------------------------------------------------------- |
| `JW_NO_SETUP` | `jw`, `jwc` | Any non-empty value skips the env-file copy and project setup on a new workspace. |
| `NAVI_DEFAULT_PATH` | `zsh/navi.zsh` | navi's default cheats folder, first in `NAVI_PATH`. Default `~/.local/share/navi/cheats`. |
| `NAVI_TRUST_FILE` | `zsh/navi.zsh` | The trusted-repos list. Default `~/.config/navi/trusted-repos`. |
| `DOTFILES_PERSONAL_DIR` | `zsh/navi.zsh` | The second identity's folder, set from `~/.config/dotfiles/config`. Repos inside it are trusted without `navi-trust`. Unset with one identity. |
| `DOTFILES_DIR` | `navi/dotfiles.cheat` | Where the dotfiles repo is cloned, set from `~/.config/dotfiles/config`. |

## Workspace layout

A workspace for repo `~/repos/app` named `fix-login` lives at
`~/repos/app-ws/fix-login`: next to the main checkout, never inside it. The
main checkout is the workspace named `default`. `jw` and `jwrm` first find
the main checkout with `jj workspace root --name default`, so they work the
same from the main checkout and from inside any workspace.

Outside a jj repo `jw` and `jwrm` print `not in a jj repo` and return 1. In a
git repo without jj they print
`git repo without jj — run: jj git init --colocate`. `jwl`, `jws` and
`jpush` call `jj` directly and show jj's own error instead.

## jw

```sh
jw <name> [rev]
```

| Argument | Default                                             |
| -------- | --------------------------------------------------- |
| `name`   | Required. Every `/` becomes `-`: `feat/login` is `feat-login`. |
| `rev`    | `trunk()`, or `@-` of the main checkout when `trunk() & ~root()` is empty (no remote trunk). |

If `<repo>-ws/<name>` already exists, `jw` prints `reusing <dir>` and `cd`s
into it. `rev` is ignored and setup does not run.

Otherwise it:

1. Creates `<repo>-ws/`.
2. If jj still lists a workspace with that name (its directory was deleted by
   hand), runs `jj workspace forget <name>` and `git worktree prune`.
3. Runs `jj workspace add --name <name> -r <rev> <dir>`. On failure it returns 1.
4. Unless `JW_NO_SETUP` is set, copies local env files and runs the project
   setup (below).
5. `cd`s into the workspace.

### Env files copied

Untracked files are not in a new working copy, so `jw` copies these from the
main checkout:

| Depth            | Patterns                                         |
| ---------------- | ------------------------------------------------ |
| Repo root        | `.env*`, `mise.local.toml`, `.mise.local.toml`   |
| One level down   | `.env*`, `mise.local.toml`                       |
| Two levels down  | `.env*`                                          |

Only regular files are copied, never anything under `node_modules/`, and
never over a file that already exists in the workspace (`cp -n`). Each copy
prints `copied <path>`.

### Project setup

Runs in a subshell inside the new workspace. The first match wins:

| Condition                                              | Runs                              |
| ------------------------------------------------------ | --------------------------------- |
| `justfile` or `Justfile` with a `setup` recipe         | `just setup`, nothing else        |
| `mise.toml` or `.mise.toml` with a `setup` task        | `mise run setup`, nothing else    |
| `mise.toml` or `.mise.toml` without one                | `mise install`, then the lockfile steps |
| Neither                                                | the lockfile steps                |

Lockfile steps. Only the first JavaScript lockfile found runs:

| File                         | Command                              |
| ---------------------------- | ------------------------------------ |
| `pnpm-lock.yaml`             | `pnpm install --frozen-lockfile`     |
| `bun.lock` or `bun.lockb`    | `bun install --frozen-lockfile`      |
| `yarn.lock`                  | `yarn install --frozen-lockfile`     |
| `package-lock.json`          | `npm ci`                             |

Each of the following runs when its file exists:

| File           | Command             |
| -------------- | ------------------- |
| `uv.lock`      | `uv sync`           |
| `poetry.lock`  | `poetry install`    |
| `go.mod`       | `go mod download`   |
| `Gemfile.lock` | `bundle install`    |

Each step prints `setup: <command>`. A failing step prints
`⚠ setup step failed: <command>` to stderr and the next step still runs. Setup
never makes `jw` fail.

## jwc

```sh
jwc <name> [rev]
```

`jw "$@" && claude`. Claude Code starts in the workspace directory, so it
inherits that directory's mise `PATH` (see
[Agents and PATH](../explanation/agents-and-path.md)). It honours
`JW_NO_SETUP` the same way.

## jws

```sh
jws
```

Lists `jj workspace list` in fzf with the prompt `workspace> `, showing only
the names. The preview runs
`jj -R <workspace root> --ignore-working-copy log -r "trunk()::@"` for the
highlighted workspace. Enter `cd`s into it. Esc leaves you where you are.

## jwl

```sh
jwl
```

Runs `jj workspace list`: each workspace name with its working-copy change.

## jwrm

```sh
jwrm [name...]
```

| Argument | Behaviour                                                              |
| -------- | ---------------------------------------------------------------------- |
| names    | Removes those workspaces. Every `/` becomes `-`, as in `jw`.            |
| none     | fzf multi-pick (`Tab` to mark, prompt `remove> `) over every workspace except `default`. Esc returns 1. |

If the current directory is inside `<repo>-ws/`, `jwrm` first `cd`s to the
main checkout. It then runs `jj workspace remove <names...>`. jj snapshots
each working copy into a commit and deletes the workspace directory, so the
changes stay in the repo and only ignored files (`node_modules`, `.env`,
build output) are lost. jj refuses to remove `default`.

## jpush

```sh
jpush [bookmark]
```

| Argument   | Default                                                         |
| ---------- | --------------------------------------------------------------- |
| `bookmark` | The name of the workspace whose working copy is `@`.            |

`jpush` refuses, with exit 1, when:

| Case                                                              | Message                                  |
| ----------------------------------------------------------------- | ---------------------------------------- |
| No argument in the `default` workspace, or no workspace name found | `usage: jpush <bookmark>`               |
| No argument and `@` is the working copy of more than one workspace | same                                     |
| The name matches a remote bookmark on `trunk()`, such as `main`   | `jpush: refusing to push to trunk/immutable bookmark '<name>'` |
| A bookmark with that name points at an immutable change           | same                                     |

Otherwise:

| Bookmark exists locally | Runs                                                        |
| ----------------------- | ----------------------------------------------------------- |
| No                      | `jj git push --named <name>=work()`                         |
| Yes                     | `jj bookmark set <name> -r 'work()'` then `jj git push -b <name>` |

`work()` is the newest non-empty mutable change below `@` (see
[jj configuration](jj-config.md#revset-aliases)), so the empty change that
`jj commit` leaves on top is never pushed. Slashes in the argument are kept:
`jpush feat/login` pushes `feat/login`.

## sign-as

```sh
sign-as [work|personal|status]
```

`work` is the main identity and `personal` the second identity, the one
`install.sh` sets up for the folder you chose. The names stay `work` and
`personal` whatever the two identities are for.

| Mode               | jj (`--repo` config)                                                 | git (`--local` config)                                                  |
| ------------------ | -------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `status` (default) | nothing                                                              | nothing                                                                 |
| `personal`         | sets `user.email`, `signing.key`, `signing.backends.ssh.program` (the key and program are unset instead when the second identity has no key) | sets `user.email`, `user.signingkey`, `gpg.ssh.program`, `core.sshCommand` |
| `work`             | unsets the same three, back to the main identity                     | unsets the same four                                                    |

`personal` reads its four values from `~/.config/git/personal.gitconfig`
(`user.email`, `user.signingkey`, `gpg.ssh.program`, `core.sshCommand`). With
one identity that file does not exist, and it returns 1 with
`no second identity set up: move ~/.config/jj/conf.d/identity.toml aside, re-run install.sh and answer yes to the second identity`.
It also returns 1 with `fill in <file> first` when `user.email` there is empty or the
placeholder `PERSONAL_EMAIL`. `core.sshCommand` is optional: when the file has
none, `sign-as personal` removes any per-repo `core.sshCommand` and git uses the
default ssh. `install.sh` never writes it. When the file has no
`user.signingkey`, the second identity has no key of its own, so `personal`
unsets the per-repo key and signer in jj and git and the main key signs.

jj per-repo config is shared by every workspace of the repo. The jj half is
skipped in a git repo without jj. Outside any repo, `sign-as` prints
`not in a repo` and returns 1. An unknown mode prints the usage line and
returns 1.

After `personal` or `work`, if the author email of `@` differs from the
configured `user.email`, `sign-as` runs `jj metaedit --update-author -r @` and
prints `updated author of @`.

Every mode ends with the effective identity, showing the last 12 characters
of each key:

```text
jj:  you@personal.example  key …personal.pub
git: you@personal.example  key …personal.pub
```

## infra

```sh
infra [subcommand] [args...]
```

Every form runs `docker compose -f ~/.config/devinfra/compose.yaml`, project
name `devinfra`.

| Form                       | Runs                                                    |
| -------------------------- | ------------------------------------------------------- |
| `infra`                    | `docker compose ... ps`                                 |
| `infra up [svc...]`        | `docker compose ... up -d --wait [svc...]`              |
| `infra reset`              | `docker compose ... down -v`. Deletes the data volumes. Extra arguments are ignored. |
| `infra kafka <script> [args...]` | `docker compose ... exec kafka /opt/kafka/bin/<script> [args...]` |
| `infra <anything else> [args...]` | `docker compose ... <anything else> [args...]`, such as `down`, `ps`, `logs -f kafka`, `restart kafka-ui` |

Services and their loopback endpoints:

| Service    | Image                            | Host port → container      | Endpoint                         |
| ---------- | -------------------------------- | -------------------------- | -------------------------------- |
| `redis`    | `redis:8`                        | `6379 → 6379`              | `redis://localhost:6379`         |
| `kafka`    | `apache/kafka:4.1.0` (KRaft)     | `9092 → 9092`              | `localhost:9092`                 |
| `kafka-ui` | `ghcr.io/kafbat/kafka-ui:latest` | `8088 → 8080`              | http://localhost:8088            |
| `jaeger`   | `jaegertracing/jaeger:latest`    | `16686`, `4317`, `4318`    | UI http://localhost:16686, OTLP gRPC `localhost:4317`, OTLP HTTP `localhost:4318` |

Every port is published on `127.0.0.1` and `[::1]` only. Redis data lives in
the `redis-data` volume and Kafka data in `kafka-data`. `infra down` keeps
them, `infra reset` removes them. Kafka creates new topics with 3 partitions.
`kafka-ui` starts once Kafka's health check passes.

## reload

```sh
reload
```

Applies changes to the dotfiles without opening a new tab. It checks first
and stops with exit 1 at the first problem, so a broken config never
replaces a working shell:

| Step | On failure |
| ---- | ---------- |
| `ghostty +validate-config`, when Ghostty is installed. On success prints `ghostty: config valid, press cmd+shift+, to apply it` | Ghostty's own error |
| `jj config list`, when jj is installed | `reload: jj config is invalid, see: jj config list` |
| `zsh -n` on `~/.zshrc` and every `~/.config/zsh/*.zsh` | `reload: syntax error in <file>, see: zsh -n <file>` |

Then it deletes `~/.zcompdump*`, so new completions load, prints
`zsh: restarting` and runs `exec zsh`. Shell variables you set by hand in
that shell are gone afterwards. Exported variables survive.

Ghostty is only checked, not reloaded: press `cmd+shift+,` (its
`reload_config` action). jj, mise and starship read their config on every
command or prompt and need nothing.

## navi-trust and navi-untrust

```sh
navi-trust
navi-untrust
```

Both act on the main checkout of the current repo, the parent of
`git rev-parse --git-common-dir`, so every jj workspace of a repo shares one
entry. Outside a git or jj repo they print `not in a git or jj repo` and
return 1.

| Command        | Does                                                                                   | Prints               |
| -------------- | -------------------------------------------------------------------------------------- | -------------------- |
| `navi-trust`   | Creates `~/.config/navi/` if needed and appends the main checkout's path to `trusted-repos`, unless the line is already there. | `trusted: <path>`    |
| `navi-untrust` | Removes that exact line from `trusted-repos`, if the file exists.                      | `untrusted: <path>`  |

Both then update `NAVI_PATH` at once. `zsh/navi.zsh` sets it on every `cd`
through a `chpwd` hook and once when it is sourced:

| Situation                                                        | `NAVI_PATH`                                          |
| ---------------------------------------------------------------- | ---------------------------------------------------- |
| In a trusted repo whose top level has a `.navi/` folder          | `$NAVI_DEFAULT_PATH:<top level>/.navi`               |
| Anywhere else                                                    | unset, so navi reads only its default folder          |

A repo is trusted when its main checkout is under `$DOTFILES_PERSONAL_DIR`,
the second identity's folder, or its path is a line of `trusted-repos`.
Symlinks in `$DOTFILES_PERSONAL_DIR` are resolved for the comparison. Repos
in that folder need no entry, and `navi-untrust` does not stop them loading.
Without a second identity the variable is unset, and only `navi-trust` adds
repos. `zsh/navi.zsh` returns
without defining anything when `navi` is not installed. See
[saved workflows](../guides/workflows.md#per-project-workflows).

## z and zi

`zshrc` runs `eval "$(zoxide init zsh)"`, which defines both.

| Form            | Behaviour                                                         |
| --------------- | ----------------------------------------------------------------- |
| `z <dir>`       | `cd` to a path, like `cd`.                                        |
| `z foo bar`     | `cd` to the highest-ranked visited directory matching `foo` then `bar`. |
| `z -`           | `cd` to the previous directory.                                   |
| `zi [query]`    | Pick from the matching directories in fzf.                        |

zoxide learns from every `cd`, so a directory has to be visited once before
`z` can find it.
