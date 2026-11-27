set shell := ["bash", "-euo", "pipefail", "-c"]

# List the recipes
default:
    @just --list

# Run install.sh, e.g. `just install --dry-run`
install *args:
    ./install.sh {{args}}

# Shellcheck, bats asserts, zsh syntax (zsh/ and agy/), compose config (if docker is installed), offline Markdown links, the Brewfile inventory, prose rules and actionlint (if installed)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    echo "== shellcheck"
    shellcheck install.sh claude/*.sh scripts/*.sh codex/*.sh bin/*
    echo "== bats asserts"
    # bash 3.2 (macOS /usr/bin/env bash) ignores a failing [[ ]] or ! that is not a test's last command.
    if grep -nE '^[[:space:]]+(\[\[ .*\]\]|! .*)$' tests/*.bats | grep -v '|| false$'; then
      echo "add '|| false' to the asserts above" >&2; exit 1
    fi
    echo "== zsh -n"
    for f in zsh/zshrc zsh/*.zsh agy/*.zsh; do zsh -n "$f"; done
    if command -v docker >/dev/null; then
      echo "== docker compose config"
      docker compose -f infra/compose.yaml config -q
    else
      echo "skip docker compose config: docker not installed"
    fi
    echo "== lychee"
    find . -name '*.md' -not -path './.git/*' -not -path './.jj/*' -print0 | xargs -0 lychee --offline --no-progress
    echo "== brewfile"
    scripts/check-brewfile.sh
    echo "== prose"
    scripts/check-prose.sh
    if command -v actionlint >/dev/null; then
      echo "== actionlint"
      actionlint
    else
      echo "skip actionlint: not installed"
    fi

# Run the bats tests
test:
    bats tests

# Run the drift, statusline, install, hooks and t3-server-setup suites under macOS's /bin/bash 3.2 (bats itself starts with env bash)
test-bash32:
    #!/usr/bin/env bash
    set -euo pipefail
    shim=$(mktemp -d)
    trap 'rm -rf "$shim"' EXIT
    ln -s /bin/bash "$shim/bash"
    export PATH="$shim:$PATH"
    version=$(bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')
    [[ $version == 3.2 ]] || { echo "test-bash32: bash on PATH is $version, not 3.2" >&2; exit 1; }
    echo "== bats under bash $(bash -c 'echo "$BASH_VERSION"')"
    bats --print-output-on-failure tests/drift.bats tests/statusline.bats tests/install.bats tests/hooks.bats tests/t3-server-setup.bats

# Scan for secrets and personal data
secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/check-secrets.sh
    if command -v gitleaks >/dev/null; then
      gitleaks dir . --config .gitleaks.toml --no-banner
    else
      echo "skip gitleaks: not installed"
    fi

# Conventional Commits subjects in a git range (default: origin/main..HEAD)
commits range="origin/main..HEAD":
    scripts/check-commits.sh "{{range}}"

# Everything CI runs
check: lint test secrets commits

# Compare each live file install.sh links against the repo copy (read-only)
drift:
    #!/usr/bin/env bash
    set -euo pipefail
    tilde="~"   # a literal ~ in a replacement is tilde-expanded by bash 5.2+
    grep '^link ' install.sh | while read -r _ src dest _; do
      dest=${dest//\"/}
      dest=${dest/\$HOME/$HOME}
      target=""
      if [[ $dest -ef $src ]]; then status=linked
      # Checked before cmp: a link into another clone or jj workspace has the same content.
      elif [[ -L $dest ]]; then status=elsewhere; target=" -> $(readlink "$dest")"
      elif [[ -f $dest ]] && cmp -s "$dest" "$src"; then status="same (copy)"
      elif [[ -e $dest ]]; then status=DIFFERS
      else status=missing
      fi
      printf '%-12s %s%s\n' "$status" "${dest/#$HOME/$tilde}" "$target"
    done
    # install.sh links agy's rex-orchestrator skill to the source Claude's skill links to.
    skill=$HOME/.claude/skills/rex-orchestrator dest=$HOME/.gemini/config/skills/rex-orchestrator target=""
    if [[ -d $skill ]]; then
      src=$(cd "$skill" && pwd -P)
      if [[ -L $dest && $(readlink "$dest") == "$src" ]]; then status=linked
      elif [[ -L $dest ]]; then status=elsewhere; target=" -> $(readlink "$dest")"
      elif [[ -e $dest ]]; then status=DIFFERS
      else status=missing
      fi
      printf '%-12s %s%s\n' "$status" "${dest/#$HOME/$tilde}" "$target"
    fi

# Read-only health check of this machine: just drift, agent-preflight, brew bundle check, then a pointer to remote-check. Exits 1 if preflight or brew fails
doctor:
    #!/usr/bin/env bash
    set -uo pipefail
    rc=0
    echo "== drift"
    just drift || rc=1
    echo "== agent-preflight"
    ./bin/agent-preflight || rc=1
    echo "== brew bundle check"
    if command -v brew >/dev/null; then
      if [[ $OSTYPE == darwin* ]]; then brew bundle check --file Brewfile --no-upgrade || rc=1
      else scripts/linux-brewfile.sh | brew bundle check --file=- --no-upgrade || rc=1; fi
    else
      echo "skip brew bundle check: brew not installed"
    fi
    echo "== phone access"
    echo "run remote-check in zsh: it is a shell function, so a just recipe cannot call it"
    exit "$rc"

# Update Homebrew (Brewfile and the rest), agy, mise global tools, uv tools, rustup and mas, e.g. `just update --greedy`
update *args:
    ./bin/dotfiles-update {{args}}

# Start the local Redis / Kafka / Jaeger stack and wait until healthy
infra-up:
    docker compose -f infra/compose.yaml up -d --wait

# Stop the local stack, keep its data
infra-down:
    docker compose -f infra/compose.yaml down
