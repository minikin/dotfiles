# Phone access with Moshi

[Moshi](https://getmoshi.app) is a terminal app for iOS and Android. It
connects to this Mac over ssh, mosh or [osewa](https://osewa.dev), and its
daemon, `moshi-hook`, sends agent notifications and approvals to the phone.
osewa keeps a session alive on the Mac while the phone changes networks or
sleeps, over QUIC with a TLS WebSocket fallback on port 7322.

## What runs on the Mac

| Piece | Started by | After a reboot |
|---|---|---|
| Remote Login (`sshd`) | macOS, at boot | Running. |
| Tailscale app | login item | Back in the state it was in: connected only if you left it connected. |
| `moshi-hook` daemon | launch agent `sh.brew.moshi-hook`, `RunAtLoad` and `KeepAlive` | Running after login. |
| osewa server | launch agent `dev.osewa.server`, written when the first device enrolls | Running after login. |
| herdr server | the first `herdr` attach | Starts when the phone attaches. Panes and agents from before the reboot are gone. |

The three launch agents are per user, and launchd starts them at login. With
FileVault on, a reboot stops at the unlock screen, and nothing but `sshd`
runs until you log in at the Mac. Until then the phone cannot connect over
osewa, and Moshi's hooks do not answer.

## Set up once

1. `./install.sh --brew` installs `moshi-hook` and `mosh` and appends
   `zsh/zshenv.snippet` to `~/.zshenv`.
2. Install osewa for your user:
   `curl -fsSL https://osewa.dev/install.sh | sh`. It lands in
   `~/.local/bin/osewa`. Skip `osewa login` and `osewa service install`:
   Moshi enrolls the phone and starts the server itself.
3. Turn on Remote Login with `moshi-hook host enable-ssh`, or in System
   Settings under General, Sharing.
4. Run `moshi-hook service install` for the daemon. `moshi-hook host setup`
   pairs the Mac for ssh and mosh access from Moshi, and
   `moshi-hook pair --token <token>`, with the token the app shows, pairs
   the agent hooks.
5. Turn on Tailscale on the Mac and on the phone.
6. In Moshi, long-press the Mac under Connections, choose Edit, set
   Connection to Osewa and save. The first connection shows "Setting up Osewa
   on the host" while `moshi-hook osewa enroll` adds the phone to
   `~/.config/osewa/devices` and starts the server.
7. Run `remote-check`.

## After a reboot

Log in at the Mac, then run `remote-check`:

```text
note FileVault is on: after a reboot nothing below runs until you log in at the Mac
ok   tailscale: connected as <mac>.<tailnet>.ts.net
ok   tailscale: exit node online
ok   ssh: Remote Login is on
ok   ssh: logins find moshi-hook and osewa
ok   moshi-hook: daemon running
ok   moshi-hook: paired
ok   osewa: server running on port 7322
ok   osewa: 1 device(s) enrolled
ok   herdr: server running
```

A `!!` line names the fix and makes `remote-check` return 1. A `warn` line
clears on the next connection from the phone. `remote-check` only reads
state, it never starts anything.

## When the phone still uses mosh

Moshi falls back to mosh without an error in three cases:

- The connection is set to Auto. Auto tries mosh, then Eternal Terminal,
  then ssh, and never picks Osewa.
- You tapped an existing session card marked Mosh. That reattaches the mosh
  session. Start a new one from Connections, or long-press the Mac and choose
  Connect With, then Osewa.
- A command over ssh cannot find `moshi-hook` or `osewa`. sshd runs it in a
  zsh that reads only `~/.zshenv`, so without the snippet neither
  `~/.local/bin` nor `/opt/homebrew/bin` is on its `PATH`. `remote-check`
  reports this as `ssh: logins don't find`.

Moshi's Diagnostics sheet for the host shows its view of osewa: whether the
host and app builds match, whether the server runs, and the port.
