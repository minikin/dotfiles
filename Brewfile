# Terminal
cask "ghostty"
cask "font-jetbrains-mono-nerd-font"
brew "bash"
brew "tmux"
brew "zellij"
brew "nushell"
brew "btop"
brew "terminal-notifier"

# Screenshots (./install.sh --shottr frees ⇧⌘3/4/5 for it)
cask "shottr"
cask "cleanshot"

# Shell
brew "starship"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "fzf"
brew "zoxide"
brew "navi"               # Ctrl-G: saved workflows from navi/*.cheat
brew "jq"
brew "ripgrep"
brew "atuin"
brew "carapace"
brew "coreutils"
brew "fd"
brew "flock"
brew "gnuplot"
brew "hyperfine"
brew "librsvg"
brew "make"
brew "poppler"
brew "ast-grep"
brew "typos-cli"

# VCS + review
brew "git"                # 2.48+: jj workspaces are git worktrees with relative paths
brew "jj"
brew "jjui"
brew "difftastic"
brew "git-delta"
brew "gh"                 # GitHub CLI: gh pr create for pushed workspaces
tap "hewigovens/tap"
cask "hewigovens/tap/jayjay", trusted: true
cask "kaleidoscope"
cask "github"

# Tooling
brew "mise"
brew "just"
brew "uv"
brew "prek"
brew "sccache"
brew "pyenv"
brew "rbenv"
brew "ruff"
brew "watchman"
brew "cmake"
brew "cargo-nextest"
brew "cargo-binstall"
brew "poetry"
brew "ffmpeg"
brew "mas"                # CLI for Mac App Store installs listed in docs/reference/applications.md
cask "1password"
cask "1password-cli"
cask "orbstack"
cask "clop"
cask "tinycast"
tap "xykong/tap"
cask "xykong/tap/flux-markdown", trusted: true
cask "zed"
cask "proxyman"
cask "datagrip"
cask "spokenly"

# AI
tap "anomalyco/tap"
brew "anomalyco/tap/opencode", trusted: true
cask "claude-code@latest"
cask "codex"
brew "ollama"
cask "antigravity"
cask "claude"
cask "chatgpt"
cask "google-gemini"

# Phone access with Moshi (see docs/guides/phone-access.md). osewa comes from its install script.
tap "rjyo/moshi"
brew "rjyo/moshi/moshi-hook", trusted: true  # daemon behind the Moshi app: agent inbox, approvals, osewa setup
brew "mosh"               # Moshi's fallback transport
brew "herdr"

# Data / messaging (local services run in Docker: see infra/compose.yaml)
brew "libpq"              # Postgres client tools (keg-only: add $(brew --prefix libpq)/bin to PATH for psql)
brew "redis"              # redis-cli (server runs in Docker)
brew "kcat"               # Kafka produce/consume/metadata
cask "redis-insight"
brew "mkcert"
brew "pinentry-mac"

# APIs / distributed systems
brew "grpcurl"
brew "xh"                 # HTTP client
brew "hurl"               # HTTP tests as files
brew "d2"                 # diagrams as code
brew "cloudflared"

# Kubernetes
brew "k9s"
brew "kubectx"
brew "stern"
brew "kind"

# Repo development (just check: lint, tests, secret scan)
brew "bats-core"
brew "shellcheck"
brew "gitleaks"
brew "lychee"
brew "actionlint"
brew "act"
