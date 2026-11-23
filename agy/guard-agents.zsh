#!/bin/zsh -f
# Antigravity (agy) PreToolUse hook: no claude or codex launch with an API key, and none without
# the env -u prefix that strips the keys. Linked to ~/.gemini/config/hooks/dotfiles-guard-agents.zsh
# and registered by agy/hooks.fragment.json, merged into ~/.gemini/config/hooks.json by install.sh.
#
# Output is empty (no opinion, agy's own permission flow decides) or one deny object. Never print
# "allow": agy would auto-approve the call and skip its permission prompts.
#
# Inspects run_command's CommandLine and manage_task send_input's Input (text typed into a running
# process), nothing else, so a toolSummary or a file body that mentions a launch is never blocked.
# The command is tokenised by zsh's own lexer (${(Z:C:)...}) and checked command by command,
# through env, op run, nohup, timeout and similar wrappers, bash/sh/zsh -c strings, $(...) and
# backticks, and the child after rex's `--`. A rex send message is data. Anything it cannot
# inspect is denied.
# Not caught: dynamic command words ($c, eval), aliases, scripts in files, encoded commands.

emulate -L zsh
setopt extended_glob

typeset -ga GUARDED=(ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CODEX_HOME)
typeset -ga CLAUDE_VARS=(ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN)
typeset -ga CODEX_VARS=(OPENAI_API_KEY CODEX_HOME)
typeset -gi MAX_DEPTH=8
typeset -g REASON='' HD_TEXT=''
typeset -ga HD_BODIES subs

deny() {
  local reason="agent guard: $1"
  if (( $+commands[jq] )); then
    jq -cn --arg r "$reason" '{decision: "deny", reason: $r}'
  else
    print -r -- '{"decision":"deny","reason":"agent guard: jq is missing, cannot inspect the command"}'
  fi
  exit 0
}

is_guarded() { (( ${GUARDED[(Ie)$1]} )) }

