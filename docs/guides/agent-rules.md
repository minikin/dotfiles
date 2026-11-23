# Agent rules for Claude, Codex and agy

Claude Code, Codex and Antigravity (`agy`) read one shared rules file,
`agents/AGENTS.md`, plus a short part of their own. `install.sh` links it
into place for each tool, adds a hook that keeps agy from launching
`claude` or `codex` on an API key, and links `agent-preflight`, a check to
run before a session with sub-agents.

## Where each tool's rules come from

| Tool   | Live file              | Links to           | Gets the shared rules through                     |
| ------ | ---------------------- | ------------------ | ------------------------------------------------- |
| Claude | `~/.claude/CLAUDE.md`  | `claude/CLAUDE.md` | `@../agents/AGENTS.md`, resolved next to the repo file |
| Codex  | `~/.codex/AGENTS.md`   | `agents/AGENTS.md` | the file itself                                   |
| agy    | `~/.gemini/GEMINI.md`  | `agy/GEMINI.md`    | `@[Shared agent rules](~/.config/dotfiles/AGENTS.md)`, a link to `agents/AGENTS.md` |

Each tool's part holds what only applies to it, such as its commit rule.
Codex has no include syntax, so its own rules sit in the "Codex only"
section at the end of the shared file. agy resolves a relative include next
to the link in `~/.gemini/`, not next to the repo file, which is why its
include names a fixed home path.

Edit the repo files. The live files are links, so the next session picks up
the change. agy caps a rule file at 24,000 bytes after includes, and
`tests/rules.bats` keeps `agy/GEMINI.md` plus the shared file under it.

## Check that each tool loads the shared rules

The shared file has one line no other file has:
`Shared rules marker: agents-rules-3f9c2a71`. Ask each tool for it from an
empty directory, so no project file can answer, and read the trace to see
that it answered without opening a file:

```sh
cd "$(mktemp -d)"
env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude -p --tools "" --output-format stream-json --verbose \
  'Quote the line that starts with "Shared rules marker:".'
env -u OPENAI_API_KEY -u CODEX_HOME codex exec --ephemeral --skip-git-repo-check -s read-only --json \
  'Quote the line that starts with "Shared rules marker:".'
agy --output-format stream-json -p \
  'Quote the line that starts with "Shared rules marker:". Then list your skills whose name contains rex.'
```

Each must quote the marker with no tool call in its output: no `tool_use`
event for Claude, no command or file-read item for Codex, no tool step for
agy. agy's answer must also name `rex-orchestrator`.

Once agy passes, `~/Desktop/antigravity-instructions.md` and
`~/.gemini/SUBSCRIPTION-AGENTS.md` are no longer read by anything.
`install.sh` prints a note for each, and you delete them.

## The agy launch guard

`agy/guard-agents.zsh` is an agy `PreToolUse` hook, registered in
`~/.gemini/config/hooks.json` under the name `dotfiles-agent-guard`. It
reads the command of `run_command` and the text `manage_task` sends to a
running process. It denies:

- `op run` wrapping `claude` or `codex`
- setting `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `OPENAI_API_KEY` or
  `CODEX_HOME` in any form, including `export` and `launchctl setenv`
- `codex login --with-api-key`
- any `claude` or `codex` launch without its own prefix:
  `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude ...` or
  `env -u OPENAI_API_KEY -u CODEX_HOME codex ...`. Only these exact commands
  need no prefix: `claude --version`, `claude -v`, `claude --help`,
  `claude -h`, `claude auth status` (with `--json` or `--text`),
  `codex --version`, `codex -V`, `codex --help`, `codex -h` and
  `codex login status`. A prompt such as `claude "auth status, then ..."` is a
  launch.

It looks through `;`, `&&`, pipes, `&`, `if` and loop bodies, functions,
subshells, comments, heredocs, `$(...)` and backticks anywhere (also in
redirect targets and array elements), `env`, `nohup`, `timeout`, `bash -c`
strings, Codex's global options before `login`, and the command after `--`
in `rex new`, `rex window new`, `rex run` and `rex split`. A Rex tab gets
the Rex server's environment, not agy's, so a prefix in front of `rex`
itself does not count.

A `rex send` message can land in an agent tab or in a plain shell, which
runs each line. So each line of the message is denied only when it is itself
a forbidden launch: its first command runs `claude` or `codex` without the
prefix, `op run` wrapping one of them, or `codex login --with-api-key`, or the
line sets one of the four variables and launches `claude` or `codex`. Prose
that names these mid-sentence, such as "Use codex --help for examples",
passes. A line that starts with `claude` or `codex` is read as a launch. A
`$(...)` in the `rex send` command line itself is checked as well.

Input it cannot inspect is denied: anything but exactly one JSON object, a
missing or malformed tool name, a missing command, a
`run_command` command that does not parse, nesting deeper than eight levels,
and the `shell_exec` and `send_command_input` tools, whose payloads are not
known yet. Text `manage_task` types into a running process that does not
parse, such as a message with one apostrophe, is checked by its tokens
instead of denied: a shell would not run it past the broken quote. It never
answers `allow`, so agy's own permission prompts still apply.

It is a guard rail, not a sandbox. It does not see a command word held in a
variable (`c=claude; $c`), `eval`, aliases, a script file that launches an
agent, or an MCP tool that starts processes.

To check that it fires with `--dangerously-skip-permissions`, run in an empty
git repo:

```sh
agy --dangerously-skip-permissions -p 'Run exactly: env ANTHROPIC_API_KEY=dummy-not-a-key claude --version'
```

agy must report `tool call denied by pre-tool hook`. If the hook did not
fire, the worst outcome is `claude --version` printing its version.

## Start-of-session checks

```sh
agent-preflight            # one ok or FAIL line per check, exit 1 on any FAIL
agent-preflight --limits   # also the Codex weekly limit
```

| Check                 | How                                                        |
| --------------------- | ---------------------------------------------------------- |
| Moshi paired          | `moshi-hook status` shows `status: paired`                 |
| Rex answering         | `rex --autostart=false whoami --json` exits 0              |
| No API-key variables  | none of the four is set in the shell or in `launchctl getenv`. A missing or failing `launchctl` is a `FAIL`, not `ok` |
| Claude subscription   | `claude auth status`: logged in, `authMethod` `claude.ai`  |
| Codex subscription    | `codex login status` says `Logged in using ChatGPT`        |
| Codex limit           | `--limits`: `account/rateLimits/read` through `codex app-server`, the window that is 10,080 minutes long, primary or secondary |

Claude has no command that prints its usage limits. `/usage` inside a
session shows them. The script prints names, never values, and never the
email or the Moshi host name.
