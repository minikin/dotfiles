# install.sh

`install.sh` links the configs into `$HOME`, appends the mise line to
`~/.zprofile`, merges the Claude Code settings, writes the local commit
identity and records the machine settings in `~/.config/dotfiles/config`. It is safe to run again: anything already in place prints `ok`.

## Usage

```sh
./install.sh             # install
./install.sh --dry-run   # print every action, change (almost) nothing
./install.sh --shottr    # also free the screenshot shortcuts for Shottr
./install.sh --all       # brew bundle, install and --shottr in one command
just install --dry-run   # the same through the justfile
```

| Argument    | Effect                                                                                                    |
| ----------- | --------------------------------------------------------------------------------------------------------- |
| none        | Full install.                                                                                             |
| `--dry-run` | Prints each command as `+ <command>` instead of running it. Skips the identity prompts and the jq check. |
| `--brew`    | Runs `brew bundle --file <repo>/Brewfile` before the links. Without `brew` on `PATH` it prints `Homebrew is required for --brew` and exits 1 before changing anything. |
| `--shottr`  | Adds the screenshot shortcuts step, see [Screenshot shortcuts](#screenshot-shortcuts). Combines with `--dry-run`. |
| `--all`     | The same as `--brew --shottr`. |
| `--help`, `-h` | Prints the usage comment from the top of the script and exits 0. |

Arguments are read in order. An unknown one prints the usage line and exits 2
without changing anything.

## Environment variables

| Variable                  | Used for                                       | Empty or unset means                     |
| ------------------------- | ---------------------------------------------- | ---------------------------------------- |
| `DOTFILES_NAME`           | `user.name`. Also switches off every prompt.   | Prompts, or the template without a TTY.  |
| `DOTFILES_EMAIL`          | Main `user.email`, used in every repo.         | Exit 2 when `DOTFILES_NAME` is set.      |
| `DOTFILES_SIGNING_KEY`    | Main signing key: public key line or `.pub` path. | No signing.                           |
| `DOTFILES_PERSONAL_DIR`   | Folder for the second identity's repos, for example `~/src/personal`. Absolute or starting with `~`, created if missing. | One identity everywhere. |
| `DOTFILES_PERSONAL_EMAIL` | Email for repos inside `DOTFILES_PERSONAL_DIR`. | One identity everywhere.                |
| `DOTFILES_PERSONAL_KEY`   | Signing key for repos inside `DOTFILES_PERSONAL_DIR`. | The main key applies there too.   |
| `DOTFILES_ACTIVATE_SETTINGS` | Program `--shottr` runs with `-u` to apply the shortcut change. The tests point it at a fake. | `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings` |

`DOTFILES_NAME` is the switch. With it set, all six values come from the
environment and a missing one is an empty answer. An empty `DOTFILES_EMAIL`
prints `DOTFILES_EMAIL must not be empty when DOTFILES_NAME is set` and exits
2 before anything is written. Without it, the other five
variables are not read at all. The variables only matter when
`~/.config/jj/conf.d/identity.toml` does not exist yet.

`DOTFILES_PERSONAL_DIR` and `DOTFILES_PERSONAL_EMAIL` are set together or not
at all. Only one of them prints
`set DOTFILES_PERSONAL_EMAIL and DOTFILES_PERSONAL_DIR together, or neither`
and exits 2 before anything is written. `DOTFILES_PERSONAL_KEY` is read only
when both are set.

## Steps

The script prints a `==` header before each step.

| Step | Header                       | What it does                                                                                     |
| ---- | ---------------------------- | ------------------------------------------------------------------------------------------------ |
| 0    | `== brew bundle`             | Only with `--brew` or `--all`: installs everything in the `Brewfile`.                            |
| 1    | `== symlinks`                | Links each repo file below into `$HOME`, then moves Ghostty's macOS config aside.               |
| 2    | `== .zprofile`               | Appends `zsh/zprofile.snippet` to `~/.zprofile` if the mise shims line is missing.               |
| 3    | `== Claude Code settings`    | Merges `claude/settings.fragment.json` into `~/.claude/settings.json`.                           |
| 4    | `== identity`                | Writes `~/.config/jj/conf.d/identity.toml` and the matching git config, if the file is missing. |
| 5    | `== machine settings`        | Writes `~/.config/dotfiles/config` with `DOTFILES_DIR` and, with a second identity, `DOTFILES_PERSONAL_DIR`. |
| 6    | `== git identity`            | Copies the main `user.name` and `user.email` into global git config if git has no email.        |
| 7    | `== screenshot shortcuts`    | Only with `--shottr`: turns off the macOS screenshot shortcuts.                                  |
| 8    | `== checks`                  | Runs `ghostty +validate-config` and, unless `--dry-run`, deletes `~/.zcompdump*`.               |

## Linked files

| Repo file                | Link created                          |
| ------------------------ | ------------------------------------- |
| `ghostty/config`         | `~/.config/ghostty/config`            |
| `zsh/zshrc`              | `~/.zshrc`                            |
| `zsh/jj.zsh`             | `~/.config/zsh/jj.zsh`                |
| `zsh/sign.zsh`           | `~/.config/zsh/sign.zsh`              |
| `zsh/infra.zsh`          | `~/.config/zsh/infra.zsh`             |
| `zsh/navi.zsh`           | `~/.config/zsh/navi.zsh`              |
| `zsh/reload.zsh`         | `~/.config/zsh/reload.zsh`            |
| `navi/` (directory)      | `~/.local/share/navi/cheats/dotfiles` |
| `infra/compose.yaml`     | `~/.config/devinfra/compose.yaml`     |
| `starship/starship.toml` | `~/.config/starship.toml`             |
| `jj/config.toml`         | `~/.config/jj/config.toml`            |
| `mise/config.toml`       | `~/.config/mise/config.toml`          |
| `claude/CLAUDE.md`       | `~/.claude/CLAUDE.md`                 |
| `claude/statusline.sh`   | `~/.claude/statusline.sh`             |
| `claude/notify.sh`       | `~/.claude/notify.sh`                 |
| `claude/guard-push.sh`   | `~/.claude/guard-push.sh`             |
| `claude/session-context.sh` | `~/.claude/session-context.sh`     |
| `claude/where.sh`        | `~/.claude/where.sh`                  |

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
`linked`, `elsewhere` (a symlink that does not resolve to the repo file,
printed with its target), `same (copy)`, `DIFFERS` or `missing`.

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
| `hooks.<event>`              | For each event in the fragment (`Notification`, `Stop`, `PreToolUse`): your matcher groups plus the fragment's, sorted and deduplicated. Events only you have are kept. |
| Keys in the fragment         | Deep merge (`jq` `*`): the fragment's value wins. Today `env.JJ_EDITOR`, `statusLine` and `preferredNotifChannel`. |
| Every other key              | Kept as it was.                                                          |

A missing or empty `settings.json` counts as `{}`. The merge goes to
`settings.json.tmp` first. If `jq` fails (for example on invalid JSON), the
temp file is deleted, `settings.json` is left untouched, and the script
prints `settings merge failed` and exits 1.

Hook groups are deduplicated only when they are equal. After you change a
group in the fragment, such as its matcher, a re-run adds the new group and
keeps the old one, so delete the old one from `settings.json` by hand.

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
| No `DOTFILES_NAME` and stdin not a TTY | Copies `jj/identity.example.toml`, mode 600, and prints a warning that commit signing is off until you fill in and uncomment its `[signing]` block. No git config is written. |
| `DOTFILES_NAME` set                    | Values from the `DOTFILES_*` variables.                        |
| Otherwise                              | Prompts on the terminal.                                       |

The prompts, in order:

| Prompt                                                                  | Variable                  |
| ----------------------------------------------------------------------- | ------------------------- |
| `Full name:`                                                            | `DOTFILES_NAME`           |
| `Email, used in every repo:`                                            | `DOTFILES_EMAIL`          |
| `Signing key — public key line or path to .pub (empty = don't sign):`   | `DOTFILES_SIGNING_KEY`    |
| `Use a second identity for the repos in one folder (e.g. personal projects)? [y/N]` | set both of the next two |
| `Folder for those repos (e.g. ~/src/personal):`                         | `DOTFILES_PERSONAL_DIR`   |
| `Email for that folder:`                                                | `DOTFILES_PERSONAL_EMAIL` |
| `Signing key for that folder — key line or .pub path (empty = same as above):` | `DOTFILES_PERSONAL_KEY` |

Any answer to the yes/no question that does not start with `y` or `Y` keeps
one identity and skips the last three prompts. An empty name or email is asked
again with `Full name:` or `Email:`. After `y`, the folder and email
prompts repeat until they get a non-empty answer.

The folder has its trailing `/` removed and a leading `~` expanded. A folder
that is still not an absolute path prints
`folder must be an absolute path or start with ~` and exits 2. Otherwise it
is created with `mkdir -p` and resolved to its physical path with `pwd -P`,
because jj and git match against the repo's physical path and a symlinked
folder would never match. Inside the resolved `$HOME` it is stored as
`~/...`, anywhere else as the resolved absolute path. That stored form is what
goes into `--when.repositories` and into git's `includeIf.gitdir:<folder>/`.

A signing key is read in one of two forms:

| Input                                                    | `signing.key`              | Signer program                                                                 | Public key for `allowed_signers` |
| -------------------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------ | -------------------------------- |
| A line starting with `ssh-`, `ecdsa-` or `sk-`           | The line itself            | `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` if executable, else `/usr/bin/ssh-keygen` | The line itself |
| A path to an existing file holding one line that starts with `ssh-`, `ecdsa-` or `sk-` (a leading `~` is expanded) | The expanded path | `/usr/bin/ssh-keygen` | The file's contents |

A file with more than one line, or one that does not start with `ssh-`,
`ecdsa-` or `sk-` (a private key, for example), prints `'<input>' is not a
public key file (expected one 'ssh-...' line, e.g. a .pub file)`. Anything
else prints `'<input>' is neither a public key line nor an existing .pub
file`. In both cases the prompt repeats at a terminal. With `DOTFILES_NAME`
set the script exits 1 and writes no identity file and no `allowed_signers`.

The file is written with mode 600. With every value given and
`~/src/personal` as the example folder, it looks like this (see [jj configuration](jj-config.md#identitytoml) for each key):

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

# Second identity for every repo under ~/src/personal (override elsewhere: sign-as personal)
[[--scope]]
--when.repositories = ["~/src/personal"]
[--scope.user]
email = "jane@personal.example"
[--scope.signing]
key = "~/.ssh/id_ed25519_personal.pub"
backends.ssh.program = "/usr/bin/ssh-keygen"
```

`[signing]` is left out when the main key is empty, also when the second
identity has a key: that key goes only into `[--scope.signing]` and
`personal.gitconfig`, never into `[signing]` or the global git config. The comment and the
`[[--scope]]` block are left out with one identity. `[--scope.signing]` is
left out when the second key is empty, so the scope inherits the main
key. A key given as a path is written with `~` already expanded, so the
real file holds an absolute path where the example above shows the template's
`~/.ssh/...` form.

### `~/.config/dotfiles/config`

Written on every run, also when `identity.toml` already exists. `zsh/zshrc`
sources it with `set -a`, so both values are exported to every shell.

```sh
# Written by install.sh, read by zshrc. Re-run install.sh to update.
DOTFILES_DIR=/Users/<you>/src/dotfiles
DOTFILES_PERSONAL_DIR=/Users/<you>/src/personal
```

| Variable                | Value                                                       | Written when |
| ----------------------- | ----------------------------------------------------------- | ------------ |
| `DOTFILES_DIR`          | The directory `install.sh` runs from, wherever the repo was cloned. | always |
| `DOTFILES_PERSONAL_DIR` | The second identity's folder as an absolute path. On this run's answers: `$HOME/...` when the resolved folder is inside the resolved `$HOME`, otherwise the resolved path. On later runs: the `--when.repositories` line in `identity.toml` with `~` expanded to `$HOME`. | there is a second identity |

The template's placeholder folder `~/path/to/personal-repos` is never written
as `DOTFILES_PERSONAL_DIR`. Values are quoted with `printf %q`. The new
content goes to `config.tmp` first. If it matches the existing file, the
script prints `ok   ~/.config/dotfiles/config (unchanged)` and drops the temp
file, otherwise it replaces the file and prints `ok   wrote ...`. Under
`--dry-run` it prints `+ write ...` with the values it would write.

The [navi](shell-commands.md#navi-trust-and-navi-untrust) trust check reads
`DOTFILES_PERSONAL_DIR`, and the saved workflows in `navi/dotfiles.cheat` run
`cd "$DOTFILES_DIR"`.

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
| `includeIf.gitdir:<folder>/.path` | `~/.config/git/personal.gitconfig` | there is a second identity and the key is not set yet |

### `~/.config/git/allowed_signers`

Created empty if missing, then set to mode 600 (also when it already
existed). For the main identity and the second one, if any, a line

```text
<email> namespaces="git" <public key>
```

is appended unless `<email> ` (the email and a space) already appears
anywhere in the file.

### `~/.config/git/personal.gitconfig`

Written when there is a second identity and the global `includeIf` for its
folder is not set yet. With one identity the file does not exist, and
`sign-as personal` refuses to run.

| Key               | Value                       | Written when               |
| ----------------- | --------------------------- | -------------------------- |
| `user.email`      | the second email            | always                     |
| `user.signingkey` | the second key              | a second key was given     |
| `gpg.ssh.program` | the second signer program   | a second key was given     |

`install.sh` never writes `core.sshCommand`. `sign-as personal` reads it from
this file if you add it by hand (see [shell commands](shell-commands.md#sign-as)).

### git identity and alias

If `git config --global user.email` is empty and `jj` is installed, the script
sets global `user.name` and `user.email`. On the run that writes
`identity.toml`, it uses the name and email given in that run. Otherwise it
reads them with `jj config get`, run from `/` so that the second identity's
`--when.repositories` scope never applies, even when `install.sh` runs inside
that folder. If the email is `you@work.example` or the name is `Your Name`
(the template's values), it prints `skip git identity: ... still has
placeholders` to stderr and writes nothing. Without `jj` it prints a `skip`
line to stderr and goes on.

If `difft` is on `PATH`, it sets the global alias
`dft = -c diff.external=difft diff` every run.

### Screenshot shortcuts

Runs only with `--shottr`. macOS has no setting for a default screenshot app,
so the step turns off its own shortcuts and leaves the keys free for Shottr
(`cask "shottr"` in the `Brewfile`). For each ID below it runs
`defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add <id> '<dict><key>enabled</key><false/></dict>'`.

| ID    | Shortcut | macOS action                     |
| ----- | -------- | -------------------------------- |
| `28`  | ⇧⌘3      | Save a picture of the screen     |
| `29`  | ⌃⇧⌘3     | Copy a picture of the screen     |
| `30`  | ⇧⌘4      | Save a picture of a selected area |
| `31`  | ⌃⇧⌘4     | Copy a picture of a selected area |
| `184` | ⇧⌘5      | Screenshot and recording options |

Then it runs `activateSettings -u` so the change applies without logging out.
If that program is missing it prints `skip applying now` to stderr, and the
change applies at the next login. The step does not set Shottr's own hotkeys.
Assign ⇧⌘3, ⇧⌘4 and ⇧⌘5 in Shottr under Preferences, Hotkeys, and turn on
Launch at login. To undo the step, tick the shortcuts again in System Settings
under Keyboard, Keyboard Shortcuts, Screenshots.

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
| `1`  | `--brew` and no `brew` on `PATH`.                                           |
| `1`  | `jq` is not installed (not checked under `--dry-run`).                      |
| `1`  | The settings merge failed. `settings.json` is untouched.                    |
| `1`  | A bad signing key with `DOTFILES_NAME` set, including a file that is not a public key. No identity file is written. |
| `2`  | An unknown argument.                                                        |
| `2`  | `DOTFILES_NAME` is set and `DOTFILES_EMAIL` is empty.                       |
| `2`  | Only one of `DOTFILES_PERSONAL_DIR` and `DOTFILES_PERSONAL_EMAIL` is set.   |
| `2`  | The second identity's folder is neither absolute nor starts with `~`.       |
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
| Machine settings     | `cmp` of the new content and the current file, prints `(unchanged)`.   |
| Git signing          | Only when git has no `user.signingkey`.                                |
| `allowed_signers`    | Only when no line contains the email followed by a space. Mode 600 is set again.        |
| Second git config    | Only when the `includeIf` key is not set.                              |
| Git identity         | Only when git has no `user.email`.                                     |
| `git dft` alias      | Set again each run to the same value.                                  |
| Screenshot shortcuts | Written again each `--shottr` run with the same value.                 |

`tests/install.bats` checks that a second run makes no new backups and leaves
`settings.json` unchanged.
