# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="/Users/Sascha/.oh-my-zsh"

# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
# ZSH_THEME="simple"

PROMPT='🚀: '

# Which plugins would you like to load?
plugins=(
  git
  bundler
  dotenv
  osx
  rake
  rbenv
  ruby
  pip
  python
)

source $ZSH/oh-my-zsh.sh
source ~/env.sh


# prompt_context() {
#   if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
#     prompt_segment black default "%(!.%{%F{yellow}%}.)$USER"
#   fi
# }

prompt_context() {
  # Custom (Random emoji)
  emojis=("⚡️" "🔥" "💀" "👑" "😎" "🐸" "🐵" "🦄" "🌈" "🍻" "🚀" "💡" "🎉" "🔑" "🇹🇭" "🚦" "🌙")
  RAND_EMOJI_N=$(( $RANDOM % ${#emojis[@]} + 1))
  prompt_segment black default "${emojis[$RAND_EMOJI_N]} "
}

# User configuration

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# local bin overrides
export PATH=/opt/homebrew/bin:$PATH
export PATH="$HOME/.cargo/bin:$PATH"
export PATH=$PATH:/Users/minikin/flutter/bi

PATH=$PATH:bin:/Applications/Postgres.app/Contents/Versions/9.6/bin
export PATH=$PATH:/Users/Sascha/flutter/bin
export PATH=$PATH:$HOME/.pub-cache/bin
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="/usr/local/opt/node@8/bin:$PATH"
export ANDROID_HOME=/Users/$USER/Library/Android/sdk
export PATH=${PATH}:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools

if which swiftenv > /dev/null; then eval "$(swiftenv init -)"; fi
