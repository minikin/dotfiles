# Commit identity and signing

Identity and signing keys are not in the repo. They live in
`~/.config/jj/conf.d/identity.toml`, which jj loads on top of the linked
`~/.config/jj/config.toml`. `install.sh` writes it on the first run, along
with matching git config. Work is the default identity, repos under
`~/repos/personal` use the personal one, and `sign-as` overrides either per
repo. The install steps around it are in [Install](../install.md), the
script itself in [install.sh](../reference/install-sh.md).

| Where the repo is | Identity | Source |
|---|---|---|
| Anywhere | Work | `[user]` and `[signing]` in `identity.toml` |
| Under `~/repos/personal`, including its `<repo>-ws` workspaces | Personal | the `--when.repositories = ["~/repos/personal"]` scope in `identity.toml` |
| A repo where you ran `sign-as personal` | Personal | per-repo jj config and local git config |

`signing.behavior = "own"` signs every commit you author, including the ones
agents make in your name and working-copy snapshots.

## Create `identity.toml`

On an interactive run, if the file is missing, `./install.sh` asks:

| Prompt | What to enter |
|---|---|
| `Full name:` | `Jane Doe` |
| `Default (work) email:` | `jane@work.example` |
| `Signing key` | a public key line (`ssh-ed25519 AAAA...`) or a path to a `.pub` file. Empty means no `[signing]` section |
| `Personal email for repos under ~/repos/personal` | `jane@personal.example`. Empty skips the personal scope and the next prompt |
| `Personal signing key` | a public key line or a `.pub` path. Empty means the scope inherits the default key |

The key input decides the signer:

- A public key line (`ssh-*`, `ecdsa-*`, `sk-*`) is signed through an agent.
  `install.sh` uses `/Applications/1Password.app/Contents/MacOS/op-ssh-sign`
  when it is executable, otherwise `/usr/bin/ssh-keygen`.
- A path to a `.pub` file is signed with `/usr/bin/ssh-keygen`. A leading `~`
  is expanded, and the absolute path goes into the file.

Anything else prints `is neither a public key line nor an existing .pub file`
and asks again. The file is written with mode 600. With two `.pub` keys, it
looks like this:

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

# Personal identity for repos under ~/repos/personal (override elsewhere: sign-as personal)
[[--scope]]
--when.repositories = ["~/repos/personal"]
[--scope.user]
email = "jane@personal.example"
[--scope.signing]
key = "/Users/<you>/.ssh/id_ed25519_personal.pub"
backends.ssh.program = "/usr/bin/ssh-keygen"
```

`./install.sh --dry-run` only prints that it would create the file. An
existing file is left alone and reported as `ok`. To answer the prompts
again, delete it and rerun `./install.sh`.

## Run without prompts

Setting `DOTFILES_NAME` switches `install.sh` to environment variables for
every answer. This is how Claude Code runs it from
[SETUP_PROMPT.md](../../SETUP_PROMPT.md):

```sh
DOTFILES_NAME="Jane Doe" \
DOTFILES_EMAIL=jane@work.example \
DOTFILES_SIGNING_KEY=~/.ssh/id_ed25519_work.pub \
DOTFILES_PERSONAL_EMAIL=jane@personal.example \
DOTFILES_PERSONAL_KEY=~/.ssh/id_ed25519_personal.pub \
./install.sh
```

In this mode a key that is neither a key line nor a `.pub` file makes
`install.sh` exit 1 instead of asking again. Leave `DOTFILES_SIGNING_KEY` or
`DOTFILES_PERSONAL_EMAIL` unset to skip signing or the personal identity.

With no terminal and no `DOTFILES_NAME`, `install.sh` copies
`jj/identity.example.toml` into place and prints a warning. Replace its
placeholders before you commit anything:

```sh
$EDITOR ~/.config/jj/conf.d/identity.toml
```

While the placeholders are there, `install.sh` does not copy the name and
email into git and prints `skip git identity`.

## The git side

On the same run, `install.sh` mirrors the identity into git without
overwriting anything git already has:

- If git has no `user.signingkey` and you gave a key, it sets
  `gpg.format ssh`, `user.signingkey`, `gpg.ssh.program`,
  `gpg.ssh.allowedSignersFile = ~/.config/git/allowed_signers`,
  `commit.gpgsign true` and `tag.gpgsign true` in the global config.
- It appends each public key to `~/.config/git/allowed_signers` as
  `<email> namespaces="git" <key>`, unless that email already has a line, so
  signatures verify locally.
- If you gave a personal email and there is no `includeIf` for it yet, it
  writes `user.email`, plus `user.signingkey` and `gpg.ssh.program` when you
  gave a personal key, to `~/.config/git/personal.gitconfig`, and adds
  `includeIf "gitdir:~/repos/personal/".path` pointing at it.
- If git has no global `user.email`, it copies `user.name` and `user.email`
  from jj.

Check the result:

```sh
git config --global --get-regexp '^(user|gpg|commit|tag|includeif)\.'
cat ~/.config/git/allowed_signers
```

## Keys on each machine

The config refers to keys that are never in the repo. Each machine needs the
work key, either in an SSH agent such as the 1Password SSH agent or as a key
file on disk, and the personal key if you use one, for example
`~/.ssh/id_ed25519_personal`.

For GitHub to mark commits as verified, add each public key under
**Settings → SSH and GPG keys → New SSH key** with the key type set to
**Signing Key**. A key added only as an authentication key does not count,
even when it is the same key.

With no signing key yet, leave the prompt empty, or remove the `[signing]`
section from `identity.toml`, and add it later.

## Override per repo with `sign-as`

For a personal project outside `~/repos/personal`, or a work repo inside it:

```sh
cd ~/repos/side-project
sign-as status       # current jj and git email, last 12 characters of each key
sign-as personal     # use the personal identity in this repo
sign-as work         # remove the override, back to the default
```

`sign-as personal` reads `user.email`, `user.signingkey`, `gpg.ssh.program`
and `core.sshCommand` from `~/.config/git/personal.gitconfig`. It refuses,
asking you to fill in that file first, while it has no `user.email`. Then it sets `user.email`, `signing.key` and
`signing.backends.ssh.program` with `jj config set --repo`, which every
workspace of the repo shares, and the matching keys with
`git config --local`. `sign-as work` unsets all of them.

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
