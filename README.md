# Minikin's Dotfiles

In this repository you'll find Minikin's dotfiles.

## Prerequisites

- Some version of ruby
- `rake` and the `colored` gems installed locally

## Symlinking these files

Clone the directory somewhere (I chose `~/Dropbox/dotfiles` so it would be easily synced across my machines).
Make sure you grab the submodules too, as the vim plugins are added as submodules.

Then we need to symlink these into your home directory. Run:

```bash
rake symlink
```

This will symlink all of the dotfiles from the repo into your home folder.
It will prompt before overwriting files, so you can skip existing ones if you want.

I highly recommend you back up any existing dotfiles before trying this out. Use at your own risk.
