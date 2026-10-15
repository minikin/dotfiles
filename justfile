set shell := ["bash", "-euo", "pipefail", "-c"]

# List the recipes
default:
    @just --list

# Run install.sh, e.g. `just install --dry-run`
install *args:
    ./install.sh {{args}}

# Shellcheck, bats asserts, zsh syntax, compose config (if docker is installed) and offline Markdown link check
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    echo "== shellcheck"
    shellcheck install.sh claude/*.sh scripts/*.sh
    echo "== bats asserts"
    # bash 3.2 (macOS /usr/bin/env bash) ignores a failing [[ ]] or ! that is not a test's last command.
    if grep -nE '^[[:space:]]+(\[\[ .*\]\]|! .*)$' tests/*.bats | grep -v '|| false$'; then
      echo "add '|| false' to the asserts above" >&2; exit 1
    fi
    echo "== zsh -n"
    for f in zsh/zshrc zsh/*.zsh; do zsh -n "$f"; done
    if command -v docker >/dev/null; then
      echo "== docker compose config"
      docker compose -f infra/compose.yaml config -q
    else
      echo "skip docker compose config: docker not installed"
    fi
    echo "== lychee"
    find . -name '*.md' -not -path './.git/*' -not -path './.jj/*' -print0 | xargs -0 lychee --offline --no-progress

# Run the bats tests
test:
    bats tests

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
      printf '%-12s %s%s\n' "$status" "${dest/#$HOME/~}" "$target"
    done

# Start the local Redis / Kafka / Jaeger stack and wait until healthy
infra-up:
    docker compose -f infra/compose.yaml up -d --wait

# Stop the local stack, keep its data
infra-down:
    docker compose -f infra/compose.yaml down
