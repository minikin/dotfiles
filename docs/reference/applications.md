# Applications

Reference inventory of actively used and occasional macOS applications across `/Applications` and `~/Applications`, with bundle IDs, install methods and CLI commands. For step-by-step setup on a new Mac, see [Installing macOS apps](../guides/mac-apps.md).

Install status tags:

- `Brewfile`: declared in `Brewfile` and installed by `./install.sh --brew` or `brew bundle`.
- `Brew cask`: core Homebrew cask (`brew install --cask <token>`), kept outside `Brewfile` as general desktop, situational or `.pkg` sudo-prompting software.
- `Tap cask`: third-party Homebrew tap cask requiring `brew trust <tap>` before installing.
- `MAS`: Mac App Store app (`mas install <id>` after signing into the App Store app).
- `Manual`: direct vendor download with no Homebrew Cask or Mac App Store package.

## Actively used apps (36)

| App | Bundle ID | Status | Install command or source | Setup notes |
|---|---|---|---|---|
| **1Password** | `com.1password.1password` | `Brewfile` | `cask "1password"` (`https://1password.com/`) | Sign into account and enable SSH Agent under Settings, Developer to provide `/Applications/1Password.app/Contents/MacOS/op-ssh-sign` for `install.sh`. |
| **Agent Caffeine** | `com.caffeinagent.app` | `Tap cask` | `brew trust vinenastudio/tap && brew install --cask vinenastudio/tap/agent-caffeine` (`https://caffeinagent.com`) | Paid license after 7-day trial, updates via Sparkle. Open Settings, Agents, Set up for agents and run `agent-caffeine mcp` (bundles `~/.local/bin/agent-caffeine`). |
| **Antigravity** | `com.google.antigravity` | `Brewfile` | `cask "antigravity"` (`https://antigravity.google/product/antigravity-2`) | Sign into Google account. Installs CLI at `~/.local/bin/agy`. |
| **Antinote** | `com.chabomakers.Antinote` | `Brew cask` | `brew install --cask antinote` (`https://antinote.io/`) | Paid license or trial activation, Sparkle updates. |
| **AppCleaner** | `net.freemacsoft.AppCleaner` | `Brew cask` | `brew install --cask appcleaner` (`https://freemacsoft.net/appcleaner/`) | Freeware, no account needed. |
| **ChatGPT** | `com.openai.codex` | `Brewfile` | `cask "chatgpt"` (`https://chatgpt.com/`) | Sign into ChatGPT account, optional global shortcut. |
| **Claude** | `com.anthropic.claudefordesktop` | `Brewfile` | `cask "claude"` (`https://claude.com/download`) | Sign into Claude account. |
| **CleanShot X** | `pl.maketheweb.cleanshotx` | `Brewfile` | `cask "cleanshot"` (`https://cleanshot.com/`) | Paid license key, grant Screen Recording and Accessibility permissions. |
| **Clop** | `com.lowtechguys.Clop` | `Brewfile` | `cask "clop"` (`https://lowtechguys.com/clop/`) | Optional Pro license, grant Accessibility and Automation permissions, links `~/.local/bin/clop`. |
| **DataGrip** | `com.jetbrains.datagrip` | `Brewfile` | `cask "datagrip"` (`https://www.jetbrains.com/datagrip/`) | Sign into JetBrains account or license. |
| **FluxMarkdown** | `com.xykong.Markdown` | `Brewfile` | `cask "xykong/tap/flux-markdown"` (`https://github.com/xykong/flux-markdown/releases`) | Enable QuickLook preview extension. If previews break, run Help, Repair Quick Look. |
| **Gemini** | `com.google.GeminiMacOS` | `Brewfile` | `cask "google-gemini"` (`https://gemini.google/`) | Sign into Google account. |
| **Ghostty** | `com.mitchellh.ghostty` | `Brewfile` | `cask "ghostty"` (`https://ghostty.org/`) | Grant Accessibility permission for the global `` Cmd+` `` quick terminal. |
| **GitHub Desktop** | `com.github.GitHubClient` | `Brewfile` | `cask "github"` (`https://desktop.github.com/`) | Sign into GitHub account, optional CLI `/usr/local/bin/github`. |
| **Goodnotes** | `com.goodnotesapp.x` | `MAS` | `mas install 1444383602` (`https://apps.apple.com/app/id1444383602`) | Requires Apple Account in App Store, sign into Goodnotes for iCloud and license sync. |
| **Google Chrome** | `com.google.Chrome` | `Brew cask` | `brew install --cask google-chrome` (`https://www.google.com/chrome/`) | Sign into Chrome profiles and sync extensions. |
| **Grammarly Desktop** | `com.grammarly.ProjectLlama` | `Brew cask` | `brew install --cask grammarly-desktop` (`https://www.grammarly.com/desktop`) | Sign into Grammarly account and grant Accessibility permission. |
| **ImageOptim** | `net.pornel.ImageOptim` | `Brew cask` | `brew install --cask imageoptim` (`https://imageoptim.com/mac`) | Freeware, no account needed. |
| **JayJay** | `dev.hewig.jayjay` | `Brewfile` | `cask "hewigovens/tap/jayjay"` (`https://github.com/hewigovens/jayjay/releases`) | Requires `jj` formula, installs `jayjay` CLI. |
| **Kaleidoscope** | `app.kaleidoscope.v4` | `Brewfile` | `cask "kaleidoscope"` (`https://kaleidoscope.app/`) | Paid license, install `ksdiff` CLI integration to `/usr/local/bin/ksdiff`. |
| **Mole** | `com.tw93.MoleApp` | `Brew cask` | `brew install --cask mole-app` (`https://mole.fit/`) | Grant Full Disk Access if deep cleaning is used. |
| **OrbStack** | `dev.kdrag0n.MacVirt` | `Brewfile` | `cask "orbstack"` (`https://orbstack.dev/`) | Launch once to start daemon and link `/usr/local/bin/{docker,orb,orbctl,kubectl}` for `infra up`. |
| **Pages Creator Studio** | `com.apple.Pages` | `MAS` | `mas install 361309726` (`https://apps.apple.com/app/id361309726`) | Requires Apple Account in App Store. |
| **Pixelmator Pro** | `com.pixelmatorteam.pixelmator.x` | `MAS` | `mas install 1289583905` (`https://apps.apple.com/app/id1289583905`) | Paid legacy App Store purchase under Apple Account. |
| **Proxyman** | `com.proxyman.NSProxy` | `Brewfile` | `cask "proxyman"` (`https://proxyman.com/`) | Optional paid license, install privileged helper and trust Proxyman Root CA for HTTPS inspection. |
| **Rex Beta** | `com.superlogical.rex` | `Manual` | `https://www.superlogical.com` (vendor invite/beta portal) | Drag `Rex Beta.app` into `/Applications`. Self-hosts local Rex server (`Contents/Helpers/Rex Server.rex/Contents/MacOS/rex`). |
| **Shottr** | `cc.ffitch.shottr` | `Brewfile` | `cask "shottr"` (`https://shottr.cc/`) | Run `./install.sh --shottr`, assign `⇧⌘3`/`4`/`5` in Preferences, Hotkeys, enable Launch at login, grant Screen Recording, enter license if licensed. |
| **Slack** | `com.tinyspeck.slackmacgap` | `Brew cask` | `brew install --cask slack` (`https://slack.com/`) | Sign into Slack workspaces, grant Screen Recording and Microphone for huddles. |
| **Spokenly** | `app.spokenly` | `Brewfile` | `cask "spokenly"` (`https://spokenly.app/`) | Grant Microphone and Accessibility permissions, configure dictation hotkey and model, CLI at `/usr/local/bin/spokenly`. |
| **Spotify** | `com.spotify.client` | `Brew cask` | `brew install --cask spotify` (`https://www.spotify.com/`) | Sign into Spotify account. |
| **Tailscale** | `io.tailscale.ipn.macsys` | `Brew cask` | `brew install --cask tailscale-app` (`https://tailscale.com/`) | Standalone `macsys` PKG installer (prompts for `sudo`, kept outside `Brewfile`). Sign into tailnet, approve System/Network Extension, link `/usr/local/bin/tailscale`. |
| **Tinycast** | `com.abueammar.tinycast` | `Brewfile` | `cask "tinycast"` (`https://tinycast.dev/`) | macOS 26+ arm64. Grant Accessibility permission and configure launcher hotkey. |
| **Typora** | `abnerworks.Typora` | `Brew cask` | `brew install --cask typora` (`https://typora.io/`) | Enter paid license key. |
| **Xcode** | `com.apple.dt.Xcode` | `MAS` | `mas install 497799835` (`https://apps.apple.com/app/id497799835`) or Apple Developer `.xip` | Requires Apple Account. After install run `sudo xcodebuild -license accept` and `xcodebuild -runFirstLaunch`. |
| **Zed** | `dev.zed.Zed` | `Brewfile` | `cask "zed"` (`https://zed.dev/`) | Optional: run `cli: install` in Zed to link `/usr/local/bin/zed`. |
| **zoom.us** | `us.zoom.xos` | `Brew cask` | `brew install --cask zoom` (`https://www.zoom.us/`) | PKG installer (prompts for `sudo`). Sign into Zoom account, grant Camera, Microphone and Screen Recording permissions. |

