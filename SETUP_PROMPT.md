# Setup prompt for Claude Code

Clone the repo to `~/repos/personal/dotfiles`, open `claude` inside it on the new machine, and paste everything below the line.

---

Set up my terminal and AI-agent development environment from this repo on this Mac. Read `README.md` first; it describes every file and where it goes.

Do this in order, and tell me before anything destructive:

1. **Preflight.** Check macOS, Apple Silicon (`uname -m`), and that Homebrew is installed (if not, show me the install command and stop). After installing Homebrew, `/opt/homebrew/bin` must be on PATH for `brew bundle` (`eval "$(/opt/homebrew/bin/brew shellenv)"`); the repo's zshrc adds it permanently. If Homebrew is not at `/opt/homebrew`, update `HOMEBREW_PREFIX` in `zsh/zshrc` and the path in `zsh/zprofile.snippet` first.
2. **Packages.** Run `brew bundle --file=Brewfile`. Report anything that failed.
3. **Identity.** If `~/.config/jj/conf.d/identity.toml` doesn't exist yet, ask me for:
   - full name and default (work) email,
   - default signing key: an SSH public key line (e.g. from the 1Password SSH agent) or a path to a `.pub` file; empty means no signing,
   - optionally a personal email (used for every repo under `~/repos/personal`) and a personal signing key (`.pub` path or key line).
   Never invent these values and never put them in files inside this repo.
4. **Preview.** Run `./install.sh --dry-run` and show me which existing files will be backed up and replaced. Wait for my OK.
5. **Install.** Run `./install.sh` with my answers as environment variables, since there is no terminal for its prompts: `DOTFILES_NAME=... DOTFILES_EMAIL=... DOTFILES_SIGNING_KEY=... DOTFILES_PERSONAL_EMAIL=... DOTFILES_PERSONAL_KEY=... ./install.sh`. It symlinks configs, backs up what it replaces (`*.bak-<timestamp>`), writes `~/.config/jj/conf.d/identity.toml` (local only), sets up git identity + SSH signing where git has none (personal identity via `includeIf` for `~/repos/personal`), merges `claude/settings.fragment.json` into `~/.claude/settings.json` (other keys kept; `env.JJ_EDITOR` and `statusLine` from the fragment win; permission lists unioned), and appends the mise line to `~/.zprofile`. Then confirm `jj config get user.email` and `git config --global user.email` match my answers.
6. **Verify.** Report each result:
   - `ghostty +validate-config` passes; font `JetBrainsMono Nerd Font Mono` shows in `ghostty +list-fonts`.
   - `zsh -i -c exit` has no errors and takes under ~150ms (`/usr/bin/time`).
   - In a new interactive shell, `jw jwc jws jwl jwrm jpush z zi` are defined.
   - `jj --version`, `mise --version`, `just --version`, `jjui --version`, `difft --version` work.
   - `echo '{"workspace":{"current_dir":"'$PWD'"},"model":{"display_name":"test"}}' | ~/.claude/statusline.sh` prints a status line.
7. **End-to-end test, ONLY in a temp directory** (`mktemp -d`; never in a real repo, and check that every `cd` succeeded): create a repo with `jj git init --colocate`, add a `.env` (gitignored) and a `mise.toml`, commit, then run `jw test-agent` and check that `.env` was copied, `mise install` ran, and `git status` works inside the workspace. Then `jwrm test-agent` and delete the temp dir.
8. **Manual steps for me**, listed at the end:
   - Add my signing public key(s) on GitHub as **Signing keys** (and the personal key as an Authentication key if I push personal repos with it).
   - Restart Ghostty and Claude Code.
   - Give Ghostty Accessibility permission for the global `` cmd+` `` quick terminal.
   - In each repo I want to use with agents: `jj git init --colocate`.

Rules: don't edit files outside this repo except through `install.sh`; don't push anything; if a step fails, stop and show me the exact error instead of working around it.
