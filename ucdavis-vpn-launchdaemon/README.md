# UC Davis OpenConnect Root LaunchDaemon

This subproject is the optional always-on layer for the OpenConnect VPN flow.

It installs a root LaunchDaemon that monitors VPN reachability and starts or
restarts OpenConnect automatically. It does not replace the browser login
helper from `../ucdavis-openconnect-vpn`; it reuses that helper to obtain the
Ivanti VPN cookie.

## Basic Idea

The daemon solves the part that is awkward for a manual shell script:
long-running background supervision.

```text
launchd starts root daemon
        |
        v
daemon checks internal reachability target
        |
        +-- reachable ----> sleep until next check
        |
        +-- not reachable
                |
                v
        run cookie helper inside user's GUI session
                |
                v
        start OpenConnect as root
                |
                v
        keep monitoring and reconnect on repeated failure
```

Chrome still runs as the normal user, not as root. The daemon uses
`launchctl asuser` and `sudo -u` to run the cookie helper in the configured
user's GUI session. OpenConnect then runs as root so it can create the `utun`
interface and manage routes/DNS without interactive sudo prompts.

## Relationship To The User Tool

This daemon depends on the cookie helper from the user tool:

```zsh
../ucdavis-openconnect-vpn/bin/ucdavis-vpn-cookie.mjs
```

The helper:

```text
starts or reuses Chrome
opens the UC Davis / Ivanti login page
handles email/password automation where possible
waits for normal SSO/MFA completion
returns the VPN cookie JSON to the daemon
```

The daemon then starts:

```zsh
openconnect --protocol=nc --cookie-on-stdin vpn.engineering.ucdavis.edu
```

Use the user-level tool first. Install this daemon only after manual
`connect`, `status`, and `disconnect` work reliably.

## Requirements

- macOS
- Homebrew `openconnect`
- Node.js available to root, or `NODE_BIN` configured
- A Keychain item for the user's VPN password
- A logged-in user GUI session for browser login and Duo/MFA
- A reachability target, either `SSH_HOST_ALIAS` or `PING_TARGET`

Install OpenConnect:

```zsh
brew install openconnect
```

Store the password in Keychain, replacing the email address:

```zsh
read -s "VPN_PASSWORD?UC Davis VPN password: "
security add-generic-password \
  -a "your_email@ucdavis.edu" \
  -s ucdavis-openconnect-vpn \
  -l "UC Davis VPN password" \
  -T /usr/bin/security \
  -U \
  -w "$VPN_PASSWORD"
unset VPN_PASSWORD
```

## Install

From the repository root:

```zsh
cd ucdavis-vpn-launchdaemon
sudo ./install.sh
```

The installer writes:

```text
/usr/local/sbin/ucdavis-vpn-root-daemon
/Library/Application Support/ucdavis-vpn-daemon/config.env
/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

By default, installation does not start the daemon.

To install and start immediately:

```zsh
sudo START_AFTER_INSTALL=1 ./install.sh
```

## Configure

Installed config:

```text
/Library/Application Support/ucdavis-vpn-daemon/config.env
```

Important settings:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
SSH_HOST_ALIAS=your-internal-host
PING_TARGET=
CHECK_INTERVAL_SECONDS=60
FAILURE_THRESHOLD=2
RECONNECT_COOLDOWN_SECONDS=180
AUTO_RECONNECT=1
CONNECT_ON_START=1
```

Use `SSH_HOST_ALIAS` if you already have an internal host in `~/.ssh/config`.
Otherwise set `PING_TARGET` to an internal IP or hostname that should only work
through the VPN.

After editing config:

```zsh
sudo launchctl bootstrap system "/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist"
sudo launchctl kickstart -k system/local.ucdavis-openconnect-daemon
```

## First Run

Check daemon prerequisites:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon doctor
```

Test one daemon-managed connection:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon connect
```

Check status:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon status
```

Run one monitor check:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon once
```

Only after these work should you enable the launchd loop.

## Commands

- `doctor`: check root/user context, GUI session, helper path, OpenConnect, and Keychain access.
- `status`: show tracked OpenConnect state, VPN IP, ping status, routes, processes, and cookie metadata.
- `once`: run one monitor check and reconnect if configured.
- `connect`: connect immediately through the root daemon path.
- `disconnect`: stop the tracked tunnel with SIGHUP.
- `logout`: terminate the tracked tunnel with stronger logout semantics.
- `run`: start the long-running monitor loop, normally invoked by launchd.

For more detail, see `../docs/commands.md`.

## LaunchDaemon Control

Start the daemon:

```zsh
sudo launchctl bootstrap system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

Restart after config or script changes:

```zsh
sudo launchctl kickstart -k system/local.ucdavis-openconnect-daemon
```

Inspect launchd state:

```zsh
sudo launchctl print system/local.ucdavis-openconnect-daemon
```

Stop and unload:

```zsh
sudo launchctl bootout system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

## State And Logs

```text
Config:  /Library/Application Support/ucdavis-vpn-daemon/config.env
Plist:   /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
State:   /var/run/ucdavis-openconnect-daemon/
DB:      /var/db/ucdavis-openconnect-daemon/
Logs:    /var/log/ucdavis-openconnect-daemon/
```

Logs:

```zsh
tail -f /var/log/ucdavis-openconnect-daemon/daemon.log
tail -f /var/log/ucdavis-openconnect-daemon/openconnect.log
tail -f /var/log/ucdavis-openconnect-daemon/launchd.err.log
```

## Security Notes

- The daemon runs as root.
- The browser helper runs as the configured user with `launchctl asuser`.
- Chrome uses a dedicated profile and local DevTools port.
- Do not commit `/Library/Application Support/ucdavis-vpn-daemon/config.env`.
- Do not commit cookies, logs, pid files, or Keychain exports.

## Uninstall

```zsh
cd ucdavis-vpn-launchdaemon
sudo ./uninstall.sh
```
