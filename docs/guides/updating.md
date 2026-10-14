# Updating the dotfiles

After `install.sh`, the live config files are symlinks into the repo, so
editing one edits the repo. Commit the change with jj, run `just check`, and
push to `main`. Each linked path is listed in [Files](../reference/files.md),
and [CONTRIBUTING.md](../../CONTRIBUTING.md) has the rules for changes from
others.

## Edit a config

```sh
ls -l ~/.zshrc
# ~/.zshrc -> ~/repos/personal/dotfiles/zsh/zshrc
```

Edit `~/.zshrc`, `~/.config/ghostty/config`, `~/.config/jj/config.toml` or
any other linked file in place, or edit the file in the repo. Both are the
same file. Reload what you changed:

```sh
exec zsh                     # zsh/zshrc and zsh/*.zsh
ghostty +validate-config     # ghostty/config, then cmd+shift+, to reload
```

Some Ghostty settings, such as `macos-option-as-alt`, apply only to new
windows.

Three files are not links, and an edit in the repo does not reach them by
itself:

- `~/.claude/settings.json` is merged from `claude/settings.fragment.json`.
  Run `./install.sh` again after changing the fragment.
- `~/.zprofile` gets `zsh/zprofile.snippet` appended once, when the
  `mise activate zsh --shims` line is missing. After changing the snippet,
  fix `~/.zprofile` by hand.
- `~/.config/jj/conf.d/identity.toml` is local to the machine and never in
  the repo, see [Identity and signing](identity-and-signing.md).

## Commit and push

```sh
cd ~/repos/personal/dotfiles
jj st
jj diff --git
jj commit -m "ghostty: bump font size"
just check
jj bookmark set main -r @-
jj git push -b main
```

`@-` is the change you just committed, below the empty `@` that
`jj commit` leaves on top. The repo is under `~/repos/personal`, so these
commits use the personal identity and key without `sign-as`.

`just check` runs `just lint`, `just test` and `just secrets`, the same steps
as the `check` job in CI:

- `lint`: `shellcheck` on `install.sh`, `claude/statusline.sh` and
  `scripts/*.sh`, `zsh -n` on every zsh file, `docker compose config -q` on
  `infra/compose.yaml` when Docker is installed, and an offline `lychee` link
  check of the Markdown
- `test`: `bats tests`
- `secrets`: `scripts/check-secrets.sh`, then `gitleaks dir .` when gitleaks
  is installed

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
| `same (copy)` | a regular file with the same content |
| `DIFFERS` | a file with other content |
| `missing` | nothing at that path |

`DIFFERS` usually means an app wrote its config in place instead of following
the symlink. Compare the two files, copy what you want to keep into the repo,
and run `./install.sh` to put the link back. It moves the live file aside as
`<file>.bak-<timestamp>` first.

## Pull updates on another machine

```sh
cd ~/repos/personal/dotfiles
jj git fetch
jj new 'trunk()'
./install.sh               # links new files, existing links print "ok"
exec zsh
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
