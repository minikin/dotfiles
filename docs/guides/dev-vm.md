# Dev VM on AWS

`devvm` connects to an EC2 dev VM through AWS Systems Manager (SSM), signing
in to AWS IAM Identity Center (SSO) and starting the VM first when needed.
`install.sh` links `bin/devvm` to `~/.local/bin/devvm`.

```sh
devvm                 # sign in if needed, start the VM if stopped, then ssh to it
devvm -L 3000:localhost:3000   # extra arguments go to ssh
devvm stop            # stop the VM, the disk and files are kept
devvm start           # start it without connecting
devvm status          # signed in or not, VM state, SSM agent state
devvm login           # aws sso login for the profile
```

EC2 start waits via `ec2 wait instance-running`, and `DEVVM_WAIT` (300 seconds
by default) controls how long `devvm` polls for its SSM agent to report
`Online` afterwards. A VM that is `stopping` is started once it has stopped.

## One-time setup

The repo is public, so it holds no account, instance or SSO URL. `devvm`
requires `aws` (`awscli`) and the AWS `session-manager-plugin` (installed
separately, not in `Brewfile`), and reads your target config from:

1. An SSO profile in `~/.aws/config`, from `aws configure sso`, with its
   `region`.
2. A host in `~/.ssh/config` whose `HostName` is the instance ID, with
   `devvm` as its proxy, so `ssh` and VS Code Remote-SSH also sign in and
   start the VM:

   ```ssh-config
   Host dev-vm
     HostName i-0123456789abcdef0
     User ubuntu
     IdentityFile ~/.ssh/dev-vm_ed25519
     ProxyCommand ~/.local/bin/devvm proxy %h %p
   ```

With the host and the profile both named `dev-vm`, nothing else is needed.
Otherwise set these in the environment or as `KEY=value` lines in
`~/.config/devvm/config`. The environment wins over the file.

| Variable | Default | Effect |
| --- | --- | --- |
| `DEVVM_HOST` | `dev-vm` | The ssh host alias. Its `HostName`, from `ssh -G`, is the instance ID. |
| `DEVVM_PROFILE` | the host alias | The AWS CLI profile. |
| `DEVVM_REGION` | the profile's `region` | The AWS region. |
| `DEVVM_SIGNIN_URL` | none | A page `devvm` opens before `aws sso login`, then waits for Enter. |
| `DEVVM_WAIT` | `300` | Seconds to poll the SSM agent for `Online` after EC2 reaches `running`. |

`devvm proxy` runs with the `DEVVM_PROFILE` and `DEVVM_REGION` of the
environment or the config file, since ssh passes it only the instance ID and
port.

## Signing in with Google

When the AWS access portal signs in through a Google Workspace account,
`aws sso login` fails in a browser that is not signed in to that account. AWS
shows "Something doesn't compute. We couldn't verify your sign-in
credentials." Sign in to Google with the work account, open AWS from Google's
app launcher (the Amazon tile), then run `devvm login` again. `devvm` prints
this hint when the sign-in fails.

To skip the detour, copy the Amazon tile's link from the app launcher into
`DEVVM_SIGNIN_URL`. `devvm` then opens it before every sign-in and waits for
Enter. In `devvm proxy` under Remote-SSH, which has no terminal, it opens
the page and goes straight on to `aws sso login`.

## Troubleshooting

| Error | Cause |
| --- | --- |
| `TargetNotConnected` | The VM is stopped or its SSM agent is down. `devvm` starts a stopped VM. `devvm status` shows the agent state. |
| `Token has expired and refresh failed` | The SSO session ended, after 12 hours on a typical setup. `devvm` signs in again. |
| `has no instance ID as HostName` | `DEVVM_HOST` names a host whose `HostName` is not an `i-` instance ID. |
| `no region for profile` | Set `region` on the profile in `~/.aws/config` or `DEVVM_REGION`. |
