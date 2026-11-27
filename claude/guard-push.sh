#!/bin/bash
# Claude Code PreToolUse hook (matcher Bash): agents in a jj workspace or git worktree must not push,
# except a T3 Code thread in a git worktree pushing one non-force explicit <src>:<dst> branch update
# to a non-default feature branch. Exit 2 blocks the tool call and Claude Code shows stderr to Claude.
# where.sh decides: a non-empty workspace name means a jj workspace or a git worktree, also
# Claude Code's own .claude/worktrees/<name>. The main checkout and non-repo dirs may push.
# The match is a plain regex on the command line. Global options between the words count
# (git -C dir push, jj -R . git push), `echo git push` is blocked too, and a push hidden in a
# script is not caught here: the pre-push hook jw installs catches git ones.

t3_safe_feature_push() {
  local cmd=$1 cwd=$2 i=1 pos=0 w remote refspec src dst def
  local no_follow_tags=0 mirror follow_tags
  local -a words

  case $cmd in
    *$'\r'*) return 1 ;;
  esac

  IFS=$' \t' read -ra words <<<"$cmd"
  (( ${#words[@]} >= 4 )) || return 1
  [[ ${words[0]} == git ]] || return 1

  if [[ ${words[$i]} == --no-pager ]]; then
    (( i++ ))
  fi
  (( i < ${#words[@]} )) && [[ ${words[$i]} == push ]] || return 1
  (( i++ ))

  while (( i < ${#words[@]} )); do
    w=${words[$i]}
    case $w in
      -u|--set-upstream|-q|--quiet|-v|--verbose|--porcelain|--atomic)
        ;;
      --no-follow-tags)
        no_follow_tags=1 ;;
      -*)
        return 1 ;;
      *)
        if (( pos == 0 )); then
          remote=$w
        elif (( pos == 1 )); then
          refspec=$w
        else
          return 1
        fi
        (( pos++ ))
        ;;
    esac
    (( i++ ))
  done

  (( pos == 2 )) || return 1
  [[ $remote =~ ^[A-Za-z0-9._-]+$ && $remote != -* ]] || return 1
  git -C "$cwd" remote get-url --push "$remote" >/dev/null 2>&1 || return 1

  # Require an explicit non-force <src>:<dst> refspec without shell expansion syntax.
  case $refspec in
    +*|:*|*:*:*) return 1 ;;
    *:*) ;;
    *) return 1 ;;
  esac

  src=${refspec%%:*}
  dst=${refspec#*:}
  [[ $src =~ ^(HEAD|[A-Za-z0-9._/-]+)$ ]] || return 1
  [[ $src != -* && $src != /* && $src != */ && $src != *..* && $src != *//* ]] || return 1
  case $src in
    refs/*|heads/*|tags/*|remotes/*|notes/*) return 1 ;;
  esac
  if [[ $src != HEAD ]]; then
    git -C "$cwd" show-ref --verify --quiet "refs/heads/$src" || return 1
  fi

  [[ $dst =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  [[ $dst != -* && $dst != /* && $dst != */ && $dst != *..* && $dst != *//* ]] || return 1
  case $dst in
    ""|HEAD|@|main|master|trunk|refs/*|heads/*|tags/*|remotes/*|notes/*) return 1 ;;
  esac
  git -C "$cwd" show-ref --verify --quiet "refs/tags/$dst" && return 1
  git -C "$cwd" show-ref --verify --quiet "refs/notes/$dst" && return 1

  def=$(git -C "$cwd" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)
  def=${def#"$remote/"}
  [[ -n $def && $dst != "$def" ]] || return 1

  mirror=$(git -C "$cwd" config --bool --get "remote.$remote.mirror" 2>/dev/null || true)
  [[ $mirror == true ]] && return 1

  if (( ! no_follow_tags )); then
    follow_tags=$(git -C "$cwd" config --bool --get push.followTags 2>/dev/null || true)
    [[ $follow_tags == true ]] && return 1
  fi

  return 0
}

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
input=$(cat 2>/dev/null)
fields=$(jq -r '(.cwd // "" | tostring | gsub("\n"; " ")), (.tool_input.command // "" | tostring | gsub("\n"; ";"))' \
  <<<"$input" 2>/dev/null) || exit 0
{ IFS= read -r cwd; IFS= read -r cmd; } <<<"$fields"

opts='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'   # -C dir, --no-pager
push_re="(^|[;&|[:space:]])(jj${opts}[[:space:]]+git|git)${opts}[[:space:]]+push([[:space:]]|\$)"
[[ $cmd =~ $push_re ]] || exit 0

[[ -n $cwd ]] && where=$("$here/where.sh" "$cwd" 2>/dev/null) || exit 0
{ IFS= read -r _; IFS= read -r name; IFS= read -r _; IFS= read -r _; IFS= read -r kind; } <<<"$where"
if [[ -n $name ]]; then
  if [[ -n ${T3CODE_THREAD_ID:-} && $kind == git ]]; then
    if t3_safe_feature_push "$cmd" "$cwd"; then
      exit 0
    fi
    echo "blocked: agents in jj workspaces and git worktrees do not push; the user pushes from the main checkout with jpush/jland" >&2
    echo "hint: in a T3 git worktree, only a single non-force explicit feature-branch push is allowed: git push <remote> <src>:<dst> (configured remote with refs/remotes/<remote>/HEAD set; no force, chaining, or redirects)" >&2
    exit 2
  fi
  echo "blocked: agents in jj workspaces and git worktrees do not push; the user pushes from the main checkout with jpush/jland" >&2
  exit 2
fi
exit 0
