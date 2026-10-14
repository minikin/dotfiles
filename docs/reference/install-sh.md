# install.sh

`install.sh` links the configs into `$HOME`, appends the mise line to
`~/.zprofile`, merges the Claude Code settings and writes the local commit
identity. It is safe to run again: anything already in place prints `ok`.

## Usage

```sh
./install.sh             # install
./install.sh --dry-run   # print every action, change (almost) nothing
just install --dry-run   # the same through the justfile
```

| Argument    | Effect                                                                                                    |
| ----------- | --------------------------------------------------------------------------------------------------------- |
| none        | Full install.                                                                                             |
| `--dry-run` | Prints each command as `+ <command>` instead of running it. Skips the identity prompts and the jq check. |
| `--help`, `-h` | Prints the usage comment from the top of the script and exits 0. |

Only the first argument is read. Any other argument prints the usage line and
exits 2 without changing anything.

## Environment variables

| Variable                  | Used for                                       | Empty or unset means                     |
| ------------------------- | ---------------------------------------------- | ---------------------------------------- |
| `DOTFILES_NAME`           | `user.name`. Also switches off every prompt.   | Prompts, or the template without a TTY.  |
| `DOTFILES_EMAIL`          | Default (work) `user.email`.                   | Empty email.                             |
| `DOTFILES_SIGNING_KEY`    | Default signing key: public key line or `.pub` path. | No signing.                        |
| `DOTFILES_PERSONAL_EMAIL` | Email for repos under `~/repos/personal`.      | No personal identity.                    |
| `DOTFILES_PERSONAL_KEY`   | Signing key for repos under `~/repos/personal`. | The default key applies there too.      |

`DOTFILES_NAME` is the switch. With it set, all five values come from the
environment and a missing one is an empty answer. Without it, the other four
variables are not read at all. The variables only matter when
`~/.config/jj/conf.d/identity.toml` does not exist yet.

## Steps

The script prints a `==` header before each step.

| Step | Header                       | What it does                                                                                     |
| ---- | ---------------------------- | ------------------------------------------------------------------------------------------------ |
| 1    | `== symlinks`                | Links each repo file below into `$HOME`, then moves Ghostty's macOS config aside.               |
| 2    | `== .zprofile`               | Appends `zsh/zprofile.snippet` to `~/.zprofile` if the mise shims line is missing.               |
| 3    | `== Claude Code settings`    | Merges `claude/settings.fragment.json` into `~/.claude/settings.json`.                           |
| 4    | `== identity`                | Writes `~/.config/jj/conf.d/identity.toml` and the matching git config, if the file is missing. |
| 5    | `== git identity`            | Copies `user.name` and `user.email` from jj into global git config if git has no email.         |
| 6    | `== checks`                  | Runs `ghostty +validate-config` and, unless `--dry-run`, deletes `~/.zcompdump*`.               |

## Linked files

| Repo file                | Link created                          |
| ------------------------ | ------------------------------------- |
| `ghostty/config`         | `~/.config/ghostty/config`            |
| `zsh/zshrc`              | `~/.zshrc`                            |
| `zsh/jj.zsh`             | `~/.config/zsh/jj.zsh`                |
| `zsh/sign.zsh`           | `~/.config/zsh/sign.zsh`              |
| `zsh/infra.zsh`          | `~/.config/zsh/infra.zsh`             |
| `zsh/navi.zsh`           | `~/.config/zsh/navi.zsh`              |
| `navi/` (directory)      | `~/.local/share/navi/cheats/dotfiles` |
| `infra/compose.yaml`     | `~/.config/devinfra/compose.yaml`     |
| `starship/starship.toml` | `~/.config/starship.toml`             |
| `jj/config.toml`         | `~/.config/jj/config.toml`            |
| `mise/config.toml`       | `~/.config/mise/config.toml`          |
| `claude/CLAUDE.md`       | `~/.claude/CLAUDE.md`                 |
| `claude/statusline.sh`   | `~/.claude/statusline.sh`             |

Each link is an absolute symlink to the file in the checkout. For each
destination:

1. If the destination already resolves to the repo file (`[[ dest -ef src ]]`),
   it prints `ok   <dest>` and moves on. This also covers a parent directory
   that is itself a link into the repo, so the script never renames the
   repo's own file.
2. Otherwise it creates the parent directory, moves anything at the
   destination (a file, a directory or a broken link) to
   `<dest>.bak-<stamp>`, and creates the link.

