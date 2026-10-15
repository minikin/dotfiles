# Running parallel agents

Each agent gets its own jj workspace: a separate working directory with its
own `@`, sharing one repo. jj also registers it as a git worktree, so
git-based tools work inside it. Agents never edit each other's files, and
every change any of them makes is visible from every workspace. The repo has
to be a jj repo first, see [Getting started](../getting-started.md). In a
plain git repo `jw` stops with `git repo without jj — run: jj git init --colocate`.

[Review and land](review-and-land.md) covers what happens after the agents
finish. [A day with parallel agents](daily-routine.md) puts both into a
daily routine. Every command here is also listed in
[Shell commands](../reference/shell-commands.md).

## Layout

`jw` puts workspaces next to the repo, never inside it, in a directory named
`<repo>-ws`:

```text
~/repos/
  my-service/                 # main checkout, the "default" workspace
  my-service-ws/
    fix-retry/                # workspace "fix-retry"
    add-metrics/              # workspace "add-metrics"
```

Slashes in a name become dashes, so `jw feat/login` creates
`my-service-ws/feat-login` and a workspace named `feat-login`.

## Start one agent

```sh
cd ~/repos/my-service
jwc fix-retry
```

`jwc <name> [rev]` runs `jw <name> [rev]` and then `claude` in the new
directory. Arguments after the name and the optional `rev` go to `claude`,
so `jwc feat/login --permission-mode plan` starts in plan mode and
`jwc fix-retry --continue` reopens an existing workspace's last
conversation. Use `jw` alone when you want the shell without the agent. The
output from a repo with a `.env` at the root, a `pkg/.env` and a `justfile`
with a `setup` recipe:

```text
Created Git worktree for the new workspace.
Created workspace in "../my-service-ws/fix-retry"
Working copy  (@) now at: zmukqnrl 86dcdc9e (empty) (no description set)
Parent commit (@-)      : lrrkynqt 11d16843 main | init
Added 3 files, modified 0 files, removed 0 files
copied .env
copied pkg/.env
setup: just setup
```

`rev` defaults to `trunk()`, for example `main@origin`. When the repo has no
remote trunk, `jw` uses `@-` instead. Pass a revision to start elsewhere:

```sh
jw hotfix release-1.4@origin     # from a release branch
jw followup fix-retry@           # on top of another agent's working copy
```

Running `jw` with a name that already has a directory prints
`reusing <dir>` and changes into it. Setup does not run again.

## Three agents on one repo

Open one Ghostty split per agent, each started from the main checkout:

```sh
cd ~/repos/my-service && jwc fix-retry
# cmd+d for a split to the right, then:
cd ~/repos/my-service && jwc add-metrics
# cmd+shift+d for a split below, then:
cd ~/repos/my-service && jwc bump-deps
```

Keep the main checkout in the left split for review with `jjui`, one tab per
repo. The full key list is in [Keybindings](../reference/keybindings.md). The
ones that matter here:

| Key | Action |
|---|---|
| `cmd+d`, `cmd+shift+d` | New split right, new split down |
| `cmd+alt+h`, `j`, `k`, `l` | Move between splits |
| `cmd+shift+enter` | Zoom the current split (toggle) |
| `cmd+shift+e` | Equalize splits |
| `cmd+shift+s` | Write the screen to a file and paste its path, to hand long output to an agent |

`unfocused-split-opacity = 0.6` dims the splits you are not in.
`macos-option-as-alt = left` makes left Option send Alt, which agent TUIs and
fzf's `Alt-C` need. `scrollback-limit = 100000000` keeps 100 MB of history
per split.

## Notifications

Ghostty tells you when an agent needs attention, so you can leave the splits
unattended:

