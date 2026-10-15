# jj (Jujutsu) helpers for running parallel agents.
# Each agent gets its own jj workspace (also a real git worktree, so git-based
# tools keep working). Workspaces live next to the repo: <parent>/<repo>-ws/<name>

_jw_root() {
  local root
  root=$(jj workspace root --name default 2>/dev/null) || {
    if git rev-parse --git-dir >/dev/null 2>&1; then
      echo "git repo without jj — run: jj git init --colocate" >&2
    else
      echo "not in a jj repo" >&2
    fi
    return 1
  }
  echo $root
}

# jw <name> [rev] — create (or reuse) a workspace and cd into it.
# rev defaults to trunk() (e.g. origin/main), or @- if there's no remote trunk.
jw() {
  local name=${1//\//-} rev=${2:-} root dir
  [[ -z $name ]] && { echo "usage: jw <name> [rev]" >&2; return 1; }
  root=$(_jw_root) || return 1
  dir="${root:h}/${root:t}-ws/$name"

  if [[ -d $dir ]]; then
    echo "reusing $dir"
  else
    if [[ -z $rev ]]; then
      rev='trunk()'
      [[ -z $(jj -R $root --ignore-working-copy log -r 'trunk() & ~root()' --no-graph -T 'x' 2>/dev/null) ]] && rev='@-'
    fi
    mkdir -p "${dir:h}"
    # Workspace registered but its directory was deleted by hand: forget the stale entry
    if jj -R $root --ignore-working-copy workspace list -T 'name ++ "\n"' | grep -qx -- "$name"; then
      jj -R $root workspace forget "$name" || return 1
      git -C $root worktree prune   # drop git's entry for the missing directory
    fi
    jj -R $root workspace add --name "$name" -r "$rev" "$dir" || return 1
    [[ -z ${JW_NO_SETUP:-} ]] && _jw_setup "$root" "$dir"
  fi
  cd "$dir"
}

# Make a fresh workspace runnable: copy untracked local env files from the main
# checkout, then run the project's setup (just/mise task, else lockfile install).
# Skip with JW_NO_SETUP=1. Failures warn but never block.
_jw_setup() {
  local root=$1 dir=$2 f rel
  for f in $root/{.env*,mise.local.toml,.mise.local.toml}(N) \
           $root/*/{.env*,mise.local.toml}(N) $root/*/*/.env*(N); do
    [[ -f $f && $f != */node_modules/* ]] || continue
    rel=${f#$root/}
    [[ -e $dir/$rel ]] && continue            # tracked or already present
    mkdir -p "$dir/${rel:h}" && cp -n "$f" "$dir/$rel" && echo "copied $rel"
  done

  (
    cd "$dir" || exit
    _run() { echo "setup: $*"; "$@" || echo "⚠ setup step failed: $*" >&2; }
    if [[ -f justfile || -f Justfile ]] && just --summary 2>/dev/null | tr ' ' '\n' | grep -qx setup; then
      _run just setup; exit
    fi
    if [[ -f mise.toml || -f .mise.toml ]]; then
      mise tasks ls 2>/dev/null | grep -qE '^setup( |$)' && { _run mise run setup; exit; }
      _run mise install
    fi
    if   [[ -f pnpm-lock.yaml ]];           then _run pnpm install --frozen-lockfile
    elif [[ -f bun.lock || -f bun.lockb ]]; then _run bun install --frozen-lockfile
    elif [[ -f yarn.lock ]];                then _run yarn install --frozen-lockfile
    elif [[ -f package-lock.json ]];        then _run npm ci
    fi
    [[ -f uv.lock ]]      && _run uv sync
    [[ -f poetry.lock ]]  && _run poetry install
    [[ -f go.mod ]]       && _run go mod download
    [[ -f Gemfile.lock ]] && _run bundle install
    true
  )
}

# jwc <name> [rev] [claude args...] — create (or reuse) a workspace and start Claude Code in it.
# The second argument is a rev unless it starts with "-": jwc x --continue, jwc x @- --continue.
jwc() {
  local name=${1:-} rev
  (( $# )) && shift
  [[ -n ${1:-} && $1 != -* ]] && { rev=$1; shift; }
  jw "$name" ${rev:+"$rev"} && claude "$@"
}

# jwl — list workspaces
jwl() { jj workspace list; }

# jws — fuzzy-switch to a workspace
jws() {
  local dir
  dir=$(jj --ignore-working-copy workspace list -T 'name ++ "\t" ++ self.root() ++ "\n"' |
    fzf --prompt="workspace> " --with-nth=1 --delimiter='\t' --preview 'jj -R {2} --ignore-working-copy log -r "trunk()::@" --color always' |
    cut -f2)
  [[ -n $dir ]] && cd "$dir"
}

# jwst — one row per workspace: latest work, commits behind trunk, pushed, conflicts.
# Queries only the root with --ignore-working-copy: touching a workspace would snapshot it.
jwst() {
  local root w work change desc pushed conflicts behind width=9
  local -a names rows
  root=$(_jw_root) || return 1
  names=(${(f)"$(jj -R $root --ignore-working-copy workspace list -T 'name ++ "\n"')"})
  for w in $names; do (( ${#w} > width )) && width=${#w}; done
  for w in $names; do
    work=$(jj -R $root --ignore-working-copy log --no-graph -r "heads(::\"$w\"@ & mutable() & ~empty())" \
      -T 'change_id.short(8) ++ "\t" ++ coalesce(description.first_line(), "(no description)") ++ "\t" ++ if(remote_bookmarks.any(|b| b.name() == "'$w'" && b.remote() == "origin"), "yes", "no")' 2>/dev/null)
    if [[ -n $work ]]; then
      change=${work%%$'\t'*} desc=${${work#*$'\t'}%$'\t'*} pushed=${work##*$'\t'}
    else
      change=- desc='(no changes)' pushed=no
    fi
    conflicts=no
    [[ -n $(jj -R $root --ignore-working-copy log --no-graph -r "trunk()..\"$w\"@ & conflicts()" -T '"x"' 2>/dev/null) ]] && conflicts=yes
    behind=$(jj -R $root --ignore-working-copy log --no-graph -r "::trunk() & ~::\"$w\"@" -T '"x"' 2>/dev/null)
    rows+=("$(printf "%-${width}s  %-8s  %6s  %-6s  %-9s  %s" "$w" "$change" "${#behind}" "$pushed" "$conflicts" "$desc")")
  done
  printf "%-${width}s  %-8s  %6s  %-6s  %-9s  %s\n" WORKSPACE CHANGE BEHIND PUSHED CONFLICTS DESCRIPTION
  print -rl -- $rows
}

# jsync [name...] — rebase workspaces onto the latest trunk (fzf multi-pick if no args,
# default included). Per workspace: snapshot its unsaved edits, rebase, update it at once,
# so an agent never sees a stale working copy for longer than one rebase.
jsync() {
  local root w d out rc=0
  local -a names
  local -A dirs
  root=$(_jw_root) || return 1
  for w d in ${(@ps:\t:)${(f)"$(jj -R $root --ignore-working-copy workspace list -T 'name ++ "\t" ++ self.root() ++ "\n"')"}}; do
    dirs[$w]=$d
  done
  if (( $# )); then
    names=(${@//\//-})
  else
    names=(${(f)"$(print -rl -- ${(k)dirs} | fzf -m --prompt="sync> ")"})
  fi
  (( ${#names} )) || return 1
  if [[ -n $(jj -R $root --ignore-working-copy git remote list 2>/dev/null) ]]; then
    jj -R $root git fetch --quiet || echo "jsync: fetch failed, using the trunk already fetched" >&2
  fi
  for w in $names; do
    d=${dirs[$w]:-}
    if [[ -z $d || ! -d $d ]]; then
      echo "$w: no such workspace directory, run: jw $w" >&2; rc=1; continue
    fi
    if [[ -z $(jj -R $root --ignore-working-copy log --no-graph -r "::trunk() & ~::\"$w\"@" -T '"x"' 2>/dev/null) ]]; then
      if [[ -n $(jj -R $root --ignore-working-copy log --no-graph -r "trunk()..\"$w\"@ & conflicts()" -T '"x"' 2>/dev/null) ]]; then
        echo "$w: up to date, conflicts left for the agent"
      else
        echo "$w: up to date"
      fi
      continue
    fi
    # update-stale first: a workspace left stale by an earlier rebase cannot snapshot
    out=$(jj -R $d workspace update-stale 2>&1 && jj -R $d status 2>&1 >/dev/null \
      && jj -R $root rebase --quiet -b "\"$w\"@" -d 'trunk()' 2>&1 && jj -R $d workspace update-stale 2>&1) || {
      echo "$w: rebase failed" >&2; print -r -- "$out" >&2; rc=1; continue
    }
    if [[ -n $(jj -R $root --ignore-working-copy log --no-graph -r "trunk()..\"$w\"@ & conflicts()" -T '"x"' 2>/dev/null) ]]; then
      echo "$w: conflicts, left for the agent"
    else
      echo "$w: rebased onto trunk"
    fi
  done
  return $rc
}

# jwrm [name...] — remove workspaces (fzf multi-pick if no args).
# jj snapshots the working copy first, so the agent's changes stay in the repo.
# Only ignored files (node_modules, .env, build output) are lost.
jwrm() {
  local root names
  root=$(_jw_root) || return 1
  if (( $# )); then
    names=(${@//\//-})
  else
    names=(${(f)"$(jj -R $root --ignore-working-copy workspace list -T 'name ++ "\n"' | grep -vx default | fzf -m --prompt="remove> ")"})
  fi
  (( ${#names} )) || return 1
  # jj reports the physical path, $PWD may be logical (symlinks, /tmp -> /private/tmp)
  [[ ${PWD:A} != ${root:A} && ${PWD:A} == "${root:A:h}/${root:A:t}-ws/"* ]] && cd $root
  jj -R $root workspace remove $names
}

# jpush [bookmark] — push your latest work as a bookmark (default: workspace name).
# Creates the bookmark on first push, moves it forward on later pushes.
# jland [rev]: move the trunk bookmark (main) to rev, default work(), and push it. For repos
# without pull requests. jj refuses to move the bookmark backwards.
jland() {
  local rev=${1:-'work()'} trunk
  trunk=$(jj log --ignore-working-copy -r 'trunk()' --no-graph -T 'remote_bookmarks.map(|b| b.name()).join("\n")' 2>/dev/null | head -1)
  trunk=${trunk:-main}
  # Checked first: jj git push refuses it anyway, but only after the bookmark has moved.
  if [[ -z $(jj log -r "$rev" --no-graph -T 'description' 2>/dev/null) ]]; then
    echo "jland: $rev has no description, run: jj describe -r '$rev' -m \"...\"" >&2
    return 1
  fi
  jj bookmark set "$trunk" -r "$rev" && jj git push -b "$trunk"
}

jpush() {
  local name=${1:-} trunk
  [[ -z $name ]] && name=$(jj log -r @ --no-graph -T 'self.working_copies().map(|w| w.name()).join(",")')
  # Several workspaces on @ give "a,b": there is no single default name
  [[ -z $name || $name == default || ( -z ${1:-} && $name == *,* ) ]] && { echo "usage: jpush <bookmark>" >&2; return 1; }
  # Never push agent work onto trunk (e.g. a workspace named "main") or an immutable bookmark
  trunk=$(jj log -r 'trunk()' --no-graph -T 'remote_bookmarks.map(|b| b.name()).join("\n")' 2>/dev/null)
  if print -r -- "$trunk" | grep -qx -- "$name" ||
     [[ -n $(jj log -r "present(bookmarks(exact:\"$name\")) & immutable()" --no-graph -T 'x' 2>/dev/null) ]]; then
    echo "jpush: refusing to push to trunk/immutable bookmark '$name' — pass another name: jpush <bookmark>" >&2
    return 1
  fi
  if [[ -n $(jj bookmark list -T 'name ++ "\n"' "exact:$name" 2>/dev/null) ]]; then
    jj bookmark set "$name" -r 'work()' && jj git push -b "$name"
  else
    jj git push --named "$name=work()"
  fi
}
