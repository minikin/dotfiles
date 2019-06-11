[ -f /usr/local/etc/bash_completion ] && . /usr/local/etc/bash_completion

# local bin overrides
PATH=$PATH:bin:/Applications/Postgres.app/Contents/Versions/9.6/bin

source ~/.bashrc
[[ -f ~/.iterm2_shell_integration.bash ]] && source ~/.iterm2_shell_integration.bash

# Set Git language to English
alias git='LC_ALL=en_US git'

export PATH=$PATH:/Developer/flutter/flutter/bin
export PATH=$PATH:$HOME/.pub-cache/bin

if which swiftenv > /dev/null; then eval "$(swiftenv init -)"; fi
export PATH="/usr/local/sbin:$PATH"

export PATH="$HOME/.cargo/bin:$PATH"
alias lg='lazygit'