- When an agent finishes or waits for input, Claude Code sends a desktop
  notification titled with the workspace name, such as `fix-retry`, and rings
  the bell. See [Claude Code](claude-code.md#notifications).
- A bell from any split triggers a dock bounce, a marker in the tab title and
  a border flash (`bell-features = attention,title,border`).
- A command that runs longer than 30 seconds in an unfocused split sends a
  notification and a bell when it finishes
  (`notify-on-command-finish = unfocused`, `notify-on-command-finish-after = 30s`).

macOS asks once whether Ghostty may send notifications. Allow it.

## What a new workspace gets

Untracked files are not in a new working copy, so `jw` copies local env files
from the main checkout when they are not already present, skipping anything
under `node_modules`:

- at the root: `.env*`, `mise.local.toml`, `.mise.local.toml`
- one level down: `.env*`, `mise.local.toml`
- two levels down, for monorepo packages: `.env*`

Then it runs the project's setup. The first match wins:

1. `just setup`, if there is a `justfile` and `just --summary` lists a `setup` recipe.
2. `mise run setup`, if there is a `mise.toml` or `.mise.toml` with a `setup` task.
3. Otherwise `mise install`, if there is a `mise.toml` or `.mise.toml`, and
   then the lockfile installs, with or without mise:
   - one of `pnpm install --frozen-lockfile`, `bun install --frozen-lockfile`,
     `yarn install --frozen-lockfile` or `npm ci`, for the first of
     `pnpm-lock.yaml`, `bun.lock` or `bun.lockb`, `yarn.lock`, `package-lock.json`
   - `uv sync` for `uv.lock`, `poetry install` for `poetry.lock`,
     `go mod download` for `go.mod`, `bundle install` for `Gemfile.lock`

A failing step prints `⚠ setup step failed: <command>` and the workspace is
still created. Fix the cause and run the command yourself in the workspace.

A project with special needs defines its own `setup` recipe or task, which
replaces the automatic steps entirely:

```just
# justfile
setup:
    mise install
    pnpm install --frozen-lockfile
    cp -n config/local.example.yaml config/local.yaml
```

Set `JW_NO_SETUP` to skip both the copy and the setup, for a quick look:

```sh
JW_NO_SETUP=1 jw peek
```

`mise trust` in the main checkout carries over to its workspaces, so mise
does not ask again. [Project tools](project-tools.md) has examples of a
`mise.toml` with a `setup` task.

## Switch, list and remove

```sh
jwst                      # one row per workspace: change, behind trunk, pushed, conflicts
jws                       # fzf picker over workspaces, previews trunk()::@, then cd
jwl                       # jj workspace list
jwrm fix-retry add-metrics
jwrm                      # no arguments: fzf multi-picker, default is not offered
```

`jwrm` runs `jj workspace remove`, which snapshots the working copy and then
deletes the directory. The agent's changes stay in the repo and `jj log`
still shows them. Ignored files are lost: `node_modules`, `.env`, build
output. Running `jwrm` from inside one of the repo's workspaces moves you back
to the main checkout first.

`jwst` reads everything from the main checkout without loading any
workspace, so it never snapshots or disturbs a running agent.

## Keep workspaces on the latest trunk

```sh
jsync fix-retry add-metrics
jsync                     # no arguments: fzf multi-picker, default included
```

`jsync` fetches once, then takes the workspaces one at a time: it snapshots
the agent's unsaved edits, rebases the stack onto `trunk()` and runs
`jj workspace update-stale` in the workspace right after, so the agent does
not hit a stale working copy. A workspace already on the latest trunk is
skipped, and conflicts are reported and left for the agent. Run it while the
agents wait for input. [Shell commands](../reference/shell-commands.md#jsync)
lists every message.

## Recover a stale workspace

When another workspace rewrites the change a workspace is on, jj reports
that the working copy is stale. `jsync <name>` updates it as its first step.
Or update it from inside that workspace:

```sh
jj workspace update-stale
```

If the directory was deleted by hand, run `jw` with the same name. It finds
the registered workspace with no directory, runs `jj workspace forget <name>`
and `git worktree prune`, and creates the workspace again with setup:

```sh
cd ~/repos/my-service
jw fix-retry
```

To drop it without recreating it, run the two commands yourself:

```sh
jj workspace forget fix-retry
git worktree prune
```

[Troubleshooting](../troubleshooting.md) covers the other failure modes.
