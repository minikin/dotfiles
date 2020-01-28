[ -f /usr/local/etc/bash_completion ] && . /usr/local/etc/bash_completion

# local bin overrides
PATH=$PATH:bin:/Applications/Postgres.app/Contents/Versions/9.6/bin

source ~/.bashrc
[[ -f ~/.iterm2_shell_integration.bash ]] && source ~/.iterm2_shell_integration.bash

# Set Git language to English
alias git='LC_ALL=en_US git'

export PATH=$PATH:/Users/Sascha/flutter/bin
export PATH=$PATH:$HOME/.pub-cache/bin

if which swiftenv > /dev/null; then eval "$(swiftenv init -)"; fi

export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/usr/local/opt/node@8/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
