# Updating the dotfiles

After `install.sh`, the live config files are symlinks into the repo, so
editing one edits the repo. Commit the change with jj, run `just check`, and
push to `main`. Each linked path is listed in [Files](../reference/files.md),
and [CONTRIBUTING.md](../../CONTRIBUTING.md) has the rules for changes from
others.

## Edit a config

```sh
ls -l ~/.zshrc
# ~/.zshrc -> ~/src/dotfiles/zsh/zshrc
```

The target is wherever you cloned the repo, `~/src/dotfiles` in this example.
`install.sh` records that location as `DOTFILES_DIR` in
`~/.config/dotfiles/config`, and the shell exports it, so `cd "$DOTFILES_DIR"`
works from anywhere.

Edit `~/.zshrc`, `~/.config/ghostty/config`, `~/.config/jj/config.toml` or
any other linked file in place, or edit the file in the repo. Both are the
same file. Reload what you changed:

```sh
reload    # validates Ghostty, jj and zsh configs, then restarts zsh
```

`reload` stops before the restart when a config is broken, so a typo never
leaves you with a shell that cannot start. It only validates Ghostty: press
`cmd+shift+,` to apply `ghostty/config`.

Some Ghostty settings, such as `macos-option-as-alt`, apply only to new
windows.

Four files are not links, and an edit in the repo does not reach them by
itself:

- `~/.claude/settings.json` is merged from `claude/settings.fragment.json`.
  Run `./install.sh` again after changing the fragment.
- `~/.zprofile` gets `zsh/zprofile.snippet` appended once, when the
  `mise activate zsh --shims` line is missing. After changing the snippet,
  fix `~/.zprofile` by hand.
- `~/.config/jj/conf.d/identity.toml` is local to the machine and never in
  the repo, see [Identity and signing](identity-and-signing.md).
- `~/.config/dotfiles/config` is rewritten by every `./install.sh` run. After
  moving the clone, run `./install.sh` from the new location to update
  `DOTFILES_DIR` and the links.

## Commit and push

```sh
cd "$DOTFILES_DIR"
jj st
jj diff --git
jj commit -m "feat(ghostty): bump font size"
just check
jland
```

`jland` moves `main` to `work()`, the change you just committed below the
empty `@` that `jj commit` leaves on top, and pushes it. It is
`jj bookmark set main -r 'work()' && jj git push -b main` with a check that
the change has a description. The commits use the identity of wherever the clone
lives: the main one, or the second one if the clone is inside the second
identity's folder. Run `sign-as status` to check, or `sign-as personal` once
to switch this repo.

`just check` runs `just lint`, `just test`, `just secrets` and `just commits`, the same steps
as the `check` job in CI:

- `lint`: `shellcheck` on `install.sh`, `claude/*.sh` and
  `scripts/*.sh`, a check that every bats `[[ ]]` and `!` assert ends in
  `|| false`, `zsh -n` on every zsh file, `docker compose config -q` on
  `infra/compose.yaml` when Docker is installed, and an offline `lychee` link
  check of the Markdown
- `test`: `bats tests`
- `secrets`: `scripts/check-secrets.sh`, then `gitleaks dir .` when gitleaks
  is installed
- `commits`: `scripts/check-commits.sh`, which checks that every commit in
  `origin/main..HEAD` follows Conventional Commits

Everything it needs is in the `Brewfile`.

## Find files that drifted

```sh
just drift
```

`just drift` reads every `link` line in `install.sh` and prints one status per
live file:

| Status | Meaning |
|---|---|
| `linked` | the live path resolves to the repo file |
| `elsewhere` | a symlink into another checkout, or a dangling one, printed with its target |
| `same (copy)` | a regular file with the same content |
| `DIFFERS` | a file with other content |
| `missing` | nothing at that path |

`DIFFERS` usually means an app wrote its config in place instead of following
the symlink. Compare the two files, copy what you want to keep into the repo,
and run `./install.sh` to put the link back. It moves the live file aside as
`<file>.bak-<timestamp>` first.

## Pull updates on another machine

```sh
cd "$DOTFILES_DIR"
jj git fetch
jj new 'trunk()'
./install.sh               # links new files, existing links print "ok"
reload                     # exec zsh if this machine has no reload yet
```

New `Brewfile` entries need `brew bundle`. New global tools in
`mise/config.toml` need `mise install`.

## Add a new config file

Put the file in the repo, in a directory named after the tool, and add one
`link` line to the symlink block in `install.sh`, with the repo-relative
source and the live destination:

```sh
link lazygit/config.yml       "$HOME/.config/lazygit/config.yml"
```

Preview it, then install:

```sh
./install.sh --dry-run
./install.sh
just drift
```

`just drift` picks the new line up without changes, since it reads the `link`
lines from `install.sh`. Then document the file: add it to
[Files](../reference/files.md) and to the guide or reference page that covers
the tool.
