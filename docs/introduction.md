# dotfiles

A macOS terminal setup for running several AI coding agents in parallel, each
in its own jj workspace.

Two agents in one checkout overwrite each other's files and mix their changes
into one diff. Here each agent gets a jj workspace of its own, a separate
directory next to the repo with its own working copy, sharing the repo's
history. You start an agent with `jwc <name>`, watch it in a Ghostty split,
review its changes from the main checkout and push them as a bookmark named
after the workspace. The rest of the setup exists to make that loop fast and
hard to get wrong.

It is written for one engineer on a Mac who runs Claude Code in several
splits at once, on services that talk to Redis and
Kafka. It assumes:

- macOS on Apple Silicon, with [Homebrew](https://brew.sh) at
  `/opt/homebrew`. On Intel, change `HOMEBREW_PREFIX` in `zsh/zshrc` and the
  path in `zsh/zprofile.snippet` before installing.
- Claude Code as the agent. The Brewfile installs it, and the rules in
  `claude/CLAUDE.md` are written for it.
- jj colocated with git in every repo you use with agents. Git, your IDE and
  CI keep working, and agents write history through jj.
- jj 0.46 or newer. From 0.46 `jj workspace add` creates a real git worktree
  for each workspace, which `jw` relies on.
- git 2.48 or newer. Each jj workspace is a git worktree with relative paths
  (`extensions.relativeWorktrees`), which older git cannot open. The Brewfile
  installs a current git, and so does recent Xcode.
- Docker or OrbStack, only if you want the local Redis, Kafka and Jaeger.

## The pieces

Ghostty is the terminal: splits on `cmd+d` and `cmd+shift+d`, 100 MB of
scrollback, and a system notification when an agent rings the bell or when a
command that ran longer than 30 seconds finishes in an unfocused split. zsh
loads fzf, zoxide, starship and mise, and sources five files of shell
functions: `jw`, `jwc`, `jws`, `jwst`, `jwl`, `jwrm`, `jsync`, `jpush` and
`jland` for workspaces,
`sign-as` for the commit identity, `infra` for the local stack, `reload`
to check every config and restart zsh, and the navi palette on `Ctrl-G`
with `navi-trust` and `navi-untrust`.
[Parallel agents](guides/parallel-agents.md) covers the workspace commands,
and [shell commands](reference/shell-commands.md) lists every one.

jj gets a small config: a `work()` revset for the latest non-empty change in
your stack, `jj stack`, `jj tug`, and `jj dft` for structural diffs through
difftastic. Agents get plain `jj diff --git`, because difftastic's output has
no `+` and `-` markers without colour.
[Review and land](guides/review-and-land.md) uses all of them, and
[jj config](reference/jj-config.md) has the definitions.

Claude Code gets global rules (jj instead of git, always `-m`, never push
unless asked), a status line with the workspace and change, a list of
read-only jj commands it may run without asking, and `JJ_EDITOR=false` so a
jj command that would open an editor fails at once.
[Claude Code](guides/claude-code.md) has the details.

mise holds global tools that behave the same everywhere, such as node LTS,
pnpm and gopls. Tools that must match CI belong in each project's
`mise.toml`. [Project tools](guides/project-tools.md) draws the line, and
[agents and PATH](explanation/agents-and-path.md) explains why Claude Code
has to start from the project directory to see them.

Your name, emails and signing keys stay in
`~/.config/jj/conf.d/identity.toml` on your machine. One identity for every
repo is the default. Optionally, a second identity covers every repo in one
folder you choose during install, such as personal projects next to a work
account.
[Identity and signing](guides/identity-and-signing.md) covers both and the
`sign-as` override.

`infra` runs Redis, Kafka, kafka-ui and Jaeger on loopback ports from one
Compose file. See [local infra](guides/local-infra.md).

## Where to go next

[Install](install.md) the setup, then follow
[getting started](getting-started.md) for a first session with two agents.
[Design](explanation/design.md) explains why it is built this way, and
[troubleshooting](troubleshooting.md) has the problems people hit first.
