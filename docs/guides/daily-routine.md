# A day with parallel agents

Start from what you want to do: build a feature, fix a bug, write an
architecture decision record, review a pull request. Each kind of work below
is a recipe: how to name the workspace, how to start the agent, what to tell
it and how to land the result. The routine around them (the morning fetch,
watching agents, cleaning up) comes after.

The recipes use commands that the other guides explain in detail:
[Parallel agents](parallel-agents.md) for workspaces,
[Review and land](review-and-land.md) for everything after an agent is done.
The examples use a repo at `~/repos/my-service`.

## The ground rules

- **One task, one workspace, one agent.** The workspace name becomes the
  directory, the jj workspace and the bookmark `jpush` pushes, so name it
  like a branch: `feat/export-csv` becomes `feat-export-csv`.
- **The main checkout is for you.** Start agents from it, review in it,
  never run an agent in it. One Ghostty tab per repo, the main checkout in
  the left split, one split per agent (`cmd+d` right, `cmd+shift+d` down).
- **Tasks that touch different code run well in parallel.** Two agents in
  the same file both finish, but the second one to merge gets a conflict.
- **Two or three agents per repo** is what you can still review.

## Recipes

### Build a feature

Plan first, code second. Start the agent in plan mode, where it reads the
code and proposes a plan but changes nothing:

```sh
cd ~/repos/my-service
jwc feat/export-csv --permission-mode plan
```

Tell it what the feature is for, not only what to build, and where you
expect it to live. Read the plan, correct it, and approve it when it looks
right. Then ask for the work in small steps, one `jj commit -m` per step with
a message such as `feat(export): add CSV writer`, so the result is a stack
you can review change by change.

While it works, follow along from the main checkout:

```sh
jj log -r 'trunk()::feat-export-csv@'    # its stack so far
jj dft -r feat-export-csv@-              # its last finished step
```

When it is done, let a second Claude read the change before you do:

```sh
jreview feat-export-csv
```

