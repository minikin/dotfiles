# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

The first release: a macOS (Apple Silicon) terminal setup for running
several coding agents on one repo at once, each in its own jj workspace and
Ghostty split.

### Added

- **Ghostty config** (`ghostty/config`). JetBrainsMono Nerd Font Mono 13,
  Catppuccin Mocha and Latte by system appearance, 100 MB scrollback, left
  Option as Alt, a global `` Cmd+` `` quick terminal, split keys
  (`Cmd+D`, `Cmd+Shift+D`, `Cmd+Alt+H/J/K/L`, zoom, equalize) and
  `Cmd+Shift+S` to write the screen to a file and paste its path. A bell
  in any split notifies, and a command over 30 seconds in an unfocused
  split notifies when it ends. See
  [Keybindings](docs/reference/keybindings.md).
- **zsh** (`zsh/zshrc`). Completions including jj's dynamic ones,
  autosuggestions, syntax highlighting, fzf (`Ctrl-R`, `Ctrl-T`, `Alt-C`,
  `**<Tab>`), zoxide (`z`, `zi`), and a starship prompt with a jj segment
  that shows the change ID, bookmarks, conflict and empty markers and the
  description.
- **Agent workspaces** (`zsh/jj.zsh`). `jw` creates a jj workspace at
  `<repo>-ws/<name>`, copies untracked `.env*` and `mise.local.toml` files
  from the main checkout and runs the project's setup (`just setup`,
  `mise run setup`, or `mise install` and the lockfile install). `jwc` also
  starts Claude Code. `jws` switches with fzf, `jwl` lists, `jwrm` removes
  and keeps the changes, and `jpush` pushes `work()` as a bookmark named
  after the workspace. See [Shell commands](docs/reference/shell-commands.md).
- **jj config** (`jj/config.toml`). Bare `jj` runs `jj log`. Revset aliases
  `work()` and `closest_bookmark()`, aliases `tug`, `stack`, `dft` and
  `dshow`, and difftastic as an opt-in diff tool. See
  [jj configuration](docs/reference/jj-config.md).
- **mise** (`mise/config.toml`, `zsh/zprofile.snippet`). Global `node` LTS,
  `pnpm`, `gopls`, `dlv`, `gotestsum` and `govulncheck`. `mise activate` in
  interactive shells and shims in `~/.zprofile` for scripts and IDE tasks.
- **Local infrastructure** (`infra/compose.yaml`, `zsh/infra.zsh`). Redis 8,
  Apache Kafka 4.1.0 in KRaft mode, kafka-ui and Jaeger with OTLP, driven by
  `infra up`, `down`, `reset`, `ps`, `logs` and `infra kafka <script>`.
- **Saved workflows** (`navi/`, `zsh/navi.zsh`). `Ctrl-G` opens a navi
  palette of saved commands for agent workspaces, jj, local infra,
  Kubernetes, Go and TypeScript, and the dotfiles themselves. Arguments
  come from live pickers, and the command is inserted into the prompt, not
  run. Destructive infra entries are labelled `[LOCAL ONLY]` and a direct
  push to main `[PERSONAL]`. A repo's own `.navi/` folder loads only when the
  repo is under `~/repos/personal` or trusted with `navi-trust`.
  `tests/navi.bats` checks every entry. See
  [Saved workflows](docs/guides/workflows.md).
- **Commit identity** (`install.sh`, `zsh/sign.zsh`). On the first run
  `install.sh` asks for a name, a work email and signing key, and an
  optional personal email and key for every repo under `~/repos/personal`.
  It takes the same values from `DOTFILES_NAME`, `DOTFILES_EMAIL`,
  `DOTFILES_SIGNING_KEY`, `DOTFILES_PERSONAL_EMAIL` and
  `DOTFILES_PERSONAL_KEY` when there is no terminal. Every commit you author
  is SSH-signed, through 1Password's `op-ssh-sign` for a key line or
  `ssh-keygen` for a `.pub` file. git gets the same identity, signing,
  `allowed_signers` and an `includeIf` for the personal directory. `sign-as
  work|personal|status` overrides one repo.
- **Claude Code integration** (`claude/`). Global rules in `CLAUDE.md` (jj
  instead of git writes, always `-m`, local infra only, never change
  authorship or bypass signing), a status line with the workspace, change and
  model, and a settings fragment that allows read-only jj commands, denies
  `--tool` and `--config`, and sets `JJ_EDITOR=false`.
- **install.sh**. Symlinks every config, backs up what it replaces as
  `<file>.bak-<timestamp>`, appends the mise line to `~/.zprofile` and merges
  the Claude Code settings. `--dry-run` prints every step. See
  [install.sh](docs/reference/install-sh.md).
- **`SETUP_PROMPT.md`**, a prompt that has Claude Code install and verify
  the setup on a new Mac.
- **justfile**. `just check` runs lint (shellcheck, `zsh -n`,
  `docker compose config`, an offline link check), the bats tests and the
  secret scan. `just drift` compares each live file with the repo copy.
- **Tests** (`tests/`). bats suites for `install.sh`, the workspace
  commands, the status line and the Compose file, each in a fake `HOME`
  with jj and git reading only test config.
- **CI** (`.github/workflows/ci.yml`). `just check` on macOS, and a gitleaks
  scan of the full git history on Linux.
- Documentation in `docs/`: introduction, install, getting started,
  guides, reference, explanation and troubleshooting. `CONTRIBUTING.md` and
  issue forms for bugs and feature requests.

### Changed

- The command cheatsheet moved from `CHEATSHEET.md` to
  [docs/reference/cheatsheet.md](docs/reference/cheatsheet.md), and the
  usage guide in `docs/GUIDE.md` is split into the pages under `docs/`.

### Fixed

- `install.sh` merges the Claude Code settings into a temp file and replaces
  `settings.json` only on success, so invalid JSON or a `jq` failure never
  leaves it truncated. An empty file counts as `{}`.
- `install.sh` leaves a destination alone when it already resolves to the
  repo file, including through a parent directory that links into the repo,
  so it never renames the repo's own file into a backup.
- `install.sh` moves aside Ghostty's
  `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`,
  which Ghostty reads after `~/.config/ghostty/config` and which silently
  overrode it.
- `jw` recreates a workspace whose directory was deleted by hand, by
  forgetting the stale jj entry and pruning git's worktree first.
- `jpush` refuses to push to a trunk bookmark or an immutable one, and
  `closest_bookmark()` considers only mutable bookmarks, so `jj tug` never
  moves `main` onto agent work.

### Security

- No identity in the repo. Names, emails and signing keys live in
  `~/.config/jj/conf.d/identity.toml` (mode 600) and the local git config.
  `jj/identity.example.toml` holds placeholders only.
- `scripts/check-secrets.sh`, run by `just secrets` and `just check`, fails
  on email addresses outside reserved example domains, absolute home paths,
  private key headers, full SSH public keys, 1Password references, and any
  string in a local denylist (`~/.config/dotfiles/denylist.txt`, never
  committed).
- `.gitleaks.toml` adds the same personal-data rules to gitleaks' defaults,
  and CI runs gitleaks 8.30.1, checksum-verified, over every commit
  reachable from the checked-out ref.
- Every port in `infra/compose.yaml` binds to `127.0.0.1` and `[::1]` only,
  and a test fails if one does not.
- The Claude Code settings deny `jj` commands with `--tool` or `--config`,
  which can run arbitrary programs.

<!-- Version links -->

[Unreleased]: https://github.com/minikin/dotfiles/commits/main
