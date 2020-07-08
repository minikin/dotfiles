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