## Occasionally used and situational apps (6)

| App | Bundle ID | Status | Install command or source | Setup notes |
|---|---|---|---|---|
| **Android Studio** | `com.google.android.studio` | `Brew cask` | `brew install --cask android-studio` (`https://developer.android.com/studio/`) | Complete SDK and emulator first-run wizard for mobile/Flutter projects. |
| **DeskPad** | `com.stengo.DeskPad` | `Brew cask` | `brew install --cask deskpad` (`https://github.com/Stengo/DeskPad`) | Virtual display utility for screen sharing, grant Screen Recording if prompted. |
| **Hyperkey** | `com.knollsoft.Hyperkey` | `Brew cask` | `brew install --cask hyperkey` (`https://hyperkey.app/`) | Grant Accessibility permission and enable Launch at login. |
| **Redis Insight** | `org.RedisLabs.RedisInsight-V2` | `Brewfile` | `cask "redis-insight"` (`https://redis.io/insight/`) | Point at local `redis://localhost:6379` from `infra up`. |
| **SnippetsLab** | `com.renfei.SnippetsLab` | `MAS` | `mas install 1006087419` (`https://apps.apple.com/app/id1006087419`) | Requires Apple Account in App Store, enable iCloud sync if used. |
| **xScope** | `com.iconfactory.xScope` | `Brew cask` | `brew install --cask xscope` (`https://xscopeapp.com/`) | Enter paid license and grant Screen Recording permission. |

