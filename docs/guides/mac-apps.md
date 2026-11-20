# Installing macOS apps

How to install the macOS applications listed in [Applications](../reference/applications.md) on a new Mac, adopt pre-existing apps on an already-configured Mac, and finish post-install permissions.

## Homebrew casks and adopting existing apps

On a fresh Mac, `./install.sh --brew` (or `./install.sh --all`) runs `brew bundle` and installs all casks declared in `Brewfile`.

On a Mac that already has non-Homebrew copies of those apps in `/Applications`, `brew bundle` stops with an error instead of overwriting an existing `.app` bundle. Adopt existing apps into Homebrew first, then re-run `brew bundle` or `./install.sh --brew`:

```sh
brew install --cask --adopt <cask-token>
```

Casks that use `.pkg` installers and prompt for `sudo` (such as `tailscale-app` and `zoom`) are intentionally kept out of `Brewfile` so `./install.sh --brew` stays non-interactive. Install them on demand with `brew install --cask <token>`.

## Optional desktop Homebrew casks

These apps are listed as `Brew cask` in [Applications](../reference/applications.md) rather than `Brewfile`. Install whichever ones you want on the new Mac:

```sh
# Daily desktop and productivity
brew install --cask \
  antinote \
  appcleaner \
  google-chrome \
  grammarly-desktop \
  imageoptim \
  mole-app \
  slack \
  spotify \
  typora

# Situational
brew install --cask android-studio deskpad hyperkey xscope

# PKG installers (prompt for sudo)
brew install --cask tailscale-app zoom
```

## Third-party Homebrew tap trust

Homebrew 7 refuses to load formulae or casks from untrusted third-party taps. In `Brewfile`, `, trusted: true` marks each individual formula or cask entry as trusted (`rjyo/moshi/moshi-hook`, `anomalyco/tap/opencode`, `hewigovens/tap/jayjay`, `xykong/tap/flux-markdown`).

When installing **Agent Caffeine** outside `Brewfile`, trust its tap first:

```sh
brew trust vinenastudio/tap
brew install --cask vinenastudio/tap/agent-caffeine
```

## Mac App Store (`mas`) applications

`Brewfile` installs the `mas` CLI formula without `mas "..."` entries so `./install.sh --brew` never blocks on GUI App Store authentication. On a new Mac, open **App Store.app**, sign into your Apple Account, and install each needed app individually (running one command per app prevents a single lookup or purchase error from stopping the rest):

```sh
mas install 497799835   # Xcode
mas install 1444383602  # Goodnotes
mas install 361309726   # Pages Creator Studio
mas install 1289583905  # Pixelmator Pro (legacy paid purchase)
mas install 1006087419  # SnippetsLab
```

After installing **Xcode**, accept its license and run first-launch setup:

```sh
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

## Manual-only applications

This application has no Homebrew Cask or Mac App Store package and must be downloaded directly from the vendor:

1. **Rex Beta** (`com.superlogical.rex`)
   - **Source**: Sign into or request invite/beta access at `https://www.superlogical.com`.
   - **Install**: Open the downloaded archive and drag `Rex Beta.app` into `/Applications`.
   - **Post-install**: Launch once so the bundled server (`Contents/Helpers/Rex Server.rex/Contents/MacOS/rex`) initializes, then verify `rex` works in a terminal.

## Post-install macOS setup checklist

1. **1Password**: Sign in and enable Settings, Developer, **Use the SSH Agent** so `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` works for signed commits.
2. **Shottr**: Run `./install.sh --shottr` to free system screenshot shortcuts, then assign `⇧⌘3`/`4`/`5` in Shottr Preferences, Hotkeys and grant Screen Recording permission.
3. **Kaleidoscope**: Activate license and install `ksdiff` CLI integration to `/usr/local/bin/ksdiff`.
4. **Ghostty**: Grant Accessibility permission under System Settings, Privacy and Security so the global `` Cmd+` `` quick terminal works.
5. **Tailscale**: Install with `brew install --cask tailscale-app`, sign into your tailnet, approve the System/Network Extension prompt, and enable `/usr/local/bin/tailscale` CLI integration in Tailscale settings.
6. **OrbStack**: Launch once to start the VM daemon and link `/usr/local/bin/{docker,orb,orbctl,kubectl}` for `infra up`.
