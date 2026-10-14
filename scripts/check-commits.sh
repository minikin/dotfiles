#!/usr/bin/env bash
# Check that every non-merge commit subject in a git range follows Conventional Commits:
#   <type>(<scope>)!: <summary>   with scope and ! optional.
# Types and scopes are the ones CONTRIBUTING.md lists. Usage: scripts/check-commits.sh [range]
# The default range is origin/main..HEAD, so history from before the convention is never checked.
# Prints each bad subject and exits 1 if any was found.
set -euo pipefail

range=${1:-origin/main..HEAD}
types='feat|fix|docs|test|ci|refactor|chore|perf'
re="^($types)(\([a-z0-9-]+\))?!?: [^ ].*"

bad=0 n=0
while IFS= read -r line; do
  sha=${line%% *} subject=${line#* }
  n=$((n + 1))
  if [[ ! $subject =~ $re ]]; then
    echo "${sha:0:12}: $subject"
    bad=$((bad + 1))
  fi
done < <(git log --no-merges --format='%H %s' "$range")

if (( bad )); then
  echo "$bad of $n commits do not follow Conventional Commits (<type>(<scope>): <summary>, types: ${types//|/, })" >&2
  exit 1
fi
echo "check-commits: $n commits ok"
