# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

macOS (Apple Silicon) dotfiles for running several AI coding agents in parallel, each in its own jj workspace. `install.sh` symlinks the configs into `$HOME`, so the live files are the repo files.

## Commands

```sh
just check                       # lint + test + secrets + commits, the same as CI. Run before every commit
just lint                        # shellcheck, bats asserts, zsh -n, docker compose config, lychee --offline on all *.md
just test                        # bats tests
bats tests/jj.bats               # one suite
bats tests/jj.bats -f 'jpush'    # tests whose name matches a regex
just secrets                     # scripts/check-secrets.sh + gitleaks
just commits                     # Conventional Commits check on origin/main..HEAD
just drift                       # read-only: live files vs repo copies
./install.sh --dry-run           # never run install.sh for real unless asked: it writes to the real $HOME
```

Run `actionlint` after editing `.github/workflows/ci.yml`, because CI doesn't run it. `tests/navi.bats` skips when `navi` is missing.

## Architecture

- **`install.sh` is the single source of what goes where.** Each `^link <src> <dest>` line is also parsed by `just drift` and by `link_pairs` in `tests/helpers.bash`, so keep that one-line format when adding a link. Besides the links, it:
  - merges `claude/settings.fragment.json` into `~/.claude/settings.json` with jq. Fragment keys win, and `permissions.allow`/`deny` and each `hooks.<event>` list are unioned, so the user's own hooks survive.
  - appends `zsh/zprofile.snippet` (mise shims) to `~/.zprofile`.
  - writes the identity to `~/.config/jj/conf.d/identity.toml`: one identity, or two using a `[[--scope]]` keyed on `DOTFILES_PERSONAL_DIR`. It mirrors this into git (`includeIf.gitdir`, `~/.config/git/allowed_signers`).
  - writes `~/.config/dotfiles/config` (`DOTFILES_DIR`, `DOTFILES_PERSONAL_DIR`), which `zsh/zshrc` sources. Code and docs must not hard-code the repo path or the personal folder. Use these variables.
- **`claude/CLAUDE.md` is linked to `~/.claude/CLAUDE.md`.** It is the user's global instructions for every Claude session, not guidance for this repo. Editing it changes every agent's behaviour.
- **Claude Code hooks** live in `claude/` as linked scripts: `notify.sh` (`Notification` and `Stop`, a notification titled `<repo>/<workspace>` via the `terminalSequence` JSON output, since hooks have no `/dev/tty`) and `guard-push.sh` (`PreToolUse` on `Bash`, exit 2 blocks `git push`/`jj git push` when `where.sh` reports a jj workspace or git worktree). `session-context.sh` (`SessionStart`) tells the agent its repo and workspace. `statusline.sh` is the status line. `where.sh` decides repo, workspace, root and colour for all of them, for the zsh tab title and tint in `jj.zsh` and for starship, so change it there and not in each caller. Test them with JSON on stdin in `tests/hooks.bats`, `tests/statusline.bats` and `tests/where.bats`.
- **zsh**: `zsh/zshrc` sources `~/.config/zsh/{jj,sign,infra,reload,navi}.zsh` (the linked copies). The agent workspace commands (`jw`, `jwc`, `jws`, `jwst`, `jnext`, `jwl`, `jwrm`, `jsync`, `jpush`, `jland`) are in `zsh/jj.zsh`. Workspaces go in `<repo>-ws/<name>`, need jj 0.46+, get the `jw-pre-push` git hook (agents can't `git push` from a workspace, also from scripts), and copy untracked `.env*` files before running the project setup (skipped when `JW_NO_SETUP` is set). `sign-as` is in `sign.zsh`, `infra` (wraps `infra/compose.yaml`) is in `infra.zsh`, `reload` is in `reload.zsh`, and the navi `Ctrl-G` palette and per-project trusted `.navi/` are in `navi.zsh`.
- **navi cheats** (`navi/*.cheat`) follow rules enforced by `tests/navi.bats`, see CONTRIBUTING.md "Adding a workflow". Pickers run in bash, so they can't call the zsh functions. jj pickers pass `--ignore-working-copy`. Destructive infra entries are prefixed `[LOCAL ONLY]` and target localhost only.
- **Tests must never touch the real machine.** Every test calls `fake_home` in `setup`, which isolates HOME, git and jj config and unsets `DOTFILES_*`. Use `copy_repo` + `run_install` to run the installer against a copy, and `make_jj_repo`/`add_bare_remote` for jj fixtures under `BATS_TEST_TMPDIR`. Never configure real signing in a test. A known bug gets a `skip "BUG: ..."` test.
- **Docs** (`docs/`) use the Diátaxis layout (guides, reference, explanation). Every path, key, default and port in a reference page must match the code, so grep the docs whenever you change a value. `docs/explanation/design.md` records why each choice was made.

## Rules for changes

- **The repo is public.** Don't add real names, emails outside `example.com`/`.org`/`.net`/`*.example`, absolute home paths (write `~/` or `$HOME`), key bodies or 1Password references. `just secrets` and the CI history scan enforce this. A secret in any commit fails CI even after it's removed, so rewrite history before pushing.
- **Commits:** jj only, [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) with the area as scope, e.g. `fix(install): ...`, `feat(zsh): ...`, `docs: ...`, `test: ...`, `ci: ...`. Breaking changes use `!` plus a `BREAKING CHANGE:` footer. One scope per commit, signed, no attribution trailers. Full list of types and scopes is in CONTRIBUTING.md.
- **Prose** (README, CONTRIBUTING, docs): no em dashes, curly quotes, ellipsis characters or semicolons. Check with the human-writing skill's `scripts/check.py`.
- **`CHANGELOG.md`:** leave it alone, the maintainer writes it at release.

@.claude/wiz-claude.md
