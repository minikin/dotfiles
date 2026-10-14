# Claude Code

`install.sh` sets up Claude Code in three places: the global rules in
`~/.claude/CLAUDE.md`, the status line script `~/.claude/statusline.sh`, and
a merge of `claude/settings.fragment.json` into `~/.claude/settings.json`.
The first two are links into the repo. The third is merged, so your own
settings stay. Why the shell matters for tool versions is explained in
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
and the model, separated by `·`:

```text
~/repos/my-service-ws/fix-retry · [fix-retry] yxnm Add retry to the order consumer · Opus
```

The change part is the workspace name in brackets, the shortest change ID of
at least 4 characters, any bookmarks, `CONFLICT` when the change has
conflicts, and the first line of the description cut to 30 characters. An
empty change shows `(empty)`, a change with no description `(no desc)`. Outside a jj repo it shows `git:<branch>`
instead. Every jj call uses `--ignore-working-copy`, so the refresh never
snapshots the working copy or adds to the op log.

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
`permissions.allow` and `permissions.deny` lists are unioned with yours, and
every other key is kept. The previous file is saved as
`settings.json.bak-<timestamp>`. After editing the fragment, run
`./install.sh` again.

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
