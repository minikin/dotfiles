#!/bin/bash
# where.sh [dir]: which repo and which jj workspace or git worktree <dir> (default $PWD) is in.
# Prints five lines: repo name, workspace name, workspace root, colour 1-6 (ANSI red..cyan), and
# jj or git. The main checkout has an empty workspace name and colour: it needs no marker.
# where.sh --colour <repo>/<workspace>...: only the colour of each label, one per line (jwst, jws).
# Exits 1 outside a repo. The status line, the notify and SessionStart hooks, the zsh title and
# tint, and through the zsh JW_WHERE variable the starship prompt all use it, so they always agree.
# jj runs with --ignore-working-copy: this must never snapshot.

colour_of() {
  local sum
  sum=$(printf '%s' "$1" | cksum)
  echo $(( ${sum%% *} % 6 + 1 ))
}

if [[ ${1:-} == --colour ]]; then
  shift
  for label; do colour_of "$label"; done
  exit 0
fi

cd "${1:-.}" 2>/dev/null || exit 1

jroot=$(jj --ignore-working-copy root 2>/dev/null) || jroot=''
groot=$(git rev-parse --show-toplevel 2>/dev/null) || groot=''

repo='' name='' root='' kind=''
# The deeper root wins: a git worktree inside a jj repo (Claude Code's .claude/worktrees/<name>)
# is that worktree, not the jj checkout around it.
if [[ -n $jroot && ( -z $groot || $groot == "$jroot" || $jroot == "$groot"/* ) ]]; then
  root=$jroot kind=jj
  if [[ -f $root/.jj/repo ]]; then   # a workspace: .jj/repo holds the main repo's .jj/repo, often relative
    main=$(<"$root/.jj/repo")
    main=$(cd "$root/.jj" 2>/dev/null && cd "${main%/.jj/repo}" 2>/dev/null && pwd -P) || main=$root
    repo=${main##*/}
    name=$(jj --ignore-working-copy workspace list -T 'name ++ "\t" ++ self.root() ++ "\n"' 2>/dev/null |
      awk -F '\t' -v root="$root" '$2 == root { print $1; exit }')
    [[ -n $name ]] || name=${root##*/}
  else
    repo=${root##*/}
  fi
elif [[ -n $groot ]]; then
  root=$groot kind=git
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null)
  if [[ -n $common && $common != "$gitdir" ]]; then   # a linked worktree
    main=${common%/.git}
    repo=${main##*/}
    repo=${repo%.git}
    name=${root##*/}
  else
    repo=${root##*/}
  fi
else
  exit 1
fi

colour=''
[[ -n $name ]] && colour=$(colour_of "$repo/$name")
printf '%s\n%s\n%s\n%s\n%s\n' "$repo" "$name" "$root" "$colour" "$kind"
