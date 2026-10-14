# Language

Always respond in English, even when I write or dictate in Russian or Ukrainian. Never reply in Russian or Ukrainian. All code, docs and commit messages are in English too.

# Version control: jj (Jujutsu)

Repos with a `.jj/` directory are managed with jj (colocated with git). In those repos:

- Use `jj` for all VCS writes. Do NOT run `git commit`, `git add`, `git checkout`, `git switch`, `git rebase`, `git stash`, `git reset` or `git branch`.
- Read-only git commands (`git status`, `git diff`, `git log`, `git blame`) are fine. A detached HEAD is normal.
- There is no staging area: file edits are recorded in the working-copy change (`@`) automatically.
- Always pass `-m` to commands that take a message (`jj describe -m`, `jj commit -m`, `jj split -m`). Never run commands that open an editor or interactive UI (`jj describe` without `-m`, `jj split` without paths, `-i`/`--interactive`, `jj resolve`).
- Workflow:
  - `jj st`, `jj diff --git`, `jj log` to inspect
  - `jj describe -m "..."` to describe the current change
  - `jj commit -m "..."` to finish the current change and start a new empty one on top
  - `jj new` to start a new change without describing the current one
- If you make a mistake, `jj undo` reverts the last jj operation.
- Never push (`jj git push`) or move/delete bookmarks unless explicitly asked.
- Each agent usually runs in its own jj workspace (`<repo>-ws/<name>`). Stay inside your workspace directory.

# Project tasks

- If a project has a `justfile`, prefer its recipes (`just --list`) for build/test/lint/run.
- If it has `mise.toml` tasks, use `mise run <task>` (`mise tasks` to list). Tool versions come from mise; don't install global toolchains.

# Local infrastructure and inspection tools

- Local Redis, Apache Kafka, kafka-ui and Jaeger run in Docker via the `infra` command: `infra up`, `infra down`, `infra ps`. Endpoints: `localhost:6379` (Redis), `localhost:9092` (Kafka), http://localhost:8088 (kafka-ui), http://localhost:16686 (Jaeger), OTLP `localhost:4317`/`4318`.
- Inspect with `redis-cli`, `kcat`, `infra kafka kafka-topics.sh --bootstrap-server localhost:9092 ...`, `grpcurl`, `xh`/`hurl`.
- Use these ONLY against local or dev endpoints. Never point them at staging or production, and never run destructive commands (`FLUSHALL`, `FLUSHDB`, topic deletion, `infra reset`) unless I explicitly ask.

# Commits: authorship and signing

Applies to every repo (work, personal, anything else).

- The author is always the user, taken from git/jj config. Never pass `--author`, `--reset-author` to someone else, or set `user.name`/`user.email` yourself.
- Never add `Co-Authored-By:` or other attribution trailers (including Claude) to commit messages or PR descriptions.
- Every commit must be signed. Never use `--no-gpg-sign`, `-c commit.gpgsign=false`, or change `signing.*` in jj config. If signing fails, stop and report it; do not work around it.
- Identity is picked automatically (work by default, personal under `~/repos/personal/`); switch only via the user's `sign-as` command, and only when asked.
