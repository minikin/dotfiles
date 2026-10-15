# Claude Code

`install.sh` sets up Claude Code in three places: the global rules in
`~/.claude/CLAUDE.md`, three scripts (`~/.claude/statusline.sh`,
`~/.claude/notify.sh` and `~/.claude/guard-push.sh`), and a merge of
`claude/settings.fragment.json` into `~/.claude/settings.json`. The rules and
the scripts are links into the repo. The settings are merged, so your own
settings and hooks stay. Why the shell matters for tool versions is explained in
[Agents and PATH](../explanation/agents-and-path.md).

## Global rules

`~/.claude/CLAUDE.md` links to `claude/CLAUDE.md`. It tells every agent to:

- answer, code and write commit messages in English, even when you write or
  dictate in Russian or Ukrainian
- in repos with `.jj/`, use jj for every write and git only for read-only
  commands (`git status`, `git diff`, `git log`, `git blame`)
- always pass `-m`, and never run anything that opens an editor or an
  interactive UI (`jj describe` without `-m`, `jj split` without paths,
  `-i`, `jj resolve`)
- run `jj undo` after a mistake
- never push, move or delete bookmarks unless asked, and stay inside its
  `<repo>-ws/<name>` workspace
- prefer `just` recipes and `mise run` tasks, and not install global toolchains
- use `infra`, `redis-cli`, `kcat`, `grpcurl`, `xh` and `hurl` only against
  local or dev endpoints, with no `FLUSHALL`, `FLUSHDB`, topic deletion or
  `infra reset` unless asked
- keep you as the author, add no `Co-Authored-By:` or other attribution
  trailer, never bypass signing, and stop and report when signing fails
- switch identity only with `sign-as`, and only when asked

Project rules go in the project's own `CLAUDE.md`. Claude Code reads both.

## Status line

`~/.claude/statusline.sh` prints the directory, the jj workspace and change,
the model, how full the context window is, and the session cost, separated
by `·`:

```text
~/repos/my-service-ws/fix-retry · [fix-retry] yxnm Add retry to the order consumer · Opus · 42% ctx · $1.23
```

The change part is the workspace name in brackets, the shortest change ID of
at least 4 characters, any bookmarks, `CONFLICT` when the change has
conflicts, and the first line of the description cut to 30 characters. An
empty change shows `(empty)`, a change with no description `(no desc)`. Outside a jj repo it shows `git:<branch>`
instead. Every jj call uses `--ignore-working-copy`, so the refresh never
snapshots the working copy or adds to the op log.

The context part comes from `context_window.used_percentage`. Early in a
session that field is `null`, and the script falls back to
`context_window.total_input_tokens` divided by
`context_window.context_window_size`. Before the first response both are
missing or 0 and the part is left out. The cost is
`cost.total_cost_usd` rounded to cents, Claude Code's estimate at list
price, and is left out while it rounds to `$0.00`. All four values come from
one `jq` call.

Test it from a shell:

```sh
echo '{"workspace":{"current_dir":"'$PWD'"},"model":{"display_name":"test"}}' | ~/.claude/statusline.sh
```

## Permissions

The settings fragment allows the read-only jj commands, so agents do not
prompt for them. Each one is allowed bare and with arguments, for example
`Bash(jj log)` and `Bash(jj log *)`:

```text
jj st, jj status, jj log, jj diff, jj show, jj op log, jj evolog,
jj workspace list, jj bookmark list, jj dft
```

It denies any jj command containing `--tool` or `--config`, with
`Bash(jj *--tool*)` and `Bash(jj *--config*)`, because both can run arbitrary
programs. The patterns match the command text, so `jj dft` passes even
though the alias expands to `--tool difft`.
Everything else, such as `jj commit` or `jj git push`, still asks.

When `install.sh` merges the fragment, keys from the fragment win, the
`permissions.allow` and `permissions.deny` lists and each event's list under
`hooks` are unioned with yours, and every other key is kept. The previous file is saved as
`settings.json.bak-<timestamp>`. After editing the fragment, run
`./install.sh` again.

## Notifications

With several agents in splits, a plain bell does not say which agent wants
you. The fragment runs `~/.claude/notify.sh` on two hook events, and the
notification's title is the name of the agent's directory: the workspace
name, such as `fix-retry`, or the repo name in the main checkout.

| Event          | When it fires                                                                    | Body                                     |
| -------------- | -------------------------------------------------------------------------------- | ---------------------------------------- |
| `Stop`         | Claude finished its turn.                                                        | `done`                                   |
| `Notification` | Matcher `permission_prompt\|elicitation_dialog\|elicitation_url_dialog\|agent_needs_input`: Claude waits for a permission or an answer, after about six seconds with no typing. | The hook's `message`, such as `Claude needs your permission to use Bash`, or `waiting for input` when it has none. |

`idle_prompt` is left out, because the `Stop` notification already said the
agent was done a minute earlier.

Hooks run without a controlling terminal and cannot write to `/dev/tty`. So
`notify.sh` prints `{"terminalSequence": "..."}` and Claude Code writes the
sequence to the terminal itself: an OSC 777 desktop notification, which
Ghostty shows, followed by a bell. The bell no longer shows a notification of
its own (`bell-features` has no `system`), but it still bounces the dock
icon, marks the tab title and flashes the split border. Claude Code writes
the sequence only in an interactive session that is on screen, never with
`-p`.

The fragment also sets `preferredNotifChannel` to `notifications_disabled`,
which turns off Claude Code's built-in notification, titled "Claude Code".
The hooks still fire. Without that you would get two notifications for each
prompt.

Try it from a shell. `JW_NOTIFY=print` prints `title|body` instead of the JSON:

```sh
echo '{"hook_event_name":"Stop","cwd":"'$PWD'"}' | JW_NOTIFY=print ~/.claude/notify.sh
```

## Push guard

The global rules tell agents never to push, and a `PreToolUse` hook on the
`Bash` tool enforces it for agents in workspaces. `~/.claude/guard-push.sh`
reads the command and the hook's `cwd`, and exits 2 when both hold:

- the command matches `git push` or `jj git push` at its start or after
  whitespace, `;`, `&` or `|`
- the nearest `.jj` above `cwd` holds `repo` as a file, which is how jj marks
  a second workspace

Exit 2 blocks the call, and Claude sees the message:

```text
blocked: agents in jj workspaces do not push; the user pushes from the main checkout with jpush/jland
```

The main checkout, where `.jj/repo` is a directory, and directories outside
jj may still push, after the usual permission prompt. The guard reads the
command text and nothing more. `echo git push` is blocked too, and a push
hidden in a script or written as `git -C dir push` gets through. It is a
backstop for the global rule, not a sandbox.

## `JJ_EDITOR=false`

The fragment sets `JJ_EDITOR` to `false` in Claude Code's `env`. A jj
command that would open an editor, such as `jj describe` without `-m`, runs
`false` as the editor and fails at once instead of leaving the agent waiting
on an editor it cannot see.

```text
$ jj describe
Error: Failed to edit description
```

## Start Claude Code from the project directory

Claude Code inherits `PATH` from the shell that starts it, and mise sets
`PATH` per directory. Start it from the project or workspace directory, and
the agent gets that project's tool versions for the whole session:

```sh
cd ~/repos/my-service-ws/fix-retry
claude
```

`jwc` does both steps. When an agent uses the wrong version, quit, `cd` into
the project, check with `mise current` and start `claude` again. A
`mise.toml` that changes mid-session needs a restart too.