## Mac App Store IDs (5)

`Brewfile` installs the `mas` CLI formula without `mas "..."` entries so `./install.sh --brew` never blocks on GUI App Store authentication. See [Installing macOS apps](../guides/mac-apps.md#mac-app-store-mas-applications) for the install commands.

| App | MAS ID | App Store URL | Notes |
|---|---|---|---|
| **Xcode** | `497799835` | `https://apps.apple.com/app/id497799835` | Or download `.xip` from Apple Developer. |
| **Goodnotes** | `1444383602` | `https://apps.apple.com/app/id1444383602` | iCloud and license sync via Goodnotes account. |
| **Pages Creator Studio** | `361309726` | `https://apps.apple.com/app/id361309726` | Optional iCloud Drive sync. |
| **Pixelmator Pro** | `1289583905` | `https://apps.apple.com/app/id1289583905` | Legacy paid MAS purchase (`1289583905`) rather than the Creator Studio edition (`6746662575`). |
| **SnippetsLab** | `1006087419` | `https://apps.apple.com/app/id1006087419` | Optional iCloud sync. |

## Manual-install applications (1)

This application has no Homebrew Cask or Mac App Store package and requires a direct vendor download (detailed steps in [Installing macOS apps](../guides/mac-apps.md#manual-only-applications)):

| App | Bundle ID | Source | Install artifact |
|---|---|---|---|
| **Rex Beta** | `com.superlogical.rex` | `https://www.superlogical.com` (invite/beta portal) | Drag `Rex Beta.app` into `/Applications`. |

## Omitted categories

This public inventory intentionally omits:

- Apple OS built-ins (such as Safari) and auto-generated helper bundles under `~/Applications`.
- Unused, one-off or duplicate applications.
- Personal music-production software, audio plugins and vendor download/license managers.
- Employer-specific, private, security/VPN and financial applications, which stay outside this public repository.
