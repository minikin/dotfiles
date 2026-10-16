# Shell commands

The zsh functions this repo defines, and the two zoxide commands `zshrc`
sets up. `<x>` is required, `[x]` is optional.

| Command            | Defined in       | Arguments            | Does                                                          |
| ------------------ | ---------------- | -------------------- | ------------------------------------------------------------- |
| `jw`               | `zsh/jj.zsh`     | `<name> [rev]`       | Create or reuse a workspace at `<repo>-ws/<name>`, `cd` into it. |
| `jwc`              | `zsh/jj.zsh`     | `<name> [rev] [claude args...]` | `jw`, then start `claude -n <repo>/<name>` there with the remaining arguments and `JW_NAME` set. |
| `jreview`          | `zsh/jj.zsh`     | `[name] [focus...]`  | A second, read-only Claude reviews the workspace's `trunk()..@`. fzf pick without a name. |
| `jnext`            | `zsh/jj.zsh`     | none                 | What to do next: one row per agent workspace that needs you, most urgent first. |
| `jwst`             | `zsh/jj.zsh`     | none                 | One row per workspace: latest change, commits behind trunk, pushed, conflicts. |
| `jsync`            | `zsh/jj.zsh`     | `[name...]`          | Fetch, then rebase workspaces onto trunk one at a time. fzf multi-pick without arguments. |
| `jws`              | `zsh/jj.zsh`     | none                 | Pick a workspace with fzf and `cd` into it.                   |
| `jwl`              | `zsh/jj.zsh`     | none                 | `jj workspace list`.                                          |
| `jwrm`             | `zsh/jj.zsh`     | `[name...]`          | Remove workspaces. fzf multi-pick without arguments.          |
| `jpush`            | `zsh/jj.zsh`     | `[bookmark]`         | Push `work()` as a bookmark named after the workspace.        |
| `jland`            | `zsh/jj.zsh`     | `[rev]`              | Move the trunk bookmark to `rev` (default `work()`) and push it. |
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
| `JW_NAME` | your app and tests | Set by `jwc` to the workspace name, in the environment of the `claude` it starts and every command that `claude` runs. Not exported to your shell, not written to a file. |
| `JW_HINT` | `zsh/jj.zsh` | `0` turns off the [repo-entry hint](#repo-entry-hint). Read when the file is sourced. |
| `JW_TINT` | `zsh/jj.zsh` | `0` turns off the background [tint](#tab-title-and-tint). The tab title stays. Read at every prompt. |
| `NO_COLOR` | `jwst`, `jws` | Any non-empty value prints workspace names without colour. |
| `CLICOLOR_FORCE` | `jwst` | `1` keeps the colour when the output is not a terminal. |
| `JW_WHERE` | starship | Exported by `zsh/jj.zsh` as `<repo>/<workspace>` in a jj workspace or git worktree, unset elsewhere. The prompt shows it. |
| `CLAUDECODE` | `zsh/jj.zsh` | Set by Claude Code in its shells. Any non-empty value turns off the repo-entry hint, the tab title and the tint. |
| `GHOSTTY_BIN` | `reload` | The Ghostty binary to validate the config with. Without it, `ghostty` on `PATH`, else `/Applications/Ghostty.app/Contents/MacOS/ghostty`. |
| `NAVI_CONFIG_YAML` | navi | Set by `zsh/navi.zsh` to the palette's column layout, unless it is already set or `${NAVI_CONFIG:-~/.config/navi/config.yaml}` exists. |
| `NAVI_DEFAULT_PATH` | `zsh/navi.zsh` | navi's default cheats folder, first in `NAVI_PATH`. Default `~/.local/share/navi/cheats`. |
| `NAVI_TRUST_FILE` | `zsh/navi.zsh` | The trusted-repos list. Default `~/.config/navi/trusted-repos`. |
| `DOTFILES_PERSONAL_DIR` | `zsh/navi.zsh` | The second identity's folder, set from `~/.config/dotfiles/config`. Repos inside it are trusted without `navi-trust`. Unset with one identity. |
| `DOTFILES_DIR` | `navi/dotfiles.cheat` | Where the dotfiles repo is cloned, set from `~/.config/dotfiles/config`. |

## Workspace layout

A workspace for repo `~/repos/app` named `fix-login` lives at
`~/repos/app-ws/fix-login`: next to the main checkout, never inside it. The
main checkout is the workspace named `default`. `jw`, `jws`, `jwst`, `jsync`, `jreview` and `jwrm` first find
the main checkout with `jj workspace root --name default`, so they work the
same from the main checkout and from inside any workspace.

Outside a jj repo `jw`, `jws`, `jwst`, `jsync`, `jreview` and `jwrm` print `not in a jj repo` and return 1. In a
git repo without jj they print
`git repo without jj — run: jj git init --colocate`. `jwl` and
`jpush` call `jj` directly and show jj's own error instead. Outside a jj
repo `jland` prints `jland: not in a jj repo` and returns 1. `jnext` behaves
differently, see [jnext](#jnext).

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
4. Adds the [agent pre-push hook](#agent-pre-push-hook) to the repo.
5. Unless `JW_NO_SETUP` is set, copies local env files and runs the project
   setup (below).
6. `cd`s into the workspace.

### Agent pre-push hook

`jw` writes a `pre-push` hook into the repo's shared git hooks
(`.git/hooks/pre-push` of the main checkout), which every workspace and git
worktree of the repo uses. The hook rejects a `git push` when `CLAUDECODE` is
set, so it comes from a Claude Code agent, and the push runs in a jj workspace
or git worktree. It catches what the [push guard](../guides/claude-code.md#push-guard)
cannot see, such as a push inside a script or a `just` recipe. Your own
pushes, and any push from the main checkout, go through.

The hook is marked with a `jw-pre-push` comment, and `jw` rewrites only a hook
with that mark. With a `pre-push` hook of your own, `jw` leaves it and prints
`jw: <path> is your own, not adding the agent push guard to it`. With
`core.hooksPath` set, `jw` adds nothing, because that directory usually
belongs to the project's hook manager.

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
jwc <name> [rev] [claude args...]
```

The second argument is the `rev` for `jw` unless it starts with `-` or
contains whitespace. Every argument after the name and the optional `rev`
goes to `claude`, so a quoted sentence becomes the agent's first prompt:

| Call | Runs |
| ---- | ---- |
| `jwc feat/x` | `jw feat/x && claude` |
| `jwc feat/x @-` | `jw feat/x @- && claude` |
| `jwc feat/x --permission-mode plan` | `jw feat/x && claude --permission-mode plan` |
| `jwc feat/x @- --continue` | `jw feat/x @- && claude --continue` |
| `jwc fix/x "fix the retry storm"` | `jw fix/x && claude "fix the retry storm"` |
| `jwc fix/x @- "fix the retry storm"` | `jw fix/x @- && claude "fix the retry storm"` |

A one-word task looks like a rev: `jwc fix/x cleanup` creates the workspace
at revision `cleanup`. Put a rev first or write the task as a sentence.

`claude` starts with `-n <repo>/<name>`, such as `-n my-service/fix-x`.
Claude Code shows that name in the tab title and in `/resume`, and
`claude -r my-service/fix-x` finds the session.

`claude` runs with `JW_NAME=<workspace name>` in its environment (`fix-x`
for `jwc fix/x`), and so does every command it runs. Prefix Kafka topics,
Redis keys and test databases with it, and two agents running the same tests
against the shared `infra` stack stay out of each other's data.

`jw` reuses an existing workspace, so `jwc <name> --continue` goes back to an
agent's last conversation. Claude Code starts in the workspace directory, so it
inherits that directory's mise `PATH` (see
[Agents and PATH](../explanation/agents-and-path.md)). It honours
`JW_NO_SETUP` the same way.

## jreview

```sh
jreview [name] [focus...]
```

| Argument | Behaviour |
| -------- | --------- |
| name     | The workspace to review. Every `/` becomes `-`, as in `jw`. An unknown name prints `jreview: no workspace named <name>` to stderr and returns 1. |
| none     | fzf pick (prompt `review> `) over every workspace except `default`. Esc returns 1. |
| focus    | Appended to the prompt after `Focus:`, for example `jreview feat-x "the retry logic"`. |

`jreview` finds the workspace directory from the main checkout with
`jj --ignore-working-copy workspace list`, as `jsync` does, so it works from
the main checkout or from any workspace. If
`jj -R <dir> diff -r 'trunk()..@' --name-only` lists no files, it prints
`jreview: <name> has no changes since trunk(), nothing to review` to stderr
and returns 1 without starting Claude. Otherwise it prints
`jreview: reviewing <name>, this takes a minute or two...` to stderr, because
`claude -p` shows nothing until the review is done. Then, in that directory
and in a subshell, so your own directory does not change:

```sh
claude -p "<prompt>" \
  --allowedTools 'Read,Grep,Glob,Bash(jj diff *),Bash(jj log *),Bash(jj show *)' \
  --disallowedTools 'Edit,Write,NotebookEdit'
```

The prompt asks for a review of `jj diff --git -r 'trunk()..@'` against the
code it touches, a list of problems by severity (blocking, should fix, nit)
with `file:line` for each, and no edits. `-p` prints the review and exits.
In `-p` mode a tool call that no rule allows is denied, not asked about, so
the reviewer can read files and run `jj diff`, `jj log` and `jj show`, and
nothing else. `Bash(jj diff *)` also matches a bare `jj diff`.

That check and the reviewer's `jj diff` snapshot the workspace like any jj command run in
it. Run `jreview` while the agent waits for input, not while it is writing
files, as with `jsync`.

## jws

```sh
jws
```

Lists `jj workspace list` in fzf with the prompt `workspace> `, showing only
the names. The preview runs
`jj -R <workspace root> --ignore-working-copy log -r "trunk()::@"` for the
highlighted workspace. Enter `cd`s into it. Esc leaves you where you are.
Each name except `default` is bold in its workspace's colour, the colour of
its [tint](#tab-title-and-tint) and status line. `NO_COLOR` turns that off.

## jwst

```sh
jwst
```

Prints a header and one row per workspace, in `jj workspace list` order,
with the columns aligned:

```text
WORKSPACE        CHANGE    BEHIND  PUSHED  CONFLICTS  DESCRIPTION
default          -              0  no      no         (no changes)
feat-export-csv  plkupkts       1  yes     no         feat(export): add CSV writer
fix-retry-storm  pvptytmu       0  no      yes        fix(consumer): retry with backoff
```

| Column | Value |
| ------ | ----- |
| `CHANGE` | Short change ID of the workspace's latest work, `heads(::<name>@ & mutable() & ~empty())`. `-` when there is none. |
| `BEHIND` | Number of commits in `::trunk() & ~::<name>@`. `0` means the workspace is on the latest trunk. |
| `PUSHED` | `yes` when the bookmark named after the workspace is on that change at `origin`. A bookmark pushed before the latest change, or before a rebase, shows `no`. |
| `CONFLICTS` | `yes` when `trunk()..<name>@` has a conflicted change. |
| `DESCRIPTION` | First line of the change's description, `(no description)` when empty, `(no changes)` when there is no change. |

On a terminal, each `WORKSPACE` name except `default` is bold in its
workspace's colour, as in `jws`. `CLICOLOR_FORCE=1` keeps the colour in a pipe,
and `NO_COLOR` turns it off.

Every query runs from the main checkout with `--ignore-working-copy` and
names the workspace as `<name>@`. `jwst` never opens a workspace's directory,
so it does not snapshot an agent's unsaved edits, sign anything or create an
operation. Unsaved edits are not in the row until the agent's next jj
command snapshots them. jj does not expose whether a workspace is stale
without loading it, so there is no stale column.

## jnext

```sh
jnext
```

Prints what to do next as aligned rows of workspace, state, command and a
note. One row per agent workspace that needs something, most urgent first,
then a `jwst` row. `default` never gets a row of its own:

```text
fix-retry-storm  conflicts     jws                    # jj st there, or tell its agent
feat-export-csv  behind trunk  jsync feat-export-csv  # rebase it onto trunk
docs-pass        not pushed    jpush                  # from its workspace, jws to get there
spike            no work       jwrm spike             # merged or abandoned
all              status        jwst                   # full table
```

Each workspace gets the first state that matches, in this order:

| State | When | Command |
| ----- | ---- | ------- |
| `conflicts` | `trunk()..<name>@` has a conflicted change | `jws`, then `jj st` there or tell its agent |
| `no work` | `heads(::<name>@ & mutable() & ~empty())` is empty: nothing on top of trunk | `jwrm <name>`. The work may have been merged or abandoned, `jnext` cannot tell which |
| `behind trunk` | `::trunk() & ~::<name>@` is not empty | `jsync <name>` |
| `not pushed` | the latest work has a description and the bookmark named after the workspace is not on it at `origin` | `jpush`, run from that workspace |

A workspace that matches none of these, such as an agent still working on
an undescribed change, gets no row. The rows are sorted by state:
conflicts, behind trunk, not pushed, no work. With no agent workspaces at
all, the first row is `-  no agents  jwc feat/<name> --permission-mode plan  # or Ctrl-G, start`.

| Where | Output |
| ----- | ------ |
| git repo without jj | one row, `-  git only  jj git init --colocate  # then jw and jwc work here`, exit 0 |
| Outside any repo | `jnext: not in a jj or git repo` on stderr, exit 1 |

Like `jwst`, every query runs from the main checkout with
`--ignore-working-copy`, so `jnext` snapshots nothing and creates no
operation.

### Repo-entry hint

`cd` into a main checkout that has agent workspaces prints one line:

```text
my-service: 3 agents · 1 behind trunk · conflicts · jnext
```

`behind trunk` counts the agent workspaces whose working copy is not on top
of `trunk()`. `conflicts` appears when any agent workspace has a conflicted
change in `trunk()..<name>@`. Each part is left out when it is zero. A repo
without agent workspaces prints nothing.

The hint runs three jj queries with `--ignore-working-copy`, the same three
however many agents there are, and takes about 60 ms. It fires once per repo
per shell, only in the main checkout (where `.jj/repo` is a directory), and
also for the directory a new shell starts in. `zsh/jj.zsh` registers it as a
`chpwd` hook only in an interactive shell, when `CLAUDECODE` is empty and
`JW_HINT` is not `0`.

## Tab title and tint

In an interactive shell, `zsh/jj.zsh` sets the tab title to where you are,
from [`where.sh`](../guides/claude-code.md#where-an-agent-works):
`<repo>/<workspace>` in a jj workspace or git worktree, the repo name in the
main checkout, and the `~`-relative directory outside a repo. While a command
runs, the title is followed by ` · ` and the first 40 characters of the
command. `ghostty/config` sets `no-title` in `shell-integration-features`,
because Ghostty's own title would overwrite this one.

In a workspace or worktree it also tints the split's background in the
workspace's colour, the same colour as its status line, so splits are easy to
tell apart. The tint is the Catppuccin colour at 12% over Mocha's background
in dark mode, and at 10% over Latte's in light mode. The mode is read from
macOS only when the tint changes, so after switching it, the next workspace
you enter gets the new shade. Leaving the workspace and exiting the shell
reset the background (OSC 111). `JW_TINT=0` turns the tint off.

The `chpwd` hook runs `where.sh` and sets `JW_WHERE` for the starship prompt,
but prints nothing. zsh also runs `chpwd` inside `$(...)` and `( ... )`, where
the escape codes would end up in the captured output, so it returns at once
in a subshell. The `precmd` hook writes the title and the tint before each
prompt, so a `cd` with its output redirected still tints. Control characters
in a command become spaces in the title. The hooks are registered only in an
interactive shell when `CLAUDECODE` is empty.

## jsync

```sh
jsync [name...]
```

| Argument | Behaviour |
| -------- | --------- |
| names    | Syncs those workspaces, in that order. Every `/` becomes `-`, as in `jw`. |
| none     | fzf multi-pick (`Tab` to mark, prompt `sync> `) over every workspace, `default` included. Esc returns 1. |

`jsync` runs `jj git fetch` once from the main checkout, and skips it when
the repo has no remote. A failed fetch prints
`jsync: fetch failed, using the trunk already fetched` to stderr and the sync
goes on. Then, for each workspace in turn:

1. If `::trunk() & ~::<name>@` is empty, prints `<name>: up to date`, or
   `<name>: up to date, conflicts left for the agent` when
   `trunk()..<name>@` has conflicts, and moves on.
2. `jj workspace update-stale` in the workspace, for one left stale by an
   earlier rebase. It does nothing in a fresh one.
3. `jj status` in the workspace, which snapshots the agent's unsaved edits.
4. `jj rebase -b <name>@ -d 'trunk()'` from the main checkout.
5. `jj workspace update-stale` in the workspace right away, so the agent
   finds it fresh.

Each workspace prints one line:

| Case | Line |
| ---- | ---- |
| Already on the latest trunk | `<name>: up to date` |
| Already on the latest trunk, with conflicts | `<name>: up to date, conflicts left for the agent` |
| Rebased cleanly | `<name>: rebased onto trunk` |
| Rebased with a conflict in `trunk()..<name>@` | `<name>: conflicts, left for the agent` |
| No such workspace, or its directory is gone | `<name>: no such workspace directory, run: jw <name>` on stderr |
| A step failed | `<name>: rebase failed` and jj's output on stderr |

A failed workspace does not stop the others, and `jsync` then returns 1.
When one workspace's stack
sits on another's, rebasing the lower one also moves the upper one and
leaves it stale until it is synced or runs `jj workspace update-stale`. Run
`jsync` while an agent waits for input, not while it is writing files.

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

## jland

```sh
jland [rev]
```

For repos without pull requests. Moves the trunk bookmark to `rev`, default
`work()`, and pushes it: `jj bookmark set <trunk> -r <rev>` then
`jj git push -b <trunk>`. The bookmark is the first remote bookmark on
`trunk()`, or `main` when there is none.

| Case | Result |
| ---- | ------ |
| Not in a jj repo | exit 1 with `jland: not in a jj repo` |
| `rev` has no description | exit 1 with `jland: <rev> has no description, run: jj describe -r '<rev>' -m "..."`, nothing moved |
| `rev` is behind the bookmark | jj refuses to move it backwards, exit 1, nothing pushed |

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
