# Files

Every file in the repo, where it ends up, and what it configures. "Linked"
means `install.sh` creates a symlink to the repo file, so editing the live
file edits the repo. `just drift` reports the state of each linked file.

## Installed configuration

| Repo file                       | Installed as                                | Configures                                                                                     |
| ------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `ghostty/config`                | linked: `~/.config/ghostty/config`          | Ghostty: JetBrainsMono Nerd Font Mono 13, Catppuccin Mocha and Latte, 100 MB scrollback, bell and finish notifications, left Option as Alt, quick terminal, split keys. See [keybindings](keybindings.md). |
| `zsh/zshrc`                     | linked: `~/.zshrc`                          | Homebrew `PATH`, completions (including jj's dynamic ones), autosuggestions, fzf, starship, zoxide, `mise activate zsh`, the machine settings in `~/.config/dotfiles/config`, the four files below, syntax highlighting last. |
| `zsh/jj.zsh`                    | linked: `~/.config/zsh/jj.zsh`              | `jw`, `jwc`, `jws`, `jwl`, `jwrm`, `jpush`. See [shell commands](shell-commands.md).           |
| `zsh/sign.zsh`                  | linked: `~/.config/zsh/sign.zsh`            | `sign-as`.                                                                                     |
| `zsh/infra.zsh`                 | linked: `~/.config/zsh/infra.zsh`           | `infra`.                                                                                       |
| `zsh/navi.zsh`                  | linked: `~/.config/zsh/navi.zsh`            | The navi widget on `Ctrl-G`, `navi-trust`, `navi-untrust`, and the `chpwd` hook that sets `NAVI_PATH` for a trusted repo's `.navi/`. See [saved workflows](../guides/workflows.md). |
| `navi/` (`agents.cheat`, `jj.cheat`, `infra.cheat`, `k8s.cheat`, `dev.cheat`, `dotfiles.cheat`) | linked: `~/.local/share/navi/cheats/dotfiles` (the directory) | The saved workflows `Ctrl-G` offers.                                     |
| `zsh/zprofile.snippet`          | appended once to `~/.zprofile`              | Homebrew `PATH` and `mise activate zsh --shims` for login shells that are not interactive.     |
| `infra/compose.yaml`            | linked: `~/.config/devinfra/compose.yaml`   | Compose project `devinfra`: Redis 8, Apache Kafka 4.1.0 (KRaft, one node), kafka-ui, Jaeger. Loopback ports only. |
| `starship/starship.toml`        | linked: `~/.config/starship.toml`           | Catppuccin Mocha prompt. `custom.jj` shows change ID, bookmarks, conflict and empty markers and the description. `git_branch` shows only on an attached HEAD. |
| `jj/config.toml`                | linked: `~/.config/jj/config.toml`          | `ui.default-command`, `work()`, `closest_bookmark()`, `tug`, `stack`, `dft`, `dshow`, the `difft` tool. See [jj configuration](jj-config.md). |
| `jj/identity.example.toml`      | template for `~/.config/jj/conf.d/identity.toml` | Placeholder identity, with the `[signing]` and second-identity `[[--scope]]` blocks commented out. Copied only when `install.sh` has no terminal and no `DOTFILES_NAME`. |
| `mise/config.toml`              | linked: `~/.config/mise/config.toml`        | Global tools: `node` LTS, `pnpm` latest, `gopls`, `dlv`, `gotestsum`, `govulncheck` (all `latest`). |
| `claude/CLAUDE.md`              | linked: `~/.claude/CLAUDE.md`               | Rules for every Claude Code session: English only, jj instead of git writes, always `-m`, just and mise tasks, local infra only, authorship and signing. |
| `claude/statusline.sh`          | linked: `~/.claude/statusline.sh`           | Claude Code status line: `dir · [workspace] change bookmarks description · model`, or `git:<branch>` outside jj. |
| `claude/settings.fragment.json` | merged into `~/.claude/settings.json`       | Allow list of read-only jj commands, deny `jj *--tool*` and `jj *--config*`, `env.JJ_EDITOR = "false"`, `statusLine`. |

## Files install.sh writes outside the repo

None of these are in the repo. See [install.sh](install-sh.md#what-it-writes).

| File                                   | Holds                                                 |
| -------------------------------------- | ----------------------------------------------------- |
| `~/.config/jj/conf.d/identity.toml`    | Name, emails, signing keys. Mode 600.                 |
| `~/.config/dotfiles/config`            | Machine settings, rewritten on every run and sourced by `zshrc`: `DOTFILES_DIR` (where the repo is cloned) and, with a second identity, `DOTFILES_PERSONAL_DIR` (its folder, absolute). |
| `~/.config/git/allowed_signers`        | `<email> namespaces="git" <public key>` lines. Mode 600. |
| `~/.config/git/personal.gitconfig`     | Only with a second identity: its `user.email`, and its key and signer if given. |
| `~/.gitconfig`                         | Signing keys, `includeIf` for the second identity's folder if any, `alias.dft`, and `user.name` and `user.email` copied from jj. |
| `*.bak-<YYYYmmdd-HHMMSS>`              | Anything the script replaced.                         |

## Packages

| Repo file  | Used by        | Installs                                                                                     |
| ---------- | -------------- | -------------------------------------------------------------------------------------------- |
| `Brewfile` | `brew bundle`  | Casks: `ghostty`, `font-jetbrains-mono-nerd-font`, `claude-code@latest`, `redis-insight`. Formulae: `starship`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fzf`, `zoxide`, `navi`, `jq`, `ripgrep`, `git`, `jj`, `jjui`, `difftastic`, `gh`, `mise`, `just`, `redis`, `kcat`, `grpcurl`, `xh`, `hurl`, `d2`, `k9s`, `kubectx`, `stern`, `bats-core`, `shellcheck`, `gitleaks`, `lychee`, `actionlint`. |

## Repo tooling

These stay in the repo and are not installed.

| Repo file                  | What it is                                                                                     |
| -------------------------- | ---------------------------------------------------------------------------------------------- |
| `install.sh`               | The installer. See [install.sh](install-sh.md).                                               |
| `justfile`                 | Recipes: `install`, `lint`, `test`, `secrets`, `check` (lint, test and secrets), `drift`, `infra-up`, `infra-down`. |
| `scripts/check-commits.sh` | Checks that every non-merge commit subject in a git range (default `origin/main..HEAD`) follows Conventional Commits with the types in `CONTRIBUTING.md`. Run by `just commits`. |
| `scripts/check-secrets.sh` | Scans tracked and untracked, non-ignored files for email addresses outside example domains, absolute home paths, private key headers, full SSH public keys, 1Password references and entries from the local denylist. Exits 1 on any hit. |
| `.gitleaks.toml`           | gitleaks default rules plus `personal-email`, `home-path`, `ssh-public-key` and `onepassword-reference`. Ignores `.jj/`. |
| `tests/helpers.bash`       | Shared bats helpers: fake `HOME`, a copy of the repo to install into, throwaway jj repos.      |
| `tests/install.bats`       | `install.sh`: dry run, links, second run, backups, settings merge, identity from env and template, one identity only, the second identity's folder and email set together, a folder outside `$HOME`, `~/.config/dotfiles/config`, the template's placeholder folder, a private key file rejected, `allowed_signers` mode 600, a second key without a main key, the git identity read outside the personal folder, the template copy leaving signing off, a symlinked folder stored as its physical path, an empty name or email refused, links repointed after the repo moves. |
| `tests/jj.bats`            | `jw`, `jwrm`, `jpush` and `jj tug` in temporary jj repos.                                     |
| `tests/statusline.bats`    | `claude/statusline.sh` inside and outside jj, empty input, no op log writes.                  |
| `tests/sign.bats`          | `sign-as personal`, `sign-as work` and `sign-as status` in a temporary jj repo, and failures without `personal.gitconfig` or outside a repo. |
| `tests/commits.bats`       | `scripts/check-commits.sh`: conventional subjects pass, other subjects fail and are named, commits before the range and merge commits are skipped. |
| `tests/drift.bats`         | `just drift`: `linked`, `elsewhere` for a link into another clone or a dangling link, `same (copy)`, `DIFFERS` and `missing`, and nothing in `HOME` changes. |
| `tests/infra.bats`         | `infra/compose.yaml` is valid and every port binds to `127.0.0.1` or `[::1]`.                 |
| `tests/navi.bats`          | `navi/*.cheat` and `zsh/navi.zsh`: every entry renders, unique descriptions, no zsh functions or working-copy snapshots in pickers, the `[LOCAL ONLY]` and `[PERSONAL]` labels, column-1 insertion, and the `.navi/` trust rules, with and without `DOTFILES_PERSONAL_DIR`. |
| `.github/workflows/ci.yml` | CI. Job `check` on `macos-latest` runs `just check`, with the commit check limited to the pushed or pull request commits. Job `history-secrets` on `ubuntu-latest` runs gitleaks 8.30.1 over the full git history. |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | Bug report form.                                                                  |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | Feature request form.                                                        |

## Documentation

| Repo file              | What it is                                                         |
| ---------------------- | ------------------------------------------------------------------ |
| `README.md`            | Overview and quick start.                                          |
| `SETUP_PROMPT.md`      | A prompt to paste into Claude Code to install and verify the setup. |
| `docs/SUMMARY.md`      | Table of contents for the docs.                                    |
| `docs/introduction.md`, `docs/install.md`, `docs/getting-started.md`, `docs/troubleshooting.md` | First reading.          |
| `docs/guides/`         | Task guides: parallel agents, review and landing, identity, infra, project tools, saved workflows, Claude Code, updating. |
| `docs/reference/`      | This section.                                                      |
| `docs/explanation/`    | Why the setup is built this way.                                   |
| `CHANGELOG.md`         | Changes, Keep a Changelog format.                                  |
| `CONTRIBUTING.md`      | How to change the repo.                                            |
| `LICENSE`              | MIT.                                                               |
