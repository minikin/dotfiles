# Agents and PATH

Start Claude Code from the project directory, or with `jwc`, and it runs the
project's tool versions. Start it anywhere else and it may run the global
ones. This page explains why, and why the versions then stay fixed until
you restart it.

## Claude Code inherits PATH

Claude Code is an ordinary process. It gets its environment, `PATH`
included, from the shell that started it, and the commands its agent runs
start from that environment. It does not run your prompt hooks again for each
command.

In this setup `PATH` is not a fixed list. It depends on the directory the
shell was in when it last drew a prompt, because that is when mise rewrites
it.

## Two ways mise reaches PATH

`zsh/zshrc` runs:

```zsh
eval "$(mise activate zsh)"
```

This installs a zsh hook. Before each prompt, and after each `cd`, mise reads
the `mise.toml` files that apply to the current directory and rewrites
`PATH` so the directories of the pinned versions come first, and exports the
`[env]` variables. Leave the project and the next prompt takes them away. The
tool directories are on `PATH` directly, so running `node` costs nothing
extra, but only a prompt or a `cd` updates it.

`zsh/zprofile.snippet`, appended to `~/.zprofile`, runs:

```zsh
eval "$(/opt/homebrew/bin/mise activate zsh --shims)"
```

This puts mise's shims directory on `PATH` and installs no hook. A shim is a
small executable named after a tool. Each time it runs, it asks mise which
version applies to the current directory and runs that one. It works in
shells that never draw a prompt: scripts, IDE tasks, `zsh -c`. It costs a
mise lookup on every call, and it covers tools only, not `[env]`.

`.zprofile` runs for login shells and `.zshrc` for interactive ones. An
interactive login shell, which is what a Ghostty tab is on macOS, runs both,
and the hook's tool directories go ahead of the shims. A script started from
an IDE gets only the shims.

## What we verified

These were checked by hand on the machine this setup was built on, and the
code relies on each of them:

| Fact                                                                  | Where the setup relies on it                         |
| --------------------------------------------------------------------- | ---------------------------------------------------- |
| Claude Code inherits `PATH` from the shell that launches it.          | `jwc` `cd`s before it starts `claude`. The comment above `mise activate` in `zsh/zshrc` says so. |
| mise trust in the main checkout extends to git worktrees.             | `jw` runs `mise install` or `mise run setup` in a new workspace without a `mise trust` step. |
| Recovering a workspace whose directory was deleted by hand needs `jj workspace forget` and `git worktree prune`. | `jw` runs both before it adds the workspace again. |
| difftastic output misleads agents when piped.                         | `jj diff` stays plain, and difftastic is behind `jj dft`. |

The freeze below follows from the first fact and from how the hook works.

## The per-session freeze

Claude Code takes `PATH` once, at launch, from a shell that had already run
the mise hook for the directory it was in. Inside the session the agent's
commands never draw a prompt, so the hook never runs again. The versions in
effect at launch are the versions for the whole session.

Three consequences:

- **Launch from the project.** `cd` into the repo or workspace first, then
  run `claude`. `jwc <name>` does both, because `jw` ends with a `cd` into the
  workspace before `claude` starts.
- **Changing `mise.toml` needs a restart.** Pin a new version, run
  `mise install`, then quit Claude Code and start it again from the project.
  The running session keeps the old `PATH`.
- **One session per project.** An agent that `cd`s into a second project
  with other pins still has the first project's directories at the front of
  `PATH`. Give the second project its own session.

`mise run <task>` is the exception inside a session: mise sets up the
task's tools and `[env]` for the directory it runs in, whatever `PATH` the
session started with.

## Checking a session

In the same directory, outside Claude Code:

```sh
mise current       # the versions mise would use here
mise ls            # every installed version and where it came from
```

Inside Claude Code, ask the agent to run `which node` and `node --version`
(or the tool in question) and compare. If they differ, the session was
started somewhere else or before the last `mise.toml` change: quit, `cd`, and
start `claude` again. If mise refuses the config, run `mise trust` in the main
checkout.

Project tools that must match CI belong in the project's `mise.toml`,
`package.json` or `go.mod` `tool` directive, not in `mise/config.toml`. See
[Per-project tools](../guides/project-tools.md).
