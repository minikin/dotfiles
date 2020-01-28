source ~/.bash/sensible.bash
source ~/.bash/aliases.bash
source ~/.bash/config.bash
source ~/.bash/env.bash

export PATH=/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin:"${PATH}"
export PATH="$HOME/.yarn/bin:$PATH"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
