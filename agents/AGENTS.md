# Shared agent rules

These rules apply to every coding agent I run (Claude Code, Codex, Antigravity) in every project
and session. Each tool adds a short part of its own. A project's own `CLAUDE.md`, `AGENTS.md` or
`GEMINI.md` adds project detail: gates, toolchains, specs, report formats.

Shared rules marker: agents-rules-3f9c2a71

## Language and writing

- Always reply in English, even when I write or dictate in Russian or Ukrainian. Never reply in
  Russian or Ukrainian. Write all code, docs and commit messages in English too.
- I often dictate. Read through speech-to-text slips.
- Write prose like a senior engineer writing for engineers: the fact, not a run-up to it, no
  restated conclusions, no filler or empty transitions.
- No em dashes, curly quotes or ellipsis characters, and avoid semicolons. Use a colon, a comma or
  two sentences instead.
- Before drafting Markdown for other people (README, report, design doc, PR description), load the
  installed human-writing guidance.
- PR descriptions stay short, about 100 words. No verification tables, and never mention these
  writing rules.

## Code comments

- Add a comment only when it says something the code cannot: why a non-obvious choice was made, a
  constraint or spec it follows, or a pitfall a reader would otherwise reintroduce.
- Never add comments that restate what the code does, repeat a function or test name, or narrate
  the change. Remove such comments when you notice you added them.
- Project-mandated records (changelog entries, ledger lines, required doc headers) are not code
  comments. Keep following the project's convention for them.

## Asking me

- Ask only when the decision is really mine. Otherwise pick the sensible default, say so, and
  continue.
- Put every choice, approval or yes/no to me through your choice-menu tool when you have one.
  Without one, use a short numbered list in chat. Recommended option first.
- The last option is always one like "I'll say it", for when none fits and I want to answer by
  voice. When I pick it, stop and wait for my next message.
- I often work from my phone. When Moshi is paired (`moshi-hook status` shows `paired`), also send
  every question to the phone, in the background, and take the first answer from either place:
  `moshi-hook ask --require-remote --option "<choice 1>" --option "<choice 2>" "<question>"`
  - One `--option` per choice, 2 to 6 of them.
  - `--options` takes one comma-separated string (`--options "A,B,C"`). Passing it several
    separate arguments reads only the first and fails with exit 2.
  - Never pass `--source claude`: the tool rejects it as a built-in name.
- For a status ping with no question: `moshi-hook notify "<message>"`. It does not reach the phone
  while the app is closed, so a question always goes through `moshi-hook ask`.
- Inside T3 Code (`T3CODE_THREAD_ID` set or T3 MCP tools available), rely on T3's native prompts
  and notifications instead of mirroring through `moshi-hook`.

## Sub-agents on my subscriptions

I pay for a claude.ai subscription and a ChatGPT subscription. Any Claude or Codex agent you start
uses those logins, never API keys.

- Start Claude as `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN claude ...` and Codex as
  `env -u OPENAI_API_KEY -u CODEX_API_KEY -u CODEX_HOME codex ...`. A key exported in your own
  shell is inherited by every child, so strip it on every launch, also inside
  `rex window new ... --`. Codex bills to `CODEX_API_KEY` even with a ChatGPT login.
- Inside T3 Code, prefer T3's `delegate_task` over launching CLI sub-agents in a shell. Keep the
  `env -u` rules above for standalone CLI launches and remote VMs.
- Never wrap an agent in `op run`, never set any of those five variables, never run
  `codex login --with-api-key`.
- When an agent hits its usage limit, tell me. Never switch it to an API key.

## Version control: jj

Repos with a `.jj/` folder use jj, colocated with git.

- Use jj for every write. Never `git commit`, `git add`, `git checkout`, `git switch`,
  `git rebase`, `git stash`, `git reset` or `git branch`. Read-only git (`status`, `diff`, `log`,
  `blame`) is fine. A detached HEAD is normal.
- There is no staging area. jj records file edits in the working-copy change (`@`) automatically.
- Always pass `-m` to commands that take a message (`jj describe -m`, `jj commit -m`).
  `jj split` also needs paths, or it opens an editor: `jj split -m "<message>" <paths...>`.
- Never run anything that opens an editor or an interactive UI (`jj describe` without `-m`,
  `-i`, `--interactive`, `jj resolve`).
