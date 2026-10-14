# Commit identity and signing

Identity and signing keys are not in the repo. They live in
`~/.config/jj/conf.d/identity.toml`, which jj loads on top of the linked
`~/.config/jj/config.toml`. `install.sh` writes it on the first run, along
with matching git config. The install steps around it are in
[Install](../install.md), the script itself in
[install.sh](../reference/install-sh.md).

You pick one of two setups during install:

- **One identity.** One name, email and key for every repo, for example only
  a personal account or only a work account. This is the default answer and
  needs nothing else.
- **Two identities.** A main identity everywhere, plus a second one for every
  repo inside one folder you choose, for example work everywhere and a
  personal account in `~/src/personal`. That folder is `$DOTFILES_PERSONAL_DIR`
  in the shell.

| Where the repo is | Identity | Source |
|---|---|---|
| Anywhere | Main | `[user]` and `[signing]` in `identity.toml` |
| Inside the second identity's folder, including its `<repo>-ws` workspaces | Second | the `--when.repositories` scope in `identity.toml`, only with two identities |
| A repo where you ran `sign-as personal` | Second | per-repo jj config and local git config |

`signing.behavior = "own"` signs every commit you author, including the ones
agents make in your name and working-copy snapshots.

## Create `identity.toml`

On an interactive run, if the file is missing, `./install.sh` asks:

| Prompt | What to enter |
|---|---|
| `Full name:` | `Jane Doe` |
| `Email, used in every repo:` | `jane@work.example` |
| `Signing key` | a public key line (`ssh-ed25519 AAAA...`) or a path to a `.pub` file. Empty means no `[signing]` section |
| `Use a second identity for the repos in one folder (e.g. personal projects)? [y/N]` | Enter or `n` for one identity. `y` asks the next three |
| `Folder for those repos (e.g. ~/src/personal):` | any absolute path or path starting with `~`. It is created if missing |
| `Email for that folder:` | `jane@personal.example` |
| `Signing key for that folder` | a public key line or a `.pub` path. Empty means the folder uses the key above |

The key input decides the signer:

- A public key line (`ssh-*`, `ecdsa-*`, `sk-*`) is signed through an agent.
  `install.sh` uses `/Applications/1Password.app/Contents/MacOS/op-ssh-sign`
  when it is executable, otherwise `/usr/bin/ssh-keygen`.
- A path to a `.pub` file is signed with `/usr/bin/ssh-keygen`. A leading `~`
  is expanded, and the absolute path goes into the file. The file must hold
  one line starting with `ssh-`, `ecdsa-` or `sk-`. Anything else, a private
  key for example, prints `is not a public key file` and asks again.

Any other input prints `is neither a public key line nor an existing .pub file`
and asks again. An empty name or email is asked for again. A folder that is
neither absolute nor starts with `~` stops the script with exit code 2. The
folder is resolved to its physical path, so a symlink is stored as the folder
it points to. A folder inside `$HOME` is stored as `~/...`, any other folder
as its absolute path.

Without a main key, a key for the second identity is used only in that
folder. It never becomes the main key.

The file is written with mode 600. With one identity it holds only `[user]`
and `[signing]`. With two identities and two `.pub` keys, it looks like this
(`~/src/personal` is an example folder):

```toml
[user]
name = "Jane Doe"
email = "jane@work.example"

[signing]
backend = "ssh"
behavior = "own"
key = "/Users/<you>/.ssh/id_ed25519_work.pub"
backends.ssh.program = "/usr/bin/ssh-keygen"
backends.ssh.allowed-signers = "~/.config/git/allowed_signers"

# Second identity for every repo under ~/src/personal (override elsewhere: sign-as personal)
[[--scope]]
--when.repositories = ["~/src/personal"]
[--scope.user]
email = "jane@personal.example"
[--scope.signing]
key = "/Users/<you>/.ssh/id_ed25519_personal.pub"
backends.ssh.program = "/usr/bin/ssh-keygen"
```

`./install.sh --dry-run` only prints that it would create the file. An
existing file is left alone and reported as `ok`. To answer the prompts
again, for example to add or drop the second identity, delete it and rerun
`./install.sh`.

## Run without prompts

Setting `DOTFILES_NAME` switches `install.sh` to environment variables for
every answer. This is how Claude Code runs it from
[SETUP_PROMPT.md](../../SETUP_PROMPT.md). One identity:

```sh
DOTFILES_NAME="Jane Doe" \
DOTFILES_EMAIL=jane@example.com \
DOTFILES_SIGNING_KEY=~/.ssh/id_ed25519.pub \
./install.sh
```

Two identities, with `~/src/personal` as the example folder:

```sh
DOTFILES_NAME="Jane Doe" \
DOTFILES_EMAIL=jane@work.example \
DOTFILES_SIGNING_KEY=~/.ssh/id_ed25519_work.pub \
DOTFILES_PERSONAL_DIR=~/src/personal \
DOTFILES_PERSONAL_EMAIL=jane@personal.example \
DOTFILES_PERSONAL_KEY=~/.ssh/id_ed25519_personal.pub \
./install.sh
```

