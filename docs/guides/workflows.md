# Saved workflows (navi)

`Ctrl-G` opens a palette of saved commands, the same idea as Warp
Workflows. You pick one, fill its arguments from pickers that list live
data (your jj changes, Kafka topics, pods in a namespace), and the finished
command lands in the prompt. Nothing runs until you press Enter.

The palette is [navi](https://github.com/denisidoro/navi), installed from
the `Brewfile` and tested with navi 2.24. The commands live in `navi/*.cheat`
in this repo.

## Open it

Press `Ctrl-G` at a zsh prompt. `zsh/zshrc` sources `zsh/navi.zsh`, which
loads navi's zsh widget with `eval "$(navi widget zsh)"`.

1. Type a few words of the description, such as `abandon` or `kafka lag`.
2. Press Enter on the entry.
3. navi asks for each `<argument>` in turn. Where the cheat has a picker,
   you get an fzf list. Otherwise you type the value.
4. The command is inserted into the prompt. Read it, edit it, press Enter.

Some entries call the zsh functions from this repo (`jw`, `jwc`, `jwrm`,
`jpush`, `jland`, `infra`). They work through `Ctrl-G` because the command ends up in your
zsh prompt. Running plain `navi` in a terminal picks and runs the command
in a subshell, where those functions do not exist, so use `Ctrl-G`.

`zsh/navi.zsh` also sets the palette's column widths through
`NAVI_CONFIG_YAML`: a narrow group column, 40% for the description and the
rest for the command, so long commands are not cut off. It leaves them alone
when you have a navi config file of your own (`navi info config-path`).

If `Ctrl-G` opens another app instead, that app has a global shortcut on the
same key and macOS gives it the key first. Change the shortcut in that app.

Ghostty has no key for the palette. In a split where Claude Code runs, keys
go to Claude Code, not zsh, so a Ghostty binding would do nothing useful
there.

## What ships

`install.sh` links `navi/` to `~/.local/share/navi/cheats/dotfiles`, inside
navi's default cheats folder (`navi info cheats-path` prints it).

The palette holds commands that are worth searching for: ones with a
picker (a change, a workspace, a topic, a pod) or a command line you would
not type from memory (revsets, templates, Kafka flags, `kubectl` jsonpath).
Short commands such as `jj undo`, `jj squash`, `jws`, `jwrm` or `infra up`
are left out, because typing them is faster than finding them.

Each description starts with a verb and the thing it acts on, so type what
you want to do: `review agent`, `tail kafka`, `debug pod`. The first column
of the palette is the group:

| Group      | File             | Entries, most used first                                                                                                                                                                                                                                        |
| ---------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `start`    | `agents.cheat`   | Start feature agent in plan mode, start bug fix agent, start ADR agent in plan mode, start throwaway spike agent, continue an agent's last conversation, drop a spike and remove its workspace. |
| `agents`   | `agents.cheat`   | Review agent workspace diff (difftastic), show agent workspace changes and files, push workspace and open pull request, create agent workspaces agent-1..N.                                                                                                |
| `review`   | `agents.cheat`   | Review pull request in its own workspace, watch CI checks of pull request.                                                                                                                                                                                       |
| `jj`       | `jj.cheat`       | Describe a change, rebase stack onto latest trunk, squash a change into another, show a change with difftastic, revert a file to its trunk version, abandon a change, find changes that touched a file, find changes by description text, restore the repo to an earlier operation, check signature of a change, push a change straight to main. |
| `kafka`    | `infra.cheat`    | Tail Kafka topic, produce message, show consumer group lag, create topic, reset consumer group to earliest offset, delete topic.                                                                                                                                 |
| `redis`    | `infra.cheat`    | Find Redis keys by pattern, inspect a key (type, TTL, memory), delete keys by pattern.                                                                                                                                                                           |
| `infra`    | `infra.cheat`    | Open kafka-ui or Jaeger in the browser.                                                                                                                                                                                                                          |
| `k8s`      | `k8s.cheat`      | Tail logs of an app, debug failing pod (describe, previous logs), port-forward service, open shell in pod, show namespace events, show container images, decode a secret.                                                                                       |
| `go`       | `dev.cheat`      | Run one Go test, debug one Go test with delve, open Go test coverage in the browser.                                                                                                                                                                              |
| `dotfiles` | `dotfiles.cheat` | Check dotfiles before pushing, compare live config files with the repo, preview what the install would change.                                                                                                                                                   |

A few entries are worth a closer look:

- "Review agent workspace diff" diffs `trunk()..<workspace>@`, everything
  the agent changed on top of trunk. The workspace picker shows the latest
  change description of each agent.
- The pod picker in `k8s.cheat` lists pods that are not ready first, with
  their status and restart count.

Two labels mark entries to read twice before pressing Enter:

- `[LOCAL ONLY]` on the destructive infra entries: deleting a Kafka topic,
  resetting a consumer group and deleting Redis keys. They only ever target
  `localhost`.
- `[PERSONAL]` on "Push a change straight to main", which runs
  `jland <change>` and skips the pull request. Use it in your own repos only.

The usual way to land work is "Push workspace and open pull request",
which runs `jpush <bookmark> && gh pr create --head <bookmark> --fill`. See
[Review and land](review-and-land.md) for the rest of that flow.

## Write your own

A cheat file starts with a `%` line of tags, which navi shows as the group
column. Each entry is a `#` description line followed by the command.
`<name>` marks an argument, and a `$ name:` line at the end of the section
gives it a picker: a shell command whose output lines become the fzf list.
A file can hold several sections, each starting with its own `%` line, as
`infra.cheat` does for `kafka`, `redis` and `infra`. A picker only serves
the entries of its own section, so repeat it in each section that needs it.

```text
% my-service, go

# Run one Go test by name
go test ./... -run '^<test>$'

$ test: grep -rhoE '^func Test[A-Za-z0-9_]+' --include='*_test.go' . | sed 's/^func //' | sort -u
```

Put it in `.navi/my-service.cheat` in the repo (see
[per-project workflows](#per-project-workflows)) or in a new file under
`navi/` here.

When a picker should show more than the value, print tab-separated columns
and tell navi which one to insert. From `jj.cheat`:

```text
$ change: jj --ignore-working-copy log --no-graph -r 'mutable()' -T 'change_id.shortest(8) ++ "\t" ++ coalesce(description.first_line(), "(no description)") ++ "\n"' --- --column 1 --delimiter '\t'
```

You search by change ID and description, and only the ID is inserted.

A later picker can use the value of an earlier one as a shell variable. In
`k8s.cheat`, the secret list depends on the namespace you picked first:

```text
$ namespace: kubectl get namespaces -o name | sed 's|^namespace/||'
$ secret: kubectl -n "$namespace" get secrets -o name | sed 's|^secret/||'
```

navi runs pickers in bash, not zsh. A picker has to call real programs
(`jj`, `kubectl`, `gh`, `docker compose ... exec -T`), never `jw`, `jpush`,
`infra` or `sign-as`. The commands themselves may use them.

Keep descriptions short and put the words you would search for first.
Without a terminal, navi cuts descriptions to a column width, so a long
description can stop matching a query in the tests.

## Per-project workflows

A repo can carry its own cheats in a `.navi/` folder at its root. Opening
the palette runs every picker in those files, so `zsh/navi.zsh` loads a
repo's `.navi/` only when the repo is trusted, for the same reason
`mise trust` and `direnv allow` exist.

A repo is trusted when its main checkout is inside `$DOTFILES_PERSONAL_DIR`,
the folder you chose for the second identity in `install.sh`, or when its
path is listed in `~/.config/navi/trusted-repos`. With one identity the
variable is unset and nothing is trusted automatically. Manage the list
from inside the repo:

```sh
navi-trust     # add this repo's main checkout to the list
navi-untrust   # remove it
```

Trust belongs to the main checkout, so every jj workspace of a trusted repo
loads its own `.navi/`, the one in that workspace's files.

Setting `NAVI_PATH` replaces navi's default folder rather than adding to it.
On every `cd` (a `chpwd` hook), `zsh/navi.zsh` sets
`NAVI_PATH=<default cheats folder>:<repo>/.navi` in a trusted repo with a
`.navi/` folder and unsets it everywhere else, so the shipped workflows are
always there.

## What the tests check

`tests/navi.bats` runs with `just test`, or alone with
`bats tests/navi.bats`. A new entry has to pass all of it:

- Every entry renders with a value for each of its `<arguments>`.
- Descriptions are unique across all cheats.
- Pickers call no zsh functions.
- Every `jj` picker passes `--ignore-working-copy`, so opening the palette
  never snapshots the working copy, adds no op log entry and never asks for
  a signature.
- Destructive infra entries (deleting topics or keys, resetting offsets,
  `FLUSH`, `infra reset`) start with `[LOCAL ONLY]`, and every `kcat`,
  `redis-cli` and Kafka command targets `localhost`.
- Any entry that runs `jj git push -b main` or `jland` starts with
  `[PERSONAL]`.
- The local pickers run in bash and print something. Pickers that need
  Docker, a cluster, GitHub, Go or Redis are skipped.
- `zsh/navi.zsh` sets the column layout in `NAVI_CONFIG_YAML`, and leaves
  it unset when navi has a config file of its own.
- An expect script picks a change from a tab-separated picker and checks that
  only column 1 is inserted.
- An untrusted repo's `.navi/` is not loaded, repos under
  `DOTFILES_PERSONAL_DIR` are, nothing is trusted automatically without that
  variable, `navi-trust` and `navi-untrust` toggle a repo, and a workspace of
  a trusted repo loads its own `.navi/`.

[Contributing](../../CONTRIBUTING.md#adding-a-workflow) has the short
version. The [cheatsheet](../reference/cheatsheet.md#workflows-zshnavizsh) lists the
keys and commands.
