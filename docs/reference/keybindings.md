# Keybindings

## Ghostty

Every `keybind` line in `ghostty/config`, plus the two settings that change
how keys behave.

| Key                 | Config line                                        | Action                                                              |
| ------------------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| `` Cmd+` ``         | `keybind = global:cmd+grave_accent=toggle_quick_terminal` | Show or hide the quick terminal, from any app.               |
| `Cmd+D`             | `keybind = cmd+d=new_split:right`                  | New split to the right.                                             |
| `Cmd+Shift+D`       | `keybind = cmd+shift+d=new_split:down`             | New split below.                                                    |
| `Cmd+Alt+H`         | `keybind = cmd+alt+h=goto_split:left`              | Focus the split to the left.                                        |
| `Cmd+Alt+J`         | `keybind = cmd+alt+j=goto_split:down`              | Focus the split below.                                              |
| `Cmd+Alt+K`         | `keybind = cmd+alt+k=goto_split:up`                | Focus the split above.                                              |
| `Cmd+Alt+L`         | `keybind = cmd+alt+l=goto_split:right`             | Focus the split to the right.                                       |
| `Cmd+Shift+Enter`   | `keybind = cmd+shift+enter=toggle_split_zoom`      | Zoom the focused split to the whole tab, or back.                   |
| `Cmd+Shift+E`       | `keybind = cmd+shift+e=equalize_splits`            | Give every split in the tab the same size.                          |
| `Cmd+Shift+S`       | `keybind = cmd+shift+s=write_screen_file:paste,plain` | Write the screen contents, without colour codes, to a temp file and paste its path at the prompt. |

| Setting                          | Value  | Effect                                                                 |
| -------------------------------- | ------ | ---------------------------------------------------------------------- |
| `macos-option-as-alt`            | `left` | Left Option sends Alt (Meta), right Option still types special characters. `Alt-C` and agent TUIs need it. |
| `quick-terminal-position`        | `top`  | The quick terminal drops down from the top of the screen.             |

`global:` bindings need Accessibility permission for Ghostty (System
Settings, Privacy and Security, Accessibility). `macos-option-as-alt` applies
to new windows only.

Ghostty's own defaults still apply to every key not listed here. The one the
docs use is `Cmd+Shift+,`, which reloads the config.

### Notifications

Not keys, but the reason a split gets your attention:

| Setting                             | Value                            |
| ----------------------------------- | -------------------------------- |
| `desktop-notifications`             | `true`                           |
| `bell-features`                     | `attention,title,border`         |
| `notify-on-command-finish`          | `unfocused`                      |
| `notify-on-command-finish-after`    | `30s`                            |
| `notify-on-command-finish-action`   | `notify,bell`                    |

A bell in any split bounces the dock icon, marks the tab title and flashes the
split border. It shows no system notification of its own, because Claude
Code's hooks send one named after the workspace (see
[Claude Code](../guides/claude-code.md#notifications)). A command that runs longer than
30 seconds in a split without focus sends a notification and rings the bell
when it ends.

## Shell

`zshrc` loads fzf's zsh integration with `source <(fzf --zsh)` and sets
`FZF_DEFAULT_OPTS="--height 40% --layout reverse --border"`.

| Key            | Action                                                                 |
| -------------- | ---------------------------------------------------------------------- |
| `Ctrl-R`       | Search shell history with fzf and put the pick on the command line.    |
| `Ctrl-T`       | Pick files or directories with fzf and insert their paths at the cursor. |
| `Alt-C`        | Pick a directory with fzf and `cd` into it. Needs left Option as Alt.  |
| `**<Tab>`      | fzf completion for the word before it: `vim **<Tab>` picks files, `cd **<Tab>` directories, `kill -9 **<Tab>` processes, `ssh **<Tab>` hosts. |
| `Ctrl-G`       | Open the navi palette of saved workflows, fill the arguments and insert the command at the prompt without running it. Loaded by `zsh/navi.zsh`. See [saved workflows](../guides/workflows.md). |

Ghostty has no binding for `Ctrl-G`'s palette: in a split where Claude Code
runs, keys go to Claude Code, not zsh.

`zsh-autosuggestions` shows a grey suggestion from history as you type. The
`→` key (or `End`) accepts it.

## Inside tools

| Tool    | Key  | Action                       |
| ------- | ---- | ---------------------------- |
| `jjui`  | `?`  | List every key.              |
| `k9s`   | `?`  | List every key.              |
| fzf     | `Tab` | Mark an entry in a multi-pick such as `jwrm`. |

See the [cheatsheet](cheatsheet.md) for the commands these keys sit next to.
