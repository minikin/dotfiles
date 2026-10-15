# Setup prompt for Claude Code

Clone the repo anywhere you like (for example `~/src/dotfiles`, `install.sh` records the location as `DOTFILES_DIR`), open `claude` inside it on the new machine, and paste everything below the line.

---

Set up my terminal and AI-agent development environment from this repo on this Mac. Read `README.md` first for the overview, then `docs/reference/files.md`, which lists every file and where it goes.

Do this in order, and tell me before anything destructive:

1. **Preflight.** Check macOS, Apple Silicon (`uname -m`), and that Homebrew is installed (if not, show me the install command and stop). After installing Homebrew, put `/opt/homebrew/bin` on PATH for `brew bundle` with `eval "$(/opt/homebrew/bin/brew shellenv)"`. The repo's zshrc adds it permanently. If Homebrew is not at `/opt/homebrew`, update `HOMEBREW_PREFIX` in `zsh/zshrc` and the path in `zsh/zprofile.snippet` first.
2. **Packages.** Run `brew bundle --file=Brewfile`. Report anything that failed.
3. **Identity.** If `~/.config/jj/conf.d/identity.toml` doesn't exist yet, ask me for:
   - full name and the main email, used in every repo,
   - the main signing key: an SSH public key line (e.g. from the 1Password SSH agent) or a path to a `.pub` file, or empty for no signing,
   - whether I want one identity for every repo (for example only personal, or only work) or two: the main one everywhere plus a second one for the repos inside one folder,
   - only for two: which folder holds the second identity's repos (any path, created if missing, for example `~/src/personal`, but ask, don't assume), the email for that folder, and its signing key (`.pub` path or key line, empty = same as the main key).
   Never invent these values and never put them in files inside this repo.
4. **Preview.** Run `./install.sh --dry-run` and show me which existing files will be backed up and replaced. Wait for my OK.
5. **Install.** Run `./install.sh` with my answers as environment variables, since there is no terminal for its prompts: `DOTFILES_NAME=... DOTFILES_EMAIL=... DOTFILES_SIGNING_KEY=... ./install.sh` for one identity, or `DOTFILES_NAME=... DOTFILES_EMAIL=... DOTFILES_SIGNING_KEY=... DOTFILES_PERSONAL_DIR=... DOTFILES_PERSONAL_EMAIL=... DOTFILES_PERSONAL_KEY=... ./install.sh` for two (`DOTFILES_PERSONAL_DIR` and `DOTFILES_PERSONAL_EMAIL` must be set together, otherwise it exits 2). It symlinks configs, backs up what it replaces (`*.bak-<timestamp>`), writes `~/.config/jj/conf.d/identity.toml` (local only) and `~/.config/dotfiles/config` (`DOTFILES_DIR`, plus `DOTFILES_PERSONAL_DIR` for two identities), sets up git identity and SSH signing where git has none (the second identity via `includeIf` for its folder), and appends the mise line to `~/.zprofile`. It also merges `claude/settings.fragment.json` into `~/.claude/settings.json`: `env.JJ_EDITOR` and `statusLine` from the fragment win, permission lists are unioned, and other keys are kept. Then confirm `(cd ~ && jj config get user.email)` and `git config --global user.email` match my main email. Run jj from `~`, because inside the second identity's folder it shows that identity.
6. **Verify.** Report each result:
   - `ghostty +validate-config` passes, and font `JetBrainsMono Nerd Font Mono` shows in `ghostty +list-fonts`.
   - `zsh -i -c exit` has no errors and takes under ~150ms (`/usr/bin/time`).
   - In a new interactive shell, `jw jwc jws jwst jwl jwrm jsync jpush jland jnext sign-as infra reload navi-trust navi-untrust z zi` are defined.
   - `jj --version`, `mise --version`, `just --version`, `jjui --version`, `difft --version` work.
   - `echo '{"workspace":{"current_dir":"'$PWD'"},"model":{"display_name":"test"}}' | ~/.claude/statusline.sh` prints a status line.
7. **End-to-end test, ONLY in a temp directory.** Make it with `mktemp -d`, never use a real repo, and check that every `cd` succeeded. Create a repo with `jj git init --colocate`, add a `.env` (gitignored) and a `mise.toml`, commit, then run `jw test-agent` and check that `.env` was copied, `mise install` ran, and `git status` works inside the workspace. Then `jwrm test-agent` and delete the temp dir.
8. **Manual steps for me**, listed at the end:
   - Add my signing public key(s) on GitHub as **Signing keys** (and the second key as an Authentication key if I push that folder's repos with it).
   - Restart Ghostty and Claude Code.
   - Give Ghostty Accessibility permission for the global `` cmd+` `` quick terminal.
   - In each repo I want to use with agents: `jj git init --colocate`.

Rules:

- Don't edit files outside this repo except through `install.sh`.
- Don't push anything.
- If a step fails, stop and show me the exact error instead of working around it.
