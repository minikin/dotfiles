#!/bin/bash
# Claude Code status line: dir · jj workspace + change (or git branch) · model · context % · cost
# Uses --ignore-working-copy so frequent refreshes never snapshot or touch the op log.
# One jq call, one value per line: @tsv would need IFS=tab, and bash collapses empty
# tab-separated fields, shifting every value after a missing one.
input=$(cat)
fields=$(jq -r '
  def oneline: tostring | gsub("[\n\r]"; " ");
  (.workspace.current_dir // .cwd // "" | oneline),
  (.model.display_name // "" | oneline),
  (.context_window as $w
    | if ($w.used_percentage | type) == "number" then $w.used_percentage
      elif ($w.total_input_tokens // 0) > 0 and ($w.context_window_size // 0) > 0
        then $w.total_input_tokens * 100 / $w.context_window_size
      else empty end
    | "\(floor)% ctx") // "",
  (.cost.total_cost_usd | if type == "number" then (. * 100 | round) else 0 end
    | if . > 0 then "$\(. / 100 | floor).\(. % 100 | tostring | if length < 2 then "0" + . else . end)"
      else "" end)
' <<<"$input" 2>/dev/null)
{ IFS= read -r dir; IFS= read -r model; IFS= read -r ctx; IFS= read -r cost; } <<<"$fields"
[[ -n $dir ]] && { cd "$dir" 2>/dev/null || true; }

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
[[ -n $ctx ]] && parts+=("$ctx")
[[ -n $cost ]] && parts+=("$cost")

out=""
for p in "${parts[@]}"; do out+="${out:+ · }$p"; done
printf '%s' "$out"