`DOTFILES_PERSONAL_DIR` and `DOTFILES_PERSONAL_EMAIL` go together: setting
only one of them makes `install.sh` exit 2 with
`set DOTFILES_PERSONAL_EMAIL and DOTFILES_PERSONAL_DIR together, or neither`.
An empty `DOTFILES_EMAIL` makes it exit 2 as well. A key that is neither a
key line nor a public key file makes it exit 1 instead of asking again. Leave `DOTFILES_SIGNING_KEY` unset to skip signing.

With no terminal and no `DOTFILES_NAME`, `install.sh` copies
`jj/identity.example.toml` into place and prints a warning. Its `[signing]`
and `[[--scope]]` blocks are commented out, so jj keeps working but commits
are not signed until you fill in a real key and uncomment `[signing]`.
Replace the name and email before you commit anything. For a second
identity, uncomment the `[[--scope]]` block and set its folder to the
folder's physical path (no symlinks):

```sh
$EDITOR ~/.config/jj/conf.d/identity.toml
```

While the name is `Your Name` or the email is `you@work.example`,
`install.sh` does not copy them into git and prints `skip git identity`. The template's
`~/path/to/personal-repos` folder never becomes `DOTFILES_PERSONAL_DIR`.

## The git side

On the same run, `install.sh` mirrors the identity into git without
overwriting anything git already has:

- If git has no `user.signingkey` and you gave a main key, it sets
  `gpg.format ssh`, `user.signingkey`, `gpg.ssh.program`,
  `gpg.ssh.allowedSignersFile = ~/.config/git/allowed_signers`,
  `commit.gpgsign true` and `tag.gpgsign true` in the global config.
- It appends each public key to `~/.config/git/allowed_signers` as
  `<email> namespaces="git" <key>`, unless that email already has a line, so
  signatures verify locally. The file is kept at mode 600.
- With a second identity and no `includeIf` for its folder yet, it writes
  `user.email`, plus `user.signingkey` and `gpg.ssh.program` when you gave
  that folder a key, to `~/.config/git/personal.gitconfig`, and adds
  `includeIf "gitdir:<folder>/".path` pointing at it.
- If git has no global `user.email`, it sets `user.name` and `user.email` to
  the main identity: the values from this run, or on later runs the ones
  `jj config get` returns outside any repo. The second identity's email never
  ends up in the global git config, even when you run `install.sh` from
  inside its folder.

Check the result:

```sh
git config --global --get-regexp '^(user|gpg|commit|tag|includeif)\.'
cat ~/.config/git/allowed_signers
```

## Keys on each machine

The config refers to keys that are never in the repo. Each machine needs the
main key, either in an SSH agent such as the 1Password SSH agent or as a key
file on disk, and the second key if you use one, for example
`~/.ssh/id_ed25519_personal`.

For GitHub to mark commits as verified, add each public key under
**Settings → SSH and GPG keys → New SSH key** with the key type set to
**Signing Key**. A key added only as an authentication key does not count,
even when it is the same key.

With no signing key yet, leave the prompt empty, or remove the `[signing]`
section from `identity.toml`, and add it later.

## Override per repo with `sign-as`

`sign-as personal` switches one repo to the second identity, and `sign-as work`
returns it to the main identity. Use it for a repo outside the second
identity's folder that belongs to that identity, or for a main-identity repo
inside the folder:

```sh
cd ~/src/side-project
sign-as status       # current jj and git email, last 12 characters of each key
sign-as personal     # use the second identity in this repo
sign-as work         # remove the override, back to the main identity
```

`sign-as personal` reads `user.email`, `user.signingkey`, `gpg.ssh.program`
and `core.sshCommand` from `~/.config/git/personal.gitconfig`. With one
identity that file does not exist, and it refuses with
`no second identity set up: move ~/.config/jj/conf.d/identity.toml aside, re-run install.sh and answer yes to the second identity`.
It also refuses, asking you to fill in the file first, while it has no
`user.email`. Then it sets `user.email`, `signing.key` and
`signing.backends.ssh.program` with `jj config set --repo`, which every
workspace of the repo shares, and the matching keys with
`git config --local`. When that file has no `user.signingkey`, it unsets
the per-repo key and signer instead, so the main key signs. `sign-as work`
unsets all of them.

Both modes then update the author of `@` with
`jj metaedit --update-author -r @` when it no longer matches:

```text
jj:  jane@personal.example  key …ersonal.pub
     updated author of @
git: jane@personal.example  key …ersonal.pub
```

jj also prints a warning that the setting only affects future commits. The
`updated author of @` line means `sign-as` already handled `@`. Earlier
commits keep their author.

When signing fails, check `sign-as status`, make sure the SSH agent is
unlocked (1Password must be running for `op-ssh-sign`), and compare the key
in `identity.toml` with the agent's key. Agents are told to stop and report a
signing failure instead of working around it, see
[Claude Code](claude-code.md).
