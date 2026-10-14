#!/bin/bash
# Claude Code status line: dir · jj workspace + change (or git branch) · model
# Uses --ignore-working-copy so frequent refreshes never snapshot or touch the op log.
input=$(cat)
dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
model=$(jq -r '.model.display_name // empty' <<<"$input")
[[ -n $dir ]] && cd "$dir" 2>/dev/null

parts=("${PWD/#$HOME/~}")
if jj --ignore-working-copy root >/dev/null 2>&1; then
  parts+=("$(jj log --ignore-working-copy --no-graph --color never -r @ -T '
    separate(" ",
      if(self.working_copies(), "[" ++ self.working_copies().map(|w| w.name()).join(",") ++ "]"),
      change_id.shortest(4),
      bookmarks,
      if(conflict, "CONFLICT"),
      if(empty, "(empty)", truncate_end(30, coalesce(description.first_line(), "(no desc)"), "…"))
    )' 2>/dev/null)")
elif branch=$(git branch --show-current 2>/dev/null) && [[ -n $branch ]]; then
  parts+=("git:$branch")
fi
[[ -n $model ]] && parts+=("$model")

out=""
for p in "${parts[@]}"; do out+="${out:+ · }$p"; done
printf '%s' "$out"