After the links, if
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` exists,
it is moved to `config.ghostty.bak-<stamp>`. Ghostty reads that file after
`~/.config/ghostty/config`, so any copy of it overrides the linked config.

`just drift` reads the same `link` lines and reports each destination as
`linked`, `same (copy)`, `DIFFERS` or `missing`.

## What it writes

### `~/.zprofile`

If no line in `~/.zprofile` contains `mise activate zsh --shims`, the script
appends an empty line and the contents of `zsh/zprofile.snippet`:

```zsh
# mise shims for non-interactive login shells (scripts, IDE tasks);
# interactive shells get full `mise activate` from .zshrc
typeset -U path
path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
eval "$(/opt/homebrew/bin/mise activate zsh --shims)"
```

The append happens once. Later edits to the snippet do not reach
`~/.zprofile`.

### `~/.claude/settings.json`

The merge needs `jq`. Without it the script prints
`jq is required` and exits 1.

| Part of the file             | Result                                                                   |
| ---------------------------- | ------------------------------------------------------------------------ |
| `permissions.allow`          | Existing list plus the fragment's list, sorted and deduplicated (`unique`). |
| `permissions.deny`           | Existing list plus the fragment's list, sorted and deduplicated.         |
| Keys in the fragment         | Deep merge (`jq` `*`): the fragment's value wins. Today `env.JJ_EDITOR` and `statusLine`. |
| Every other key              | Kept as it was.                                                          |

A missing or empty `settings.json` counts as `{}`. The merge goes to
`settings.json.tmp` first. If `jq` fails (for example on invalid JSON), the
temp file is deleted, `settings.json` is left untouched, and the script
prints `settings merge failed` and exits 1.

If the merged result equals the current file, the temp file is dropped and
the script prints `ok   ~/.claude/settings.json (unchanged)`. Otherwise an
existing file is copied to `settings.json.bak-<stamp>` and the merged file
replaces it, and the script prints `updated (backup: <file>)`. With no
`settings.json` at all it writes the merged fragment and prints `created`.

### `~/.config/jj/conf.d/identity.toml`

Written only when the file does not exist. An existing file is never read or
changed: delete it and run the script again to redo the prompts.

| Situation                              | Result                                                         |
| -------------------------------------- | -------------------------------------------------------------- |
| File exists                            | `ok`, nothing else in this step runs.                          |
| `--dry-run`                            | Prints `+ create ...`.                                         |
| No `DOTFILES_NAME` and stdin not a TTY | Copies `jj/identity.example.toml`, mode 600, prints a warning. No git config is written. |
| `DOTFILES_NAME` set                    | Values from the `DOTFILES_*` variables.                        |
| Otherwise                              | Prompts on the terminal.                                       |

The prompts, in order:

| Prompt                                                                  | Variable                  |
| ----------------------------------------------------------------------- | ------------------------- |
| `Full name:`                                                            | `DOTFILES_NAME`           |
| `Default (work) email:`                                                 | `DOTFILES_EMAIL`          |
| `Signing key — public key line or path to .pub (empty = don't sign):`   | `DOTFILES_SIGNING_KEY`    |
| `Personal email for repos under ~/repos/personal (empty = skip):`       | `DOTFILES_PERSONAL_EMAIL` |
| `Personal signing key — public key line or .pub path (empty = same as default):` | `DOTFILES_PERSONAL_KEY` |

The personal key prompt appears only when a personal email was given.

A signing key is read in one of two forms:

| Input                                                    | `signing.key`              | Signer program                                                                 | Public key for `allowed_signers` |
| -------------------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------ | -------------------------------- |
| A line starting with `ssh-`, `ecdsa-` or `sk-`           | The line itself            | `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` if executable, else `/usr/bin/ssh-keygen` | The line itself |
| A path to an existing file (a leading `~` is expanded)   | The expanded path          | `/usr/bin/ssh-keygen`                                                          | The file's contents              |

Anything else prints `'<input>' is neither a public key line nor an existing
.pub file`. At a terminal the prompt repeats. With `DOTFILES_NAME` set the
script exits 1 and writes no identity file.

The file is written with mode 600. With every value given, it looks like
this (see [jj configuration](jj-config.md#identitytoml) for each key):

```toml
[user]
name = "Jane Doe"
email = "jane@work.example"

[signing]
backend = "ssh"
behavior = "own"
key = "ssh-ed25519 AAAA..."
backends.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
backends.ssh.allowed-signers = "~/.config/git/allowed_signers"

[[--scope]]
--when.repositories = ["~/repos/personal"]
[--scope.user]
email = "jane@personal.example"
[--scope.signing]
key = "~/.ssh/id_ed25519_personal.pub"
backends.ssh.program = "/usr/bin/ssh-keygen"
```

`[signing]` is left out when the default key is empty. The `[[--scope]]`
block is left out when the personal email is empty. `[--scope.signing]` is
left out when the personal key is empty, so the scope inherits the default
key. A key given as a path is written with `~` already expanded, so the
real file holds an absolute path where the example above shows the template's
`~/.ssh/...` form.

### Global git config

Written in the same run as `identity.toml`, never on later runs.

| Key                           | Value                              | Written when                                       |
| ----------------------------- | ---------------------------------- | -------------------------------------------------- |
| `gpg.format`                  | `ssh`                              | git has no `user.signingkey` and a default key was given |
| `user.signingkey`             | the default key                    | same                                               |
| `gpg.ssh.program`             | the default signer program         | same                                               |
| `gpg.ssh.allowedSignersFile`  | `~/.config/git/allowed_signers` (literal `~`) | same                                    |
| `commit.gpgsign`              | `true`                             | same                                               |
| `tag.gpgsign`                 | `true`                             | same                                               |
| `includeIf.gitdir:~/repos/personal/.path` | `~/.config/git/personal.gitconfig` | a personal email was given and the key is not set yet |

### `~/.config/git/allowed_signers`

Created empty if missing. For the default and the personal identity, a line

```text
<email> namespaces="git" <public key>
```

is appended unless `<email> ` (the email and a space) already appears
anywhere in the file.

### `~/.config/git/personal.gitconfig`

Written when a personal email was given and the global `includeIf` for
`~/repos/personal/` is not set yet.

| Key               | Value                       | Written when               |
| ----------------- | --------------------------- | -------------------------- |
| `user.email`      | the personal email          | always                     |
| `user.signingkey` | the personal key            | a personal key was given   |
| `gpg.ssh.program` | the personal signer program | a personal key was given   |

`install.sh` never writes `core.sshCommand`. `sign-as personal` reads it from
this file if you add it by hand (see [shell commands](shell-commands.md#sign-as)).

### git identity and alias

If `git config --global user.email` is empty and `jj` is installed, the script
copies `user.name` and `user.email` from `jj config get` into global git
config. Without `jj` it prints a `skip` line to stderr and goes on.

If `difft` is on `PATH`, it sets the global alias
`dft = -c diff.external=difft diff` every run.

## Backups

Every backup is `<original path>.bak-<stamp>`, where `<stamp>` is
`date +%Y%m%d-%H%M%S` taken once at start, so all backups from one run share
it. The script never deletes a backup.

| What                                   | Backed up when                         |
| -------------------------------------- | -------------------------------------- |
| A link destination                     | It exists and does not resolve to the repo file. |
| `config.ghostty` under Application Support | It exists.                          |
| `~/.claude/settings.json`              | It exists and the merge changes it.    |

`~/.zprofile`, `identity.toml`, the git config files and `allowed_signers`
are appended to or written in place, without a backup.

## Exit status

The script runs under `set -euo pipefail`.

| Exit | Cause                                                                       |
| ---- | --------------------------------------------------------------------------- |
| `0`  | Finished. The last line is `done — open a new terminal tab (or: exec zsh)`. |
| `1`  | `jq` is not installed (not checked under `--dry-run`).                      |
| `1`  | The settings merge failed. `settings.json` is untouched.                    |
| `1`  | A bad signing key with `DOTFILES_NAME` set. No identity file is written.    |
| non-zero | Any other failing command, for example `mkdir`, `mv` or `ln`.           |

A failing `ghostty +validate-config` prints Ghostty's errors and leaves out
the `ok   ghostty config valid` line, but does not stop the script. The check
runs only when `ghostty` is on `PATH` or
`/Applications/Ghostty.app/Contents/MacOS/ghostty` exists, and never under
`--dry-run`.

## Idempotency

| Step                 | Check that makes a second run a no-op                                  |
| -------------------- | ---------------------------------------------------------------------- |
| Links                | `dest -ef src`: already linked, prints `ok`.                           |
| `config.ghostty`     | Moved on the first run, so it no longer exists.                        |
| `~/.zprofile`        | `grep` for `mise activate zsh --shims`.                                |
| Claude settings      | `jq` equality of the merged result and the current file.               |
| Identity             | `identity.toml` exists.                                                |
| Git signing          | Only when git has no `user.signingkey`.                                |
| `allowed_signers`    | Only when no line starts with the email.                               |
| Personal git config  | Only when the `includeIf` key is not set.                              |
| Git identity         | Only when git has no `user.email`.                                     |
| `git dft` alias      | Set again each run to the same value.                                  |

`tests/install.bats` checks that a second run makes no new backups and leaves
`settings.json` unchanged.
