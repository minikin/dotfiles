# Design

The setup exists to run several coding agents on one repo at the same time,
each in its own Ghostty split, and to review and land their work without
anything leaking between them, into a public repo, or onto the network. Most
choices below follow from that.

## Why jj workspaces over git worktrees

An agent needs its own working directory, or two agents edit the same files.
Both git worktrees and jj workspaces give it one. The difference is what
happens to the work.

A git worktree has to check out a branch that no other worktree has, or sit
on a detached HEAD. Until the agent runs `git add` and `git commit`, its edits
exist only as files in that directory. Delete the directory and they are
gone. To see what an agent did you `cd` there, or ask git to compare branches
that may not exist yet.

A jj workspace has its own working-copy change, `@`, in a repo every
workspace shares. jj snapshots the files into that change every time a jj
command runs, so the agent's edits are already commits before anyone asks for
one. From the main checkout, `jj log` shows every agent's change as
`<name>@`, and `jj diff -r fix-login@` reads it without leaving your
directory. `jj workspace remove` snapshots once more before it deletes the
directory, which is why `jwrm` loses only ignored files.

The rest of jj helps the same workflow. There is no staging area for an
agent to forget. Every operation is in `jj op log` and `jj undo` reverts it,
which matters when an agent ran a command you did not expect. A rebase that
conflicts records the conflict in the change and finishes, so moving five
agent stacks onto a new trunk never stops halfway. Bookmarks are needed only
to push, and `jpush` names them after the workspace.

Agents still need rules for jj: always `-m`, never an editor, no git writes.
`claude/CLAUDE.md` carries them, and `JJ_EDITOR=false` makes the editor case
fail at once instead of hanging the agent.

## Why colocated

`jj git init --colocate` puts `.jj/` next to an existing `.git/` and keeps
them in sync. Git tools see a normal repo on a detached HEAD: the IDE, `gh`,
CI, pre-commit hooks that read `git`, and anything else that never heard of
jj. A repo moves to jj in place, with no second clone, and moves back by
deleting `.jj/`.

Agents benefit too. Read-only git (`git status`, `git log`, `git blame`) is
something every model knows, and `claude/CLAUDE.md` allows it. Only the
writes go through jj. mise trust in the main checkout also extends to git
worktrees, so a new jj workspace needs no `mise trust` of its own.

## Why mise over direnv

direnv does one thing: it loads environment variables from an `.envrc` when
you enter a directory. A project here needs three: pinned tool versions that
match CI, environment variables such as `OTEL_EXPORTER_OTLP_ENDPOINT`, and a
`setup` task that a fresh workspace can run. A project's `mise.toml` holds all
three (`[tools]`, `[env]`, `[tasks]`), and `jw` already knows to run
`mise run setup` or `mise install` in a new workspace.

Trust is the other reason. direnv approves an `.envrc` by its path, so every
new workspace directory would need its own `direnv allow` before the agent in
it got its environment. mise trust carries over from the main checkout.

mise also has two ways to reach `PATH`: `mise activate` for interactive
shells, and shims for scripts and IDE tasks that never print a prompt. The
setup uses both. [Agents and PATH](agents-and-path.md) covers why that
matters for Claude Code.

## Why difftastic is opt-in

difftastic compares syntax trees, so a change that only reflows a function
shows as no change, and a renamed argument shows as one token, not a
rewritten line. For a human reading in colour that is the better diff.

An agent reads diffs as plain text. Piped without colour, difftastic's
side-by-side output has no `+` or `-` markers, and the two columns run into
each other. Agents misread it. So `jj diff` and `jj show` keep jj's own
format, `jj diff --git` is what `claude/CLAUDE.md` tells agents to use, and
difftastic sits behind `jj dft`, `jj dshow` and `git dft` for people.

The Claude Code settings deny any jj command containing `--tool` or
`--config`, because both can make jj run an arbitrary program. `jj dft` is
allowed by name, since its tool is fixed in `jj/config.toml`.

## Why identity lives outside the repo

The repo is public. A name, a work email, a personal email and the public
halves of two signing keys are enough to tie an employer to a private
account, and once pushed they stay in git history.

