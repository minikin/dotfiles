# Troubleshooting

**Claude Code uses the wrong tool versions**, such as the global node instead
of the one in the project's `mise.toml`. Claude Code inherits `PATH` from the
shell that starts it, and mise sets `PATH` per directory, so a session
started in another directory, or before `mise.toml` changed, keeps the old
versions for its whole life. Quit it, `cd` into the project or workspace, and
start `claude` again. `jwc` does the `cd` for you. `mise current` in the same
directory shows what the session should see. If mise refuses the config, run
`mise trust` in the main checkout, and the workspaces inherit it.
[Agents and PATH](explanation/agents-and-path.md) has the full story.

**jj says "The working copy is stale" in a workspace.** Another workspace
rewrote the change this one has checked out, for example by squashing or
rebasing it from the main checkout. Bring the workspace up to date:

```bash
jj workspace update-stale
```

**A workspace directory was deleted by hand.** jj still lists it in
`jj workspace list`. Run `jw <name>` again: it forgets the stale entry,
prunes git's worktree entry and creates the workspace afresh. To drop it for
good, run `jj workspace forget <name>` and then `git worktree prune` in the
main checkout.

**Ghostty ignores a config change.** Run `ghostty +validate-config` first: it
prints nothing when the file is valid. Then check that
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` does
not exist. Ghostty on macOS reads that file after
`~/.config/ghostty/config`, so even an empty copy overrides the repo's
settings. `install.sh` moves it aside when it finds one, so rerun it or
rename the file yourself. Reload with `cmd+shift+,`. A few settings, such as
`macos-option-as-alt`, apply only to new windows.

**zsh takes long to start.** Measure it, and aim for about 150 ms or less:

```bash
/usr/bin/time zsh -i -c exit
rm -f ~/.zcompdump* && exec zsh        # rebuild a stale completion cache
zsh -i -x -c exit 2>&1 | tail -40      # trace startup to find the slow line
```

`zsh/zshrc` hardcodes `HOMEBREW_PREFIX=/opt/homebrew` rather than run
`brew --prefix` in every new split. On an Intel Mac that path is wrong, and
every Homebrew tool goes missing.

**Commits fail to sign.** `sign-as status` shows the email and the last 12
characters of the key jj and git will use in this repo. With a public key
line in `identity.toml`, signing goes through 1Password's `op-ssh-sign` when
1Password is installed, so 1Password has to be running and unlocked, and the
key has to be the one its SSH agent holds. With a `.pub` path, signing goes
through `/usr/bin/ssh-keygen`, which needs the matching private key in your
SSH agent or next to the `.pub` file. Agents are told to stop and report a signing
failure, not to work around it, so the fix is always on your side.
[Identity and signing](guides/identity-and-signing.md) explains which
identity applies where.

**Commits are not signed at all.** If `install.sh` ran without a terminal and
without `DOTFILES_NAME`, it copied the template, whose `[signing]` block is
commented out. Fill in a real key in `~/.config/jj/conf.d/identity.toml` and
uncomment the block, or delete the file and rerun `./install.sh`.

**`install.sh` says `is not a public key file`.** The signing key path points
at a file that is not a single `ssh-...`, `ecdsa-...` or `sk-...` line,
usually the private key. Give the `.pub` file next to it instead.

**`infra up` fails with "port is already allocated" or "address already in
use".** Something on the host
already listens on 6379, 9092, 8088, 16686, 4317 or 4318. The usual suspect
is a Homebrew Redis: the Brewfile installs the `redis` formula for
`redis-cli`, and `brew services start redis` would take port 6379. Find the
owner and stop it:

```bash
lsof -nP -iTCP:6379 -sTCP:LISTEN
brew services stop redis
infra up
```

The other ports clash with a second Kafka, or a Jaeger or OpenTelemetry
collector started by another Compose project. `docker ps` lists those.

**`just drift` shows `DIFFERS`.** The live file is no longer a link into the
repo and its content has changed:

```console
$ just drift
linked       ~/.config/ghostty/config
linked       ~/.zshrc
DIFFERS      ~/.claude/statusline.sh
```

Usually an app wrote its config in place and replaced the symlink with a
plain file. Compare the two before you decide which one wins:

```bash
diff ~/.claude/statusline.sh "$DOTFILES_DIR/claude/statusline.sh"
```

Copy anything worth keeping into the repo file, then run `./install.sh`. It
moves the live file to `statusline.sh.bak-<timestamp>` and links it again.
`same (copy)` means the content matches but the link is gone, and
`./install.sh` fixes that too. `elsewhere` means the link points into
another checkout, usually an old clone or a jj workspace, and shows its target.
Run `./install.sh` from the checkout you want to use.

**`jpush` refuses to push.** The bookmark name is a trunk bookmark such as
`main` or an immutable one, or you are in the `default` workspace without a
name. Pass one: `jpush <bookmark>`.

**Something went wrong in jj.** `jj undo` reverts the last operation. For
anything older, `jj op log` lists every operation, and
`jj op restore <op-id>` puts the whole repo back to that point.

**`git status` fails inside a workspace.** The git on `PATH` is older than 2.48
and does not understand `extensions.relativeWorktrees`, which jj sets for
workspace worktrees. Check with `git --version`, then `brew install git` and
make sure `/opt/homebrew/bin` comes before `/usr/bin` on `PATH`.
