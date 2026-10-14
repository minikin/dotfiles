# Reviewing and landing agent work

Review from the main checkout, tidy the stack from inside the agent's
workspace, push it with `jpush`, then clean up after the merge. The revsets
and aliases used below are defined in `jj/config.toml` and listed in
[jj config](../reference/jj-config.md). Starting the agents is covered in
[Parallel agents](parallel-agents.md).

## See what the agents did

Every workspace's working copy shows up in the main checkout as `<name>@`:

```sh
cd ~/repos/my-service
jj log                         # fix-retry@, add-metrics@, ... all appear
jj stack                       # only your stack on top of trunk
jj diff --git -r fix-retry@    # what the agent has in its current change
```

`jj stack` is `jj log -r 'trunk()::@ | @::'`. Run it inside a workspace to
see that agent's stack and nothing else.

An agent that ran `jj commit` leaves an empty `@` on top of its work, so the
change you want is often `fix-retry@-`. The `work()` revset finds it in
either case: `heads(::@ & mutable() & ~empty())`, the latest non-empty
mutable change below `@`.

For a structural diff, use difftastic:

```sh
jj dft -r fix-retry@-          # jj diff --tool difft
jj dshow <change-id>           # jj show --tool difft
git dft main...HEAD            # git -c diff.external=difft diff
```

`install.sh` adds the `git dft` alias when `difft` is on `PATH`. The
difftastic aliases are opt-in because agents read diffs without colour, and
difftastic's side-by-side output has no `+` or `-` markers to fall back on.
Agents use `jj diff --git`.

For browsing, describing, squashing and rebasing interactively, run `jjui` in
the main checkout. It is installed by the `Brewfile`.

## Tidy the stack

Switch into the agent's workspace with `jws` and pick it, then:

```sh
jj stack                               # check the stack
jj squash                              # fold @ into its parent
jj describe -r <change-id> -m "Add retry to the order consumer"
jj abandon <change-id>                 # drop a change
jj git fetch
jj rebase -d 'trunk()'                 # move the stack onto the latest trunk
```

Always pass `-m`. If something goes wrong, `jj undo` reverts the last
operation, and `jj op log` with `jj op restore <op-id>` goes back further.

## Push with `jpush`

Inside the workspace, `jpush` pushes `work()` as a bookmark named after the
workspace:

```sh
jpush                 # in workspace "fix-retry": pushes work() as "fix-retry"
jpush retry-backoff   # or name the bookmark yourself
```

The first push creates the bookmark with `jj git push --named fix-retry=work()`.
Later pushes move it forward with `jj bookmark set fix-retry -r 'work()'` and
then run `jj git push -b fix-retry`. The empty `@` that `jj commit` leaves on
top is never pushed, since `work()` skips it.

`jpush` refuses in three cases, and exits 1 without pushing:

- In the `default` workspace without a name it prints `usage: jpush <bookmark>`.
  Pass the bookmark explicitly.
- When the name is one of the remote bookmarks on `trunk()`, for example a
  workspace named `main`.
- When the name is an existing bookmark that is `immutable()`.

The last two print:

```text
jpush: refusing to push to trunk/immutable bookmark 'main' — pass another name: jpush <bookmark>
```

Then open the pull request as usual:

```sh
gh pr create --head fix-retry
```

## Push a branch that already has a bookmark

When the change already sits on a bookmark, for example a checked-out pull
request branch, move that bookmark up to your latest work and push it:

```sh
jj tug
jj git push
```

`jj tug` is `jj bookmark move --from 'closest_bookmark(@)' --to 'work()'`.
`closest_bookmark(to)` is `heads(::to & bookmarks() & mutable())`, so it never
picks `main` or another immutable bookmark and never drags trunk onto agent
work. When the bookmark is already at `work()` it prints
`No bookmarks to update.`

## Land on `main`

After the pull request merges, fetch and remove the workspace:

```sh
cd ~/repos/my-service
jj git fetch
jwrm fix-retry
```

`jwrm` keeps the agent's changes in the repo. Once the merge is fetched they
are part of `trunk()` or, after a squash merge, can be dropped with
`jj abandon`.

In a repo without pull requests, land directly by moving `main` to the
change and pushing it:

```sh
jj bookmark set main -r 'work()'
jj git push -b main
```

Without `--allow-backwards`, `jj bookmark set` only moves `main` forward.
Run `jj git fetch` and `jj rebase -d 'trunk()'` first, so the change sits on
top of the latest `main`.