So `jj/config.toml` carries no `[user]` or `[signing]` at all. jj loads every
file in `~/.config/jj/conf.d/`, so `install.sh` writes the identity there,
mode 600, and never links it. Each machine gets its own, which also fits the
keys: one machine signs through the 1Password agent, another with a `.pub`
file and `ssh-keygen`.

The work and personal split lives in the same local file as a
`--when.repositories` scope on `~/repos/personal`, mirrored for git with an
`includeIf`. Placing a repo under that directory is the whole switch, and
`sign-as` covers the exceptions.

Two scanners keep it that way. `scripts/check-secrets.sh` runs in
`just check` on the working tree, with a local denylist for your own name
and employer that is itself never committed. gitleaks with `.gitleaks.toml`
scans the whole history in CI.

## Why symlinks and drift checks

A copied config drifts on the first edit: you change `~/.zshrc`, forget the
repo, and the next machine gets the old one. A symlink makes the live file
and the repo file the same file, so `jj st` in the repo shows every edit you
made from anywhere.

An app that saves its config by writing a new
file and renaming it over the old path replaces the link with a regular file,
and from then on edits go nowhere near the repo. Nothing announces it.
`just drift` reads the same `link` lines `install.sh` uses and reports each
destination as `linked`, `same (copy)`, `DIFFERS` or `missing`, without
changing anything. Running `install.sh` again backs the stray file up and
restores the link.

Two files are deliberately not links. Claude Code writes
`~/.claude/settings.json` itself, with your own permissions and options, so
`install.sh` merges the repo's fragment into it instead: the fragment's keys
win, the allow and deny lists are unioned, and everything else stays.
`~/.zprofile` is a file other installers append to as well, so the repo adds
its snippet once and leaves the rest alone.

## Why loopback-only infra

Docker publishes a port on every interface unless told otherwise. On a
laptop that means a Redis without a password and a Kafka with plaintext
listeners, reachable from any network the laptop joins.

`infra/compose.yaml` binds every port to `127.0.0.1` and `[::1]`. Both,
because some clients resolve `localhost` to `::1` first and would fail to
connect if only IPv4 were bound. `tests/infra.bats` fails if a port is
published anywhere else, so a new service cannot quietly widen it.

The stack mirrors production's Redis and Kafka closely enough to test
against, with Jaeger for traces. Kafka advertises `localhost:9092` to the
host and `kafka:19092` inside the Compose network, so `kcat` on the host and
kafka-ui in a container both reach it. Agents get the same endpoints, and
`claude/CLAUDE.md` limits their tools to local or dev endpoints and rules out
`infra reset`, `FLUSHALL` and topic deletion unless you ask.

## Why navi for saved workflows

The commands worth saving are the ones you run once a week and get wrong:
a Kafka consumer-lag query, a port-forward, a signature check on one
change. A shell alias hides the command, and history search finds it only
if you ran it recently with the same arguments. navi keeps each command
readable in a plain `.cheat` file, turns its arguments into fzf pickers fed
by live data, and its zsh widget writes the result into the prompt. It is
one Homebrew formula and needs no app or account.

`Ctrl-G` inserts the command and never runs it. You see the namespace, the
topic or the change ID before pressing Enter, which matters most for the
`[LOCAL ONLY]` and `[PERSONAL]` entries. Inserting into the prompt also
puts the command in your zsh, where `jw`, `jpush`, `infra` and `sign-as`
exist.

The pickers are another matter. navi runs every `$ var:` line in bash, which
has none of those zsh functions, so the pickers call `jj`, `kubectl`, `gh`
and `docker compose ... exec -T` directly. Every `jj` picker passes
`--ignore-working-copy`. Without it, opening the palette in a workspace
would snapshot the working copy, write an op log entry and, with signing
on, could ask 1Password for a signature, all to list some change IDs.

A repo's own `.navi/` folder is code that runs as soon as you open the
palette in it, because navi evaluates the pickers to build the lists. A
cloned repo could put anything there. So `zsh/navi.zsh` loads it only for a
trusted repo, the same deal as `mise trust` and `direnv allow`: your own
repos under `~/repos/personal` are trusted, and any other repo needs one
`navi-trust`. Trust is recorded for the main checkout, so new jj workspaces
inherit it, as they do for mise.
