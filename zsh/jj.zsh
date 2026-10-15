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

# jwc <name> [rev] — create workspace and start Claude Code in it
jwc() { jw "$@" && claude; }

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
