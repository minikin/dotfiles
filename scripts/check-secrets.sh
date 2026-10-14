#!/usr/bin/env bash
# Scan the repo's files for personal data and secrets before they go public.
#
# Checks every tracked (and untracked, non-ignored) file for:
#   - email addresses (reserved example domains and GitHub noreply are allowed)
#   - absolute home paths (/Users/<name>/, /home/<name>/); use ~/ or $HOME instead
#   - private key headers
#   - full SSH public key bodies (placeholders such as "AAAA..." are fine)
#   - 1Password references (secret reference URIs, vault names passed to the vault flag, item IDs)
#   - fixed strings from an optional local denylist, one per line:
#       ${DOTFILES_DENYLIST:-~/.config/dotfiles/denylist.txt}
#     Put your own name, employer and personal email there. It is never committed.
#
# Only file contents are scanned, so the result is deterministic.
# Prints file:line: reason for every hit and exits 1 if anything was found.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

denylist=${DOTFILES_DENYLIST:-$HOME/.config/dotfiles/denylist.txt}

# Patterns are assembled from pieces so this script does not match itself.
dashes='-----'
re_email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
# RFC 2606 example domains and the reserved .example TLD, GitHub noreply, and git@ host remotes.
re_email_ok='@(example\.(com|org|net)|[A-Za-z0-9.-]+\.example|users\.noreply\.github\.com)$|^git@(github|gitlab)\.com$'
re_home='/(Users|home)/[A-Za-z0-9._-]+/'
re_privkey="${dashes}BEGIN ([A-Z0-9]+ )*PRIVATE KEY${dashes}"
re_sshkey='(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh\.com) AAAA[A-Za-z0-9+/]{40,}'
re_op="(o""p://|--vault[= ]+[\"']?[A-Za-z0-9]|\\bop (item|document) get [a-z0-9]{26}\\b)"

files=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    [[ -f $f ]] && files+=("$f")
  done < <(git ls-files -z --cached --others --exclude-standard)
fi
if [[ ${#files[@]} -eq 0 ]]; then
  # jj workspace without a git index: walk the tree instead.
  while IFS= read -r -d '' f; do
    files+=("${f#./}")
  done < <(find . \( -name .git -o -name .jj \) -prune -o -type f -print0)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "check-secrets: no files to scan" >&2
  exit 1
fi

found=0
report() { # file:line:content reason
  local file=${1%%:*} rest=${1#*:}
  printf '%s:%s: %s\n' "$file" "${rest%%:*}" "$2"
  found=1
}

# scan REGEX REASON: grep -E over all files, binary files skipped.
scan() {
  local hit
  while IFS= read -r hit; do
    report "$hit" "$2"
  done < <(grep -nHIE -- "$1" "${files[@]}" || true)
}

# Emails need a second pass so allowed addresses on the same line don't hide real ones.
while IFS= read -r hit; do
  file=${hit%%:*}
  rest=${hit#*:}
  line=${rest%%:*}
  text=${rest#*:}
  while IFS= read -r addr; do
    if ! grep -qE -- "$re_email_ok" <<<"$addr"; then
      printf '%s:%s: email address %s\n' "$file" "$line" "$addr"
      found=1
    fi
  done < <(grep -oE -- "$re_email" <<<"$text")
done < <(grep -nHIE -- "$re_email" "${files[@]}" || true)

scan "$re_home" "absolute home path (use ~/ or \$HOME)"
scan "$re_privkey" "private key header"
scan "$re_sshkey" "full SSH public key"
scan "$re_op" "1Password reference"

if [[ -r $denylist ]]; then
  patterns=$(grep -vE '^[[:space:]]*(#|$)' "$denylist" || true)
  if [[ -n $patterns ]]; then
    while IFS= read -r hit; do
      report "$hit" "matches an entry in $denylist"
    done < <(grep -nHIiF -- "$patterns" "${files[@]}" || true)
  fi
fi

if [[ $found -ne 0 ]]; then
  echo "check-secrets: found possible secrets or personal data (see above)" >&2
  exit 1
fi
echo "check-secrets: ${#files[@]} files clean"