It reviews `trunk()..feat-export-csv@` read-only and prints problems by
severity with file and line. Paste the ones you agree with to the agent,
then review the result yourself and land it as described in [Land the
result](#land-the-result). Run `jreview` while the agent waits for input:
its `jj diff` snapshots the workspace like any jj command.

### Fix a bug

A bug fix starts with a test that fails. Give the task with the command
line and the agent starts on it at once:

```sh
jwc fix/retry-storm "consumer retries without backoff after a broker restart, see the log in #142"
```

Give the agent the symptom and everything you have: the error, the log
line, the request that triggers it, the version where it started. Ask it to
write a failing test first and stop. Review that test from the main
checkout before it fixes anything:

```sh
jj dft -r fix-retry-storm@-
```

A test that reproduces the bug is half the review. Then let it fix the code,
run the tests, and commit the fix on top of the test. Run
`jreview fix-retry-storm` before your own review of the fix.

For a fix that must go onto a release branch rather than trunk, start the
workspace from that branch:

```sh
jj git fetch
jwc hotfix/1.4-timeout release-1.4@origin
```

### Write an architecture decision record

An ADR is a document, so the agent researches and drafts, and you decide.
Start it in plan mode so the research step cannot change code:

```sh
jwc adr/event-store --permission-mode plan
```

Give it the decision to make, the constraints (load, team, budget,
deadlines) and the options you already know about. Ask it to read the code
the decision affects and the existing records first, so it follows the
repo's format and numbering (often `docs/adr/` or `docs/decisions/`). Once
the plan is approved, it writes the record with context, the options with
their trade-offs, the decision and its consequences, and commits it as
`docs(adr): ...`.

Edit the draft yourself once the agent is done, then push it with `jpush`
and open a pull request: the review of an ADR is the discussion.

### Explore or prototype

For a question about the code ("how does auth reach this handler?") or a
throwaway spike:

```sh
jwc spike/grpc-streaming
```

When the answer is all you need, drop its changes and then the workspace,
from the main checkout:

```sh
jj abandon 'trunk()..spike-grpc-streaming@'
jwrm spike-grpc-streaming
```

`jj abandon` comes first, while `<name>@` still exists. Keep the
spike's findings by asking the agent to write them into the pull request or
issue you are working from.

### Review someone else's pull request

Check out the branch in a workspace of its own, so your other agents are not
disturbed:

```sh
jj git fetch
jwc review/pr-123 their-branch@origin
```

Ask the agent to review the change against `trunk()` (`jj diff --git -r
'trunk()..@'`), to run the tests and to list problems by severity with file
and line. Its notes go into the pull request through you. Remove the
workspace with `jwrm review-pr-123` when you are done.

### Answer review comments on your own pull request

Go back to the workspace that made the change. Its agent still has the
context:

```sh
jwc fix-retry-storm --continue    # reuses the workspace, resumes its last conversation
```

Paste the comments, let it fix them in new changes, and run `jpush` again.
It moves the bookmark forward and the pull request updates.

## Land the result

When the agent is done, review in the main checkout first
(`jj dft -r <name>@-`, or `jjui` to browse). Then switch into its workspace:

```sh
jws                    # pick the workspace
jj stack               # its changes on top of trunk
jj squash              # fold @ into its parent, if needed
jj describe -r <change> -m "fix(consumer): retry with backoff"
jj git fetch && jj rebase -d 'trunk()'   # or jsync <name> from the main checkout
jpush                  # pushes work() as the bookmark named after the workspace
gh pr create --head fix-retry-storm
```

After the merge:

```sh
cd ~/repos/my-service
jj git fetch
jwrm fix-retry-storm
```

## The day around the recipes

### Morning

```sh
cd ~/repos/my-service   # prints: my-service: 3 agents · 1 behind trunk · conflicts · jnext
jj git fetch
jnext                  # what needs you, most urgent first
jwst                   # workspaces left over from yesterday, one row each
```

Entering the repo prints a one-line hint when it has agent workspaces.
`jnext` turns it into commands: one row per workspace that needs something,
conflicts first, then behind trunk, not pushed and no work left. Run the
command on its row, or `jwst` for the full table.

`jwst` shows each workspace's latest change, how many commits it is behind
trunk, whether that change is pushed and whether it has conflicts. It only
reads the repo, so it is safe while agents work.

Remove the ones whose pull requests merged with `jwrm <name>`. After a
squash merge, their original changes stay in `jj log` on top of the old
trunk, and `jj abandon <change>` drops them.

A workspace you keep working on should start from the latest trunk:

```sh
jsync fix-retry-storm add-metrics    # or jsync alone to pick with fzf
```

`jsync` fetches once, then for each workspace snapshots the agent's unsaved
edits, rebases its stack onto `trunk()` and runs `jj workspace update-stale`
in it right away, so the agent never meets `The working copy is stale`. It
prints one line per workspace: `up to date`, `up to date, conflicts left
for the agent`, `rebased onto trunk`, or `conflicts, left for the agent`. Leave conflicts to the agent, `jj st` in
the workspace lists them. Run `jsync` while the agents wait for input, not
while they are writing files.

To come back to yesterday's agent, `jwc <name> --continue` reuses the
workspace without running setup and picks up the last conversation there.

### While agents work

You do not have to watch the splits. When an agent finishes or waits for
input, Claude Code sends a macOS notification titled with its workspace name
and rings the bell, which marks the tab, and a command over 30 seconds
in an unfocused split notifies when it ends. The status line in each agent
shows its workspace, change and description.

Leave the files in an agent's workspace to the agent. Tell it what to change
instead. All agents share the local infra from `infra up`. `jwc` starts
each agent with `JW_NAME` set to its workspace name, so an app or test that
creates Kafka topics or Redis keys can prefix them with `$JW_NAME`, and two
agents running the same tests do not read each other's messages.
`cmd+shift+s` writes the screen to a file and pastes its path, to hand long
output from one split to another agent.

After a merge, run `jsync` for the agents that are still running, as in
the morning, so their conflicts show up now and not at their own merge. Pick
a moment when they wait for input. `jwst` shows which ones are behind.

### Evening

Nothing has to be shut down. Workspaces are directories and survive a
reboot, and the agents' changes are already in the repo.

```sh
jwst                   # what is still open, and what is behind trunk
jwrm                   # fzf multi-picker: drop the ones you gave up on
infra down             # stop Redis and Kafka, keep their data
```

## When something goes wrong

| Symptom | Fix |
|---|---|
| A workspace says its working copy is stale | `jj workspace update-stale` inside it |
| You deleted a workspace directory by hand | `jw <name>` recreates it |
| A rebase or squash went wrong | `jj undo`, or `jj op log` and `jj op restore <op>` |
| An agent uses the wrong tool versions | [Troubleshooting](../troubleshooting.md), and [Agents and PATH](../explanation/agents-and-path.md) |
| A commit is signed with the wrong identity | `sign-as status`, then [Identity and signing](identity-and-signing.md) |

Press `Ctrl-G` and type `start` for the recipe openers above (feature, bug
fix, ADR, spike, continue, drop a spike), or any other command in this guide you do not
type every day. See
[Saved workflows](workflows.md).
