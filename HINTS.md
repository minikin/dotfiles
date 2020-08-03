# Hints

## Zsh

open zsh profile

```sh
code ~/.zshrc
```

```sh
echo "al

```sh
echo "alias astudio="open -a /Applications/Android\ Studio.app" >>  ~/.zshrc
```

edit env.sh

```zsh
code ~/env.sh
```

reload zsh

```zsh
source ~/.zshrc
```

Launching from the command line
https://code.visualstudio.com/docs/setup/mac#_launching-from-the-command-line

```sh
cat << EOF >> ~/.bash_profile
# Add Visual Studio Code (code)
export PATH="\$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
EOF
```

## Bash

open bash profile

```sh
code ~/.bash_profile
```

add new alias

```sh
echo "alias lg='lazygit'" >> ~/.bash_profile
```

navigate to bash folder

```sh
cd  ~/.bash
```

reload bash

```sh
. ~/.bash_profile
```

## Create System Links

```sh
ln -s /Users/developer/Documents/Developer/Utils/dotfiles/.gitconfig .gitconfig

ln -s /Users/developer/Documents/Developer/Utils/dotfiles/.gitignore_global .gitignore_global
```

```sh
.gitconfig -> /Developer/Utils/dotfiles/.gitconfig
.gitignore_global -> /Developer/Utils/dotfiles/.gitignore_global
```