# A word that assigns a guarded variable: NAME=..., NAME+=..., NAME=(...).
assigns_guarded() {
  local w=$1 name
  [[ $w == (#b)([A-Za-z_][A-Za-z0-9_]#)(\+|)=* ]] || return 1
  name=$match[1]
  is_guarded $name && { REASON="sets $name"; return 0 }
  return 1
}

# Every $(...), <(...), >(...) and `...` body in a raw (still quoted) word, one per line in the
# array `subs`. Single-quoted text is skipped: the shell does not expand it. Double-quoted text
# is scanned.
extract_subs() {
  local w=$1 i=1 n=${#1} c depth start q=''
  subs=()
  while (( i <= n )); do
    c=$w[i]
    # Inside double quotes an apostrophe is literal, and $(...) and backticks still run.
    if [[ -z $q && $c == "'" ]]; then
      q="'"; (( i++ )); continue
    elif [[ $q == "'" ]]; then
      [[ $c == "'" ]] && q=''; (( i++ )); continue
    fi
    if [[ $c == '"' ]]; then
      if [[ $q == '"' ]]; then q=''; else q='"'; fi
      (( i++ )); continue
    fi
    if [[ $c == '\' ]]; then (( i += 2 )); continue; fi
    if [[ $c == [\$\<\>] && $w[i+1] == '(' ]]; then
      depth=1 start=$(( i + 2 )); (( i += 2 ))
      while (( i <= n && depth > 0 )); do
        [[ $w[i] == '(' ]] && (( depth++ ))
        [[ $w[i] == ')' ]] && (( depth-- ))
        (( i++ ))
      done
      subs+=("${w[start,i-2]}")
      continue
    fi
    if [[ $c == '`' ]]; then
      start=$(( i + 1 )); (( i++ ))
      while (( i <= n )) && [[ $w[i] != '`' ]]; do (( i++ )); done
      subs+=("${w[start,i-1]}")
      (( i++ )); continue
    fi
    (( i++ ))
  done
}

# strip_heredocs <text>: sets HD_TEXT to the text without heredoc bodies and HD_BODIES to the
# bodies of unquoted heredocs, whose $(...) still runs. Tokenising a body as commands would read
# an apostrophe in it as an open quote, or a word in it as a launch.
strip_heredocs() {
  local line tok d i
  local -a toks pending
  HD_TEXT='' HD_BODIES=()
  for line in "${(@f)1}"; do
    if (( $#pending )); then
      d=${pending[1]#[qu]}
      if [[ ${line##$'\t'#} == $d ]]; then
        pending=("${(@)pending[2,-1]}")
      elif [[ $pending[1] == u* ]]; then
        HD_BODIES+=("$line")
      fi
      continue
    fi
    HD_TEXT+="$line"$'\n'
    toks=("${(Z:C:)line}")
    for (( i = 1; i < $#toks; i++ )); do
      tok=$toks[i]
      [[ $tok == [0-9]#(\<\<|\<\<-) ]] || continue
      d=$toks[i+1]
      if [[ $d == *[\'\"\\]* ]]; then pending+=("q${(Q)d}"); else pending+=("u$d"); fi
    done
  done
}

# check_text <shell text> <depth> <typed> <unset names...>: 0 when fine, 1 with REASON set.
# typed=1 is text typed into another program (manage_task input, a Rex child string):
# a chat message like "Don't push." does not parse, so it is tokenised and checked anyway instead
# of denied. A shell runs the lines before a syntax error, which the tokens still show.
check_text() {
  local text=$1 depth=$2 typed=$3
  shift 3
  local -a inherited=("$@") words cmd subs
  local w sub skip_next=0 in_array=0

  (( depth > MAX_DEPTH )) && { REASON="nesting deeper than $MAX_DEPTH levels"; return 1 }
  [[ -z ${text//[[:space:]]/} ]] && return 0
  if (( ! typed )) && ! print -r -- "$text" | zsh -fn 2>/dev/null; then
    REASON="the command does not parse as shell"; return 1
  fi

  strip_heredocs "$text"
  for w in "${HD_BODIES[@]}"; do
    extract_subs "$w"
    for sub in "${subs[@]}"; do
      check_text "$sub" $(( depth + 1 )) $typed "${inherited[@]}" || return 1
    done
  done

  # (Z:C:) is the shell's own lexer with comments removed, newlines as ';'.
  words=("${(Z:C:)HD_TEXT}")
  for w in "${words[@]}" ';'; do
    # Every word's $(...) runs, whatever its role: argument, redirect target or array element.
    extract_subs "$w"
    for sub in "${subs[@]}"; do
      check_text "$sub" $(( depth + 1 )) $typed "${inherited[@]}" || return 1
    done
    if (( skip_next )); then skip_next=0; continue; fi
    if (( in_array )); then
      [[ $w == ')' ]] && in_array=0
      continue
    fi
    if [[ $w == [A-Za-z_][A-Za-z0-9_]#(\+|)=\( ]]; then
      assigns_guarded "${w%\(}" && return 1
      in_array=1; continue
    fi
    case $w in
      (';'|';;'|';&'|';|'|'&&'|'||'|'|'|'|&'|'&'|'&!'|'&|'|'('|')'|'{'|'}'|'()'|$'\n')
        if (( $#cmd )); then
          check_argv $depth "${(j: :)inherited}" "${cmd[@]}" || return 1
        fi
        cmd=(); continue ;;
      ([0-9]#(\>|\>\>|\<|\<\<|\<\<\<|\>\||\>\!|\>\&|\<\&|\&\>|\&\>\>|\<\>))
        skip_next=1; continue ;;
      ([0-9]#(\>|\>\>|\<|\>\||\>\!|\>\&|\<\&|\&\>|\&\>\>)?*)
        continue ;;
    esac
    cmd+=("${(Q)w}")
  done
  return 0
}

# check_argv <depth> <unset names joined by spaces> <argv...>
check_argv() {
  local depth=$1 unset_str=$2
  shift 2
  local -a argv=("$@") unset_names=(${=unset_str}) child
  local w exe sub v i

  # Reserved words in command position are not commands. `for x in ...` and `select` lists are
  # data, so the whole simple command is skipped after its reserved word.
  while (( $#argv )); do
    case $argv[1] in
      (if|then|else|elif|fi|do|done|while|until|esac|time|'!'|'{'|'}'|function|coproc|nocorrect|noglob|builtin|'-') argv=("${(@)argv[2,-1]}") ;;
      (for|select|case|'[['|'[') return 0 ;;
      (*) break ;;
    esac
  done

  while (( $#argv )) && [[ $argv[1] == [A-Za-z_][A-Za-z0-9_]#(\+|)=* ]]; do
    assigns_guarded $argv[1] && return 1
    argv=("${(@)argv[2,-1]}")
  done
  (( $#argv )) || return 0

  exe=${argv[1]:t}
  case $exe in
    (env)
      i=2
      while (( i <= $#argv )); do
        v=$argv[i]
        case $v in
          (-i|-|--ignore-environment) unset_names+=("${GUARDED[@]}") ;;
          (-u|--unset) (( i++ )); unset_names+=("$argv[i]") ;;
          (-u?*) unset_names+=("${v#-u}") ;;
          (--unset=*) unset_names+=("${v#--unset=}") ;;
          (-C|-P|-S|--chdir|--split-string) (( i++ )) ;;
          (--) (( i++ )); break ;;
          (-*) ;;
          ([A-Za-z_][A-Za-z0-9_]#=*) assigns_guarded $v && return 1 ;;
          (*) break ;;
        esac
        (( i++ ))
      done
      (( i <= $#argv )) || return 0
      check_argv $depth "${(j: :)unset_names}" "${(@)argv[i,-1]}"
      return ;;
    (exec|command|nohup|nice|sudo|caffeinate|timeout|xargs|stdbuf|arch)
      [[ $exe == command && $argv[2] == -[vV] ]] && return 0
      i=2
      while (( i <= $#argv )) && [[ $argv[i] == -* ]]; do
        case $exe:$argv[i] in
          (exec:-a|nice:-n|sudo:-[ugCDhpRrTU]|caffeinate:-[tw]|timeout:-[sk]|xargs:-[nILPsEd]|stdbuf:-[ioe]) (( i++ )) ;;
        esac
        (( i++ ))
      done
      [[ $exe == timeout ]] && (( i++ ))
      (( i <= $#argv )) || return 0
      check_argv $depth "$unset_str" "${(@)argv[i,-1]}"
      return ;;
    (export|declare|typeset|local|readonly|integer|float)
      for v in "${(@)argv[2,-1]}"; do
        assigns_guarded $v && return 1
        is_guarded $v && { REASON="exports $v"; return 1 }
      done
      return 0 ;;
    (launchctl)
      if [[ $argv[2] == setenv ]] && is_guarded "$argv[3]"; then
        REASON="sets $argv[3] in launchd"; return 1
      fi
      return 0 ;;
    (op)
      [[ $argv[2] == run ]] || return 0
      i=3
      while (( i <= $#argv )); do
        case $argv[i] in
          (--) (( i++ )); break ;;
          (--env-file|--account|--cache|--config|--session|--environment) (( i++ )) ;;
          (-*) ;;
          (*) break ;;
        esac
        (( i++ ))
      done
      (( i <= $#argv )) || return 0
      child=("${(@)argv[i,-1]}")
      exe=$(real_exe "${child[@]}")
      if [[ $exe == (claude|codex) ]]; then
        REASON="op run wraps $exe, which bills an API key"; return 1
      fi
      check_argv $depth "$unset_str" "${child[@]}"
      return ;;
    (rex)
      # Find the subcommand past rex's global options.
      i=2
      while (( i <= $#argv )) && [[ $argv[i] == -* ]]; do
        [[ $argv[i] == (-S|--server|-C|--client|--timeout|--color) ]] && (( i++ ))
        (( i++ ))
      done
      # A rex send message is text for an agent, not a command line: data. Its outer $(...) was
      # already checked as a word of this command.
      [[ $argv[i] == (send|send-key) ]] && return 0
      i=${argv[(i)--]}
      (( i <= $#argv )) || return 0
      child=("${(@)argv[i+1,-1]}")
      (( $#child )) || return 0
      # The child gets the environment of the Rex server's login shell, not this one.
      check_argv $depth "" "${child[@]}" || return 1
      if (( $#child == 1 )) && [[ $child[1] == *[[:space:]]* ]]; then
        check_text "$child[1]" $(( depth + 1 )) 1 || return 1
      fi
      return 0 ;;
    (bash|sh|zsh|dash|ksh)
      i=2
      while (( i <= $#argv )) && [[ $argv[i] == -* ]]; do
        if [[ $argv[i] == -[A-Za-z]#c[A-Za-z]# ]]; then
          (( i++ ))
          (( i <= $#argv )) || return 0
          check_text "$argv[i]" $(( depth + 1 )) 0 "${unset_names[@]}"
          return
        fi
        (( i++ ))
      done
      return 0 ;;
    (claude|codex)
      check_agent $exe "$unset_str" "${(@)argv[2,-1]}"
      return ;;
  esac
  return 0
}

# real_exe <argv...>: the basename of the program argv finally runs, through env and wrappers.
real_exe() {
  local -a argv=("$@")
  local i
  while (( $#argv )); do
    while (( $#argv )) && [[ $argv[1] == [A-Za-z_][A-Za-z0-9_]#=* ]]; do argv=("${(@)argv[2,-1]}"); done
    (( $#argv )) || return 0
    case ${argv[1]:t} in
      (env|exec|command|nohup|nice|sudo|caffeinate|timeout|xargs|stdbuf)
        i=2
        while (( i <= $#argv )) && [[ $argv[i] == -* || $argv[i] == [A-Za-z_][A-Za-z0-9_]#=* ]]; do
          [[ $argv[i] == (-u|--unset|-a|-n|-s|-k|-t|-w|-C|-P|-S) ]] && (( i++ ))
          (( i++ ))
        done
        [[ ${argv[1]:t} == timeout ]] && (( i++ ))
        argv=("${(@)argv[i,-1]}") ;;
      (*) print -r -- ${argv[1]:t}; return 0 ;;
    esac
  done
}

# check_agent <claude|codex> <unset names> <args...>
check_agent() {
  local exe=$1 unset_str=$2
  shift 2
  local -a args=("$@") unset_names=(${=unset_str}) need
  local v i=1

  if [[ $exe == codex ]]; then
    # Skip codex's global options to find the subcommand: `codex -c k=v login ...` is a login.
    while (( i <= $#args )) && [[ $args[i] == -* ]]; do
      [[ $args[i] == (-c|--config|-p|--profile|-m|--model|-s|--sandbox|-a|--ask-for-approval|-C|--cd|-i|--image|--enable|--disable|--add-dir|--local-provider) ]] && (( i++ ))
      (( i++ ))
    done
    if [[ $args[i] == login ]] && (( ${args[(Ie)--with-api-key]} )); then
      REASON="codex login --with-api-key replaces the ChatGPT login with an API key"; return 1
    fi
  fi
  # Exceptions compare whole arguments, so a prompt such as "auth status, then ..." is a launch.
  if [[ $exe == claude ]]; then
    (( $#args == 1 )) && [[ $args[1] == (--version|-v|--help|-h) ]] && return 0
    if [[ $args[1] == auth && $args[2] == status ]]; then
      for v in "${(@)args[3,-1]}"; do [[ $v == (--json|--text) ]] || break; done
      [[ $v == (--json|--text) || $#args -eq 2 ]] && return 0
    fi
  else
    (( $#args == 1 )) && [[ $args[1] == (--version|-V|--help|-h) ]] && return 0
    (( $#args == 2 )) && [[ $args[1] == login && $args[2] == status ]] && return 0
  fi
  if [[ $exe == claude ]]; then need=("${CLAUDE_VARS[@]}"); else need=("${CODEX_VARS[@]}"); fi
  for v in "${need[@]}"; do
    if ! (( ${unset_names[(Ie)$v]} )); then
      REASON="$exe starts without unsetting $v. Launch it as: env -u ${(j: -u :)need} $exe ..."
      return 1
    fi
  done
  return 0
}

(( $+commands[jq] )) || deny "jq is missing, cannot inspect the command"
input=$(cat)
[[ -n ${input//[[:space:]]/} ]] || deny "empty hook input"
# Exactly one event object: jq reads a stream of values, and a second object must not slip past.
jq -e -s 'length == 1 and (.[0] | type) == "object"' >/dev/null 2>&1 <<<"$input" ||
  deny "hook input is not exactly one JSON object"
input=$(jq -c '.' <<<"$input")
tool=$(jq -r '.toolCall.name // empty | strings' <<<"$input")
[[ -n $tool ]] || deny "hook input has no tool name"
[[ $tool == [A-Za-z0-9_.:-]## ]] || deny "hook input has a malformed tool name"

case $tool in
  (run_command) field=CommandLine typed=0 ;;
  (manage_task)
    [[ $(jq -r '.toolCall.args.Action // empty | strings' <<<"$input") == send_input ]] || exit 0
    field=Input typed=1 ;;
  (shell_exec|send_command_input) deny "$tool has no known command field yet" ;;
  (*) exit 0 ;;
esac

jq -e --arg f $field '.toolCall.args[$f] | type == "string"' >/dev/null 2>&1 <<<"$input" ||
  deny "$tool has no string $field"
cmd=$(jq -r --arg f $field '.toolCall.args[$f]' <<<"$input")
check_text "$cmd" 0 $typed || deny "$REASON"
exit 0
