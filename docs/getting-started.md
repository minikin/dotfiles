# Getting started

The steps below assume the setup is installed. See [Install](install.md).
They run two agents on one repo, `~/repos/my-service`, from start to merge.

## 1. Turn the repo into a jj repo

Agent workspaces are jj workspaces, so the repo needs jj. In an existing git
repo, once:

```bash
cd ~/repos/my-service
jj git init --colocate
```

This adds `.jj/` next to `.git/` and keeps both in sync. Git, `gh`, your IDE
and CI work as before. `git status` now reports a detached HEAD, which is
normal in a colocated repo. If you skip this step, `jw` stops with
`git repo without jj` and the command to run.

## 2. Start the first agent

```console
$ jwc fix-retry
Created workspace in "../my-service-ws/fix-retry"
copied .env
setup: just setup
```

`jwc` creates the workspace at `~/repos/my-service-ws/fix-retry` on top of
`trunk()`, which is `main@origin` in most repos. It copies the untracked
`.env*` and `mise.local.toml` files from the main checkout, since a new
working copy has only tracked files. Then it runs the project's setup:
`just setup` if the `justfile` has that recipe, else `mise run setup`, else
`mise install` and a lockfile install such as `pnpm install
--frozen-lockfile` or `go mod download`. A failed step prints a warning and
does not stop the workspace from being created. Last, it starts Claude Code
in the new directory, so mise puts the project's tool versions on `PATH`.

Give the agent its task as usual.

## 3. Start the second agent in a split

Press `cmd+d` for a split to the right, and start another agent:

```bash
cd ~/repos/my-service
jwc add-metrics
```

`cmd+alt+h` and `cmd+alt+l` move between the splits, and `cmd+shift+enter`
zooms one. When an agent stops to ask you something, it rings the bell, and
Ghostty shows a notification and flashes the split's border. The
[parallel agents](guides/parallel-agents.md) guide has a layout for three or
more.

## 4. Read the status line

Each Claude Code session shows its directory, workspace, change and model at
the bottom. Right after `jwc`, the working copy is empty:

```text
~/repos/my-service-ws/fix-retry · [fix-retry] tkvs (empty) · Opus
```

Once the agent has described its change with `jj describe -m` or
`jj commit -m`, the description takes its place:

```text
~/repos/my-service-ws/fix-retry · [fix-retry] yxnm Add retry to the order consumer · Opus
```

A bookmark on the change shows after the change ID, and a change with
conflicts shows `CONFLICT`. The status line reads the repo with
`--ignore-working-copy`, so it never snapshots files or adds to the
operation log.

## 5. Review from the main checkout

Press `cmd+shift+d` for a split below and stay in `~/repos/my-service`.
Every workspace's working copy shows up there as `<name>@`:

```bash
jj log                          # fix-retry@ and add-metrics@ among the changes
jj stack                        # only your stack on top of trunk
jj diff --git -r fix-retry@     # the agent's current change
jj dft -r fix-retry@-           # the change below it, through difftastic
jjui                            # browse, diff and squash interactively
```

After `jj commit -m`, the agent's working copy is a fresh empty change and
its work sits one below, at `fix-retry@-`. The `work()` revset finds the
latest non-empty change for you, and `jpush` uses it.
[Review and land](guides/review-and-land.md) covers squashing, rewording and
rebasing the stack before you push.

## 6. Push and open a pull request

Go back to the agent's split, or switch to its workspace with `jws`, then:

```bash
jpush
gh pr create --head fix-retry
```

`jpush` pushes `work()` as a bookmark named after the workspace, `fix-retry`.
The first push creates the bookmark, and later pushes move it forward. It
refuses to push to `main` or any other trunk or immutable bookmark, and in
the `default` workspace it wants a name: `jpush <bookmark>`.

## 7. Clean up after the merge

```bash
cd ~/repos/my-service
jj git fetch
jwrm fix-retry add-metrics
```

`jwrm` removes the workspaces, and `jwrm` with no arguments picks them with
fzf. jj snapshots each working copy first, so the agents' changes stay in the
repo and `jj log` still shows them. Only ignored files go with the
directory: `node_modules`, `.env` and build output.

From here, [parallel agents](guides/parallel-agents.md) covers starting a
workspace from another revision and skipping setup with `JW_NO_SETUP=1`, and
the [cheatsheet](reference/cheatsheet.md) fits on one page.
