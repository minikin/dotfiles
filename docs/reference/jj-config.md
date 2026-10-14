# jj configuration

jj reads two files from this setup:

| File                                   | Source                          | Holds                                    |
| -------------------------------------- | ------------------------------- | ---------------------------------------- |
| `~/.config/jj/config.toml`             | link to `jj/config.toml`        | UI default, revset aliases, command aliases, difftastic tool. No identity. |
| `~/.config/jj/conf.d/identity.toml`    | written by `install.sh`, local only | Name, emails, signing.               |

jj also loads every `*.toml` in `~/.config/jj/conf.d/`, so the identity
file needs no include line. Per-repo settings that `sign-as` writes (`jj config set --repo`) override
both.

## ui

| Key                  | Value   | Effect                      |
| -------------------- | ------- | --------------------------- |
| `ui.default-command` | `"log"` | Bare `jj` runs `jj log`.    |

## Revset aliases

| Alias                  | Definition                                  | Meaning                                                                  |
| ---------------------- | ------------------------------------------- | ------------------------------------------------------------------------ |
| `work()`               | `heads(::@ & mutable() & ~empty())`         | The newest non-empty mutable change at or below `@`. After `jj commit` this is the change you just finished, not the empty `@` on top. |
| `closest_bookmark(to)` | `heads(::to & bookmarks() & mutable())`     | The nearest bookmark at or below `to` that sits on a mutable change. Trunk is immutable, so `main` never matches. |

`jpush` pushes `work()`. `jj tug` moves `closest_bookmark(@)` to `work()`.

## Aliases

| Alias       | Definition (`[aliases]`)                                                    | Equivalent command                                        |
| ----------- | --------------------------------------------------------------------------- | --------------------------------------------------------- |
| `jj tug`    | `["bookmark", "move", "--from", "closest_bookmark(@)", "--to", "work()"]`   | `jj bookmark move --from 'closest_bookmark(@)' --to 'work()'` |
| `jj stack`  | `["log", "-r", "trunk()::@ \| @::"]`                                        | `jj log -r 'trunk()::@ \| @::'`                           |
| `jj dft`    | `["diff", "--tool", "difft"]`                                               | `jj diff --tool difft`                                    |
| `jj dshow`  | `["show", "--tool", "difft"]`                                               | `jj show --tool difft`                                    |

Arguments after an alias are appended: `jj dft -r fix-login@`,
`jj dshow <change-id>`.

When no mutable bookmark is below `@`, `jj tug` has nothing to move. In a
fresh workspace created from `trunk()` that is the expected result: `main`
stays where it is. `tests/jj.bats` checks this.

`jj stack` shows trunk, every change between trunk and `@`, and anything
above `@`.

## merge-tools.difft

```toml
[merge-tools.difft]
diff-args = ["--color=always", "$left", "$right"]
```

| Key         | Value                                    | Effect                                                  |
| ----------- | ---------------------------------------- | ------------------------------------------------------- |
| `diff-args` | `["--color=always", "$left", "$right"]`  | jj runs `difft --color=always <left dir> <right dir>`. The program name defaults to the table name, `difft`. |

difftastic is used only through `jj dft`, `jj dshow` or an explicit
`--tool difft`. `ui.diff-formatter` is not set, so `jj diff` and `jj show`
print jj's own format. The Claude Code settings deny any jj command
containing `--tool`, and allow `jj dft`. See
[Design](../explanation/design.md#why-difftastic-is-opt-in).

## identity.toml

`~/.config/jj/conf.d/identity.toml` is never in the repo. `install.sh` writes
it on the first run, mode 600, from prompts or `DOTFILES_*` variables (see
[install.sh](install-sh.md#configjjconfdidentitytoml)). The template is
`jj/identity.example.toml`.

```toml
[user]
name = "Your Name"
email = "you@work.example"

[signing]
backend = "ssh"
behavior = "own"
key = "ssh-ed25519 AAAA...your-work-key"
backends.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
backends.ssh.allowed-signers = "~/.config/git/allowed_signers"

[[--scope]]
--when.repositories = ["~/repos/personal"]
[--scope.user]
email = "you@personal.example"
[--scope.signing]
key = "~/.ssh/id_ed25519_personal.pub"
backends.ssh.program = "/usr/bin/ssh-keygen"
```

| Key                                       | Section             | Value from `install.sh`                                     | Required |
| ----------------------------------------- | ------------------- | ----------------------------------------------------------- | -------- |
| `user.name`                               | `[user]`            | Full name                                                   | yes      |
| `user.email`                              | `[user]`            | Default (work) email                                        | yes      |
| `signing.backend`                         | `[signing]`         | `"ssh"`                                                     | with signing |
| `signing.behavior`                        | `[signing]`         | `"own"`: sign every commit whose author is you              | with signing |
| `signing.key`                             | `[signing]`         | Public key line, or path to a `.pub` file                   | with signing |
| `signing.backends.ssh.program`            | `[signing]`         | `op-ssh-sign` for a key line when 1Password is installed, else `/usr/bin/ssh-keygen` | with signing |
| `signing.backends.ssh.allowed-signers`    | `[signing]`         | `"~/.config/git/allowed_signers"`                           | with signing |
| `--when.repositories`                     | `[[--scope]]`       | `["~/repos/personal"]`                                      | with a personal email |
| `user.email`                              | `[--scope.user]`    | Personal email                                              | with a personal email |
| `signing.key`                             | `[--scope.signing]` | Personal key                                                | with a personal key |
| `signing.backends.ssh.program`            | `[--scope.signing]` | Signer for the personal key                                 | with a personal key |

Without `[signing]`, commits are not signed. Without `[--scope.signing]`, the
personal scope signs with the default key.

`--when.repositories` matches a repo by its path prefix, so the scope also
covers jj workspaces of personal repos, which live in
`~/repos/personal/<repo>-ws/`.

`signing.behavior = "own"` signs every commit you author when jj writes it,
including working-copy snapshots and commits an agent makes in your name.
Commits authored by someone else are left as they are.
