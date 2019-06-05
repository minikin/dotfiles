# Sasha Prokhorenko's Dotfiles

In this repository you'll find Sasha Prokhorenko's dotfiles.

## Repository structure

- `master` branch contains files for `zsh`
- `bash` branch contains files for `bash`

## Prerequisites

- Some version of ruby
- `rake` and the `colored` gems installed locally

## Symlinking these files

Clone the directory somewhere.

Then we need to symlink these into your home directory. Run:

```zsh
rake symlink
```

This will symlink all of the dotfiles from the repo into your home folder.
It will prompt before overwriting files, so you can skip existing ones if you want.

I highly recommend you back up any existing dotfiles before trying this out. Use at your own risk.