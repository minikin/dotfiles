# Install

The setup expects macOS on Apple Silicon with [Homebrew](https://brew.sh) at
`/opt/homebrew`. After installing Homebrew, put it on `PATH` for the current
shell. The repo's `zshrc` does it permanently once installed:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

On an Intel Mac, change `HOMEBREW_PREFIX` in `zsh/zshrc` and the path in
`zsh/zprofile.snippet` first. Docker Desktop or OrbStack is needed only for
the [local infra](guides/local-infra.md). Go comes from the official
installer, not from Homebrew or mise.

## By hand

Clone the repo anywhere you like. `~/src/dotfiles` below is only an example.
`install.sh` records the location as `DOTFILES_DIR` in
`~/.config/dotfiles/config`, and the shell reads it from there.

```bash
git clone https://github.com/minikin/dotfiles ~/src/dotfiles
cd ~/src/dotfiles
brew bundle
./install.sh --dry-run
./install.sh
exec zsh
```

`brew bundle` installs everything in the `Brewfile`: Ghostty and the
JetBrains Mono Nerd Font, the shell tools, jj, jjui and difftastic, mise,
just, Claude Code, `redis-cli` and `kcat`, the API and Kubernetes tools, and
what the repo's own checks need.

`--dry-run` prints every command `install.sh` would run, prefixed with `+`,
and a link that is already in place as `ok`. Read the `mv` lines: those are
the files it would back up. Then run it for real. In order, it symlinks the
configs into `$HOME`, moves the macOS Ghostty config aside, appends the mise
line to `~/.zprofile`, merges the Claude Code settings, writes your identity,
writes the machine settings file `~/.config/dotfiles/config`, mirrors the
identity into git, and validates the Ghostty config.
[install.sh](reference/install-sh.md) describes each step.

The live configs end up as symlinks into the repo, so editing `~/.zshrc`
edits `zsh/zshrc`. [Updating](guides/updating.md) covers committing those
edits and pulling them on another machine.

## With Claude Code

```bash
git clone https://github.com/minikin/dotfiles ~/src/dotfiles
cd ~/src/dotfiles
claude
```

Paste everything below the line in [SETUP_PROMPT.md](../SETUP_PROMPT.md).
Claude checks for macOS, Apple Silicon and Homebrew, runs `brew bundle`, asks
you for your identity values, including whether you want one identity or
two, shows you the `./install.sh --dry-run` output
and waits for your OK. It then runs `install.sh` with your answers in
environment variables, runs the checks from [Verify](#verify), and tries
`jw` end to end in a `mktemp -d` repo, never a real one. It stops on the
first error and never pushes.

## Identity

The repo contains no names, emails or keys. On the first run, if
`~/.config/jj/conf.d/identity.toml` does not exist, `install.sh` asks for
them:

```text
Set up your commit identity (stored only on this machine).
  Full name: Jane Doe
  Email, used in every repo: jane@work.example
  Signing key — public key line or path to .pub (empty = don't sign): ~/.ssh/id_ed25519_work.pub
  Use a second identity for the repos in one folder (e.g. personal projects)? [y/N] y
  Folder for those repos (e.g. ~/src/personal): ~/src/personal
  Email for that folder: jane@personal.example
  Signing key for that folder — key line or .pub path (empty = same as above): ~/.ssh/id_ed25519_personal.pub
```

The signing key is either an SSH public key line, such as the one the
1Password SSH agent shows, or a path to a `.pub` file. One identity for
every repo is the default: answer `N` (or press Enter) at the second-identity
question and you are done. With `y`, the second email and key apply to every
repo inside the folder you name, `~/src/personal` in this example. The folder
can be any path and is created if missing. A symlinked folder is stored as
the physical path it points to. `install.sh` writes the answers to
`identity.toml` with mode 600, and sets up git signing,
`~/.config/git/allowed_signers` and, for a second identity,
`~/.config/git/personal.gitconfig` where git has nothing configured yet.

Without a terminal, it reads the same values from `DOTFILES_NAME`,
`DOTFILES_EMAIL` and `DOTFILES_SIGNING_KEY`, plus `DOTFILES_PERSONAL_DIR`,
`DOTFILES_PERSONAL_EMAIL` and `DOTFILES_PERSONAL_KEY` for a second identity.
`DOTFILES_NAME` switches this on. `DOTFILES_PERSONAL_DIR` and
`DOTFILES_PERSONAL_EMAIL` must be set together, otherwise `install.sh` exits
2. An empty `DOTFILES_EMAIL` also exits 2. This is how Claude runs it for two identities. Drop the last three
variables for one:

```bash
DOTFILES_NAME="Jane Doe" DOTFILES_EMAIL=jane@work.example \
DOTFILES_SIGNING_KEY=~/.ssh/id_ed25519_work.pub \
DOTFILES_PERSONAL_DIR=~/src/personal \
DOTFILES_PERSONAL_EMAIL=jane@personal.example \
DOTFILES_PERSONAL_KEY=~/.ssh/id_ed25519_personal.pub \
./install.sh
```

With neither a terminal nor `DOTFILES_NAME`, it copies
`jj/identity.example.toml` into place for you to edit by hand. Its
`[signing]` and `[[--scope]]` blocks are commented out, so commits are not
signed until you fill in a real key and uncomment `[signing]`. To answer the
prompts again, delete `identity.toml` and rerun `./install.sh`.
[Identity and signing](guides/identity-and-signing.md) explains how the
identity is picked per repo and how `sign-as` overrides it.

## What gets backed up

Anything `install.sh` would replace is renamed to
`<file>.bak-<YYYYMMDD-HHMMSS>`, one timestamp per run. That covers:

- each of the 16 link targets that exists and is not already a link into the
  repo, such as `~/.zshrc` or `~/.config/jj/config.toml`
- `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`,
  which Ghostty reads after `~/.config/ghostty/config` and which would
  override it
- `~/.claude/settings.json`, copied before the merge, and only when the
  merge changes it

`~/.zprofile` is appended to, not replaced, and only when it has no
`mise activate zsh --shims` line yet.

## Verify

```bash
exec zsh
ghostty +validate-config
ghostty +list-fonts | grep 'JetBrainsMono Nerd Font Mono'
/usr/bin/time zsh -i -c exit
type jw jwc jws jwst jwl jwrm jsync jpush jland jnext sign-as infra reload navi-trust navi-untrust z zi
(cd ~ && jj config get user.email)
git config --global user.email
echo '{"workspace":{"current_dir":"'$PWD'"},"model":{"display_name":"test"}}' | ~/.claude/statusline.sh
```

`ghostty +validate-config` prints nothing when the config is valid. Shell
startup should take about 150 ms or less. Both emails should be the main
email you entered (jj runs from `~` because inside the second identity's
folder it shows that identity), unless git already had one, which `install.sh`
leaves alone. The status line should print the directory, the change and
`test`, separated by `·`.

Then restart Ghostty and Claude Code, and add your public keys on GitHub as
**Signing keys** so your commits show as verified. The global `` cmd+` ``
quick terminal needs Accessibility permission for Ghostty, under System
Settings, Privacy and Security.

## Uninstall

There is no uninstall script. Remove the symlinks and move the backups back:

```bash
cd ~
for f in .zshrc .config/ghostty/config .config/zsh/jj.zsh .config/zsh/sign.zsh \
         .config/zsh/infra.zsh .config/zsh/navi.zsh .config/zsh/reload.zsh \
         .local/share/navi/cheats/dotfiles \
         .config/devinfra/compose.yaml .config/starship.toml \
         .config/jj/config.toml .config/mise/config.toml .claude/CLAUDE.md \
         .claude/statusline.sh .claude/notify.sh .claude/guard-push.sh; do
  [[ -L $f ]] && rm "$f"
done
find ~ -maxdepth 4 -name '*.bak-*' 2>/dev/null
```

Rename each backup you want to keep to its original name, for example
`mv ~/.zshrc.bak-20261014-151200 ~/.zshrc`. If you ran `install.sh` more
than once, the oldest timestamp holds your original file. Then clean up by
hand:

- the mise block at the end of `~/.zprofile`
- `~/.claude/settings.json`, restored from its `.bak-*` copy or edited to
  drop `statusLine`, `env.JJ_EDITOR`, `preferredNotifChannel`, the jj
  permission entries and the `hooks` entries that run `~/.claude/notify.sh`
  and `~/.claude/guard-push.sh`
- `~/.config/jj/conf.d/identity.toml`, `~/.config/dotfiles/config`,
  the per-repo files `sign-as` wrote under `~/.config/jj/repos/`,
  `~/.config/git/allowed_signers` and `~/.config/git/personal.gitconfig`
- the global git keys it set: `user.name` and `user.email` when git had
  none, `gpg.format`, `user.signingkey`,
  `gpg.ssh.program`, `gpg.ssh.allowedSignersFile`, `commit.gpgsign`,
  `tag.gpgsign`, `alias.dft` and, with a second identity, the
  `includeIf.gitdir:<folder>/.path` entry

Homebrew packages stay installed. Remove the ones you no longer want with
`brew uninstall`.