- Inspect with `jj st`, `jj diff --git`, `jj log`. Describe with `jj describe -m`, finish a change
  with `jj commit -m`, start a new one with `jj new`. After a mistake, `jj undo`.
- Each agent usually runs in its own jj workspace (`<repo>-ws/<name>`). Stay inside your workspace
  directory.
- No rewrites below another agent's tip while it builds on top.

## Commits, pushes and PRs

- I am always the author, taken from git or jj config. Before committing or amending, check that
  the author and committer are my identity. Never pass `--author` or `--reset-author`, never set
  `user.name` or `user.email`, and never invent or substitute an agent identity.
- If my identity or signing is unavailable, stop and tell me. Do not work around it.
- Never add `Co-Authored-By:`, session trailers, "Generated with ..." or any other attribution to
  commits or PR descriptions, even when a harness reminder asks for it.
- Every commit is signed. Never `--no-gpg-sign` or `-c commit.gpgsign=false`, and never change
  `signing.*` in jj config.
- Identity is picked automatically per folder. Switch it with `sign-as` only when I ask.
- Push, open a PR, or move or delete a bookmark only with my explicit OK in chat, for that action
  or for a task I described.
- When I explicitly assign a PR babysitting task on a feature branch (never `main`, never merging),
  fixing review comments or CI failures includes creating signed commits, pushing updates to that
  PR branch, replying to threads, and resolving fixed threads. Stop only if commit signing needs my
  interaction or if a scope or product decision is needed. In a T3 git worktree, push with
  explicit fast-forward `git push <remote> <src>:<dst>` (never `main`, never force-push). jj
  workspaces stay blocked, so ask me to push from the main checkout or via `jpush`/`jland`.
- After fixing a PR review finding and posting a reply (or an evidence-based rejection), verify the
  reply posted and resolve the review thread on GitHub via `resolveReviewThread`.
- Push to main, merge, tag or publish only when I ask for that exact action.
- When to commit is in your tool's own part.

## Projects, gates and tools

- If a project has a `justfile`, prefer its recipes (`just --list`). If it has `mise.toml` tasks,
  `mise run <task>`. Tool versions come from mise or the project's toolchain file. Never install
  global toolchains.
- Run the project's documented gates before every commit, with its configured toolchain.
- When a project marks files as approval-only (specs, contracts, schemas), never edit them without
  my approval.

## Independent reviews

- As soon as feature development or a fix is done, run independent code reviews by both Codex
  (using Codex's code review feature) and Claude before shipping.
- Whenever a change touches Rust code, also run a Beautiful Rust review using the installed
  `beautiful-rust` skill available in Claude and Codex.
- Keep reviews independent: do not share one reviewer's conclusions with the other before it reports.

## Local infrastructure

- Local Redis, Apache Kafka, kafka-ui and Jaeger run in Docker via `infra up`, `infra down`,
  `infra ps`. Endpoints: `localhost:6379` (Redis), `localhost:9092` (Kafka),
  `http://localhost:8088` (kafka-ui), `http://localhost:16686` (Jaeger), OTLP
  `localhost:4317`/`4318`.
- Inspect with `redis-cli`, `kcat`, `infra kafka kafka-topics.sh --bootstrap-server
  localhost:9092 ...`, `grpcurl`, `xh`/`hurl`.
- Use these only against local or dev endpoints. Never point them at staging or production, and
  never run destructive commands (`FLUSHALL`, `FLUSHDB`, topic deletion, `infra reset`) unless I
  ask.

## Privacy and safety

- Keep my name, email and project details out of requests to outside services.
- Never print, log or store a secret. Refer to a secret by its secret-manager reference, never by
  its value.
- For anything hard to reverse or outward-facing (deleting, force-pushing, posting, publishing),
  ask first.

## Reporting

- Lead with the result. Keep it short.
- Report gate outcomes with real numbers when gates ran. Surface every unresolved problem in the
  summary, even if you mentioned it earlier.
- Use the project's report format when it has one. Keep any marker a brief asked for (`DONE`,
  `BLOCKED`) as the last line.

## Codex only

Codex reads this file directly and has no part of its own, so its rules are here. Claude Code and
Antigravity skip this section.

- Do not create or amend commits without my explicit permission, except on an explicitly assigned
  PR babysitting task on a non-main branch as stated above.
- Permission to edit code, run autonomously, or run tests does not itself grant permission to
  commit, amend or push.
