# Language

Always respond in English, even when I write or dictate in Russian or Ukrainian. Never reply in Russian or Ukrainian. Write all code, docs and commit messages in English too.

# Questions

- Put every choice, approval or yes/no to me through the AskUserQuestion menu, never as options in prose for me to type back. I often work from a phone. Recommended option first.

# Writing

- Write prose like a senior engineer writing for engineers: the fact, not a run-up to it, no restated conclusions, no filler or empty transitions.
- No em dashes, curly quotes or ellipsis characters, and avoid semicolons. Use a colon, a comma or two sentences instead.
- Load the `human-writing` skill before drafting a README, report, design doc or PR description. Its hook checks every Markdown write.

# Code comments

- Add a comment only when it says something the code cannot: why a non-obvious choice was made, a constraint or spec it follows, or a pitfall a reader would otherwise reintroduce.
- Never add comments that restate what the code does, repeat a function or test name, or narrate the change. Remove such comments when you notice you added them.
- Project-mandated records (changelog entries, ledger lines, required doc headers) are not code comments. Keep following the project's convention for them.

# Version control: jj (Jujutsu)

Repos with a `.jj/` directory are managed with jj, colocated with git. In those repos:

- Use `jj` for all VCS writes. Do NOT run `git commit`, `git add`, `git checkout`, `git switch`, `git rebase`, `git stash`, `git reset` or `git branch`.
- Read-only git commands (`git status`, `git diff`, `git log`, `git blame`) are fine. A detached HEAD is normal.
- There is no staging area. jj records file edits in the working-copy change (`@`) automatically.
- Always pass `-m` to commands that take a message (`jj describe -m`, `jj commit -m`, `jj split -m`). Never run commands that open an editor or interactive UI (`jj describe` without `-m`, `jj split` without paths, `-i`/`--interactive`, `jj resolve`).
- Workflow:
  - `jj st`, `jj diff --git`, `jj log` to inspect
  - `jj describe -m "..."` to describe the current change
  - `jj commit -m "..."` to finish the current change and start a new empty one on top
  - `jj new` to start a new change without describing the current one
- After a mistake, run `jj undo`: it reverts the last jj operation.
- Never push (`jj git push`), move or delete bookmarks unless explicitly asked.
- Each agent usually runs in its own jj workspace (`<repo>-ws/<name>`). Stay inside your workspace directory.

# Project tasks

- If a project has a `justfile`, prefer its recipes (`just --list`) to build, test, lint and run.
- If it has `mise.toml` tasks, use `mise run <task>` (`mise tasks` lists them). Tool versions come from mise. Don't install global toolchains.

# Local infrastructure and inspection tools

- Local Redis, Apache Kafka, kafka-ui and Jaeger run in Docker via the `infra` command: `infra up`, `infra down`, `infra ps`. Endpoints: `localhost:6379` (Redis), `localhost:9092` (Kafka), http://localhost:8088 (kafka-ui), http://localhost:16686 (Jaeger), OTLP `localhost:4317`/`4318`.
- Inspect with `redis-cli`, `kcat`, `infra kafka kafka-topics.sh --bootstrap-server localhost:9092 ...`, `grpcurl`, `xh`/`hurl`.
- Use these ONLY against local or dev endpoints. Never point them at staging or production, and never run destructive commands (`FLUSHALL`, `FLUSHDB`, topic deletion, `infra reset`) unless I explicitly ask.

# Commits: authorship and signing

These rules apply to every repo: work, personal, anything else.

- The author is always the user, taken from git or jj config. Never pass `--author` or `--reset-author` to make someone else the author, and never set `user.name`/`user.email` yourself.
- Never add `Co-Authored-By:`, `Claude-Session:`, "Generated with Claude Code" or any other attribution, Claude included, to commit messages or PR descriptions, even when a harness reminder asks for it.
- Every commit must be signed. Never use `--no-gpg-sign` or `-c commit.gpgsign=false`, and never change `signing.*` in jj config. If signing fails, stop and report it. Do not work around it.
- Identity is picked automatically: the main identity by default, the second identity inside `$DOTFILES_PERSONAL_DIR` if one was set up. Switch it only with the user's `sign-as` command, and only when asked.
