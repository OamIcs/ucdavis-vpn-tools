# UC Davis OpenConnect Root LaunchDaemon

Root-level LaunchDaemon wrapper for the OpenConnect-based VPN flow.

The daemon runs as root so OpenConnect can create the `utun` interface and
manage routes/DNS without sudo prompts. The browser/SAML login helper still runs
inside the normal user's GUI session, so Chrome is not launched as root.

## Relationship To The User Tool

This daemon is intentionally separate from `../ucdavis-openconnect-vpn`. It
reuses one helper from that project:

```zsh
../ucdavis-openconnect-vpn/bin/ucdavis-vpn-cookie.mjs
```

That helper starts or reuses a dedicated Chrome profile, obtains the VPN web
session cookie, and returns it to the root daemon. The daemon then starts:

```zsh
openconnect --protocol=nc
```

## Requirements

- macOS
- Homebrew `openconnect`
- Node.js available to root, or `NODE_BIN` configured
- A Keychain item for the user's VPN password
- A logged-in user GUI session for browser login and Duo/MFA

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

```zsh
/usr/local/sbin/ucdavis-vpn-root-daemon
/usr/local/bin/ucdavis-vpnctl
/Library/Application Support/ucdavis-vpn-daemon/config.env
/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

The installer also removes the old legacy LaunchDaemon label
`com.weyl.ucdavis-openconnect-daemon` if it is present.

Start immediately during install:

```zsh
sudo START_AFTER_INSTALL=1 ./install.sh
```

## Configure

Installed config:

```zsh
/Library/Application Support/ucdavis-vpn-daemon/config.env
```

Important settings:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
SSH_HOST_ALIAS=your-internal-host
PING_TARGET=
SSH_CONFIG_TIMEOUT_SECONDS=5
CHECK_INTERVAL_SECONDS=60
FAILURE_THRESHOLD=2
RECONNECT_COOLDOWN_SECONDS=180
GUI_SESSION_WAIT_SECONDS=0
GUI_SESSION_POLL_SECONDS=1
MAX_BROWSER_SESSION_ATTEMPTS=2
CONTROL_POLL_SECONDS=1
PRESERVE_DEFAULT_ROUTE=1
DEFAULT_ROUTE_RESTORE_DELAY_SECONDS=2
AUTO_RECONNECT=1
CONNECT_ON_START=1
```

If you do not use an SSH alias, set `PING_TARGET` to an internal IP or hostname.
When `SSH_HOST_ALIAS` is used, `SSH_CONFIG_TIMEOUT_SECONDS` bounds the `ssh -G`
config lookup so a bad SSH config cannot hang the daemon control loop.
When the daemon starts before the desktop GUI is ready after boot,
`GUI_SESSION_WAIT_SECONDS=0` means it keeps polling the user's GUI session until
it is available, then immediately starts the browser login helper. Set a positive
number to use a bounded wait instead.
`MAX_BROWSER_SESSION_ATTEMPTS=2` stops automatic browser session acquisition
after two attempts while the VPN is still not verified by the ping monitor.
The attempt state is stored under `/var/run`, so it resets after reboot. After
fixing the network or logging in manually, a manual `connect` also clears the
block and starts a fresh attempt:

`PRESERVE_DEFAULT_ROUTE=1` keeps the macOS default route on the physical network
after OpenConnect starts. This prevents the VPN route script from temporarily
turning the tunnel into the machine-wide default internet path.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon connect
```

After editing config:

```zsh
sudo launchctl bootout system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

## Commands

Normal no-sudo control:

```zsh
ucdavis-vpnctl status
ucdavis-vpnctl doctor
ucdavis-vpnctl connect
ucdavis-vpnctl disconnect
ucdavis-vpnctl off
ucdavis-vpnctl on
```

The user CLI sends privileged actions through the running root LaunchDaemon's
control channel. It does not need sudo after installation.

Root daemon commands:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon doctor
sudo /usr/local/sbin/ucdavis-vpn-root-daemon status
sudo /usr/local/sbin/ucdavis-vpn-root-daemon once
sudo /usr/local/sbin/ucdavis-vpn-root-daemon connect
sudo /usr/local/sbin/ucdavis-vpn-root-daemon disconnect
sudo /usr/local/sbin/ucdavis-vpn-root-daemon logout
```

Quick VPN controls:

```zsh
# Connect or reconnect now.
ucdavis-vpnctl connect

# Disconnect the tunnel but leave automatic reconnect enabled.
ucdavis-vpnctl disconnect

# Pause automatic reconnect and disconnect the tunnel.
ucdavis-vpnctl off

# Resume automatic reconnect and connect now.
ucdavis-vpnctl on
```

LaunchDaemon control:

```zsh
sudo launchctl bootstrap system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
sudo launchctl print system/local.ucdavis-openconnect-daemon
sudo launchctl bootout system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

Logs:

```zsh
tail -f /var/log/ucdavis-openconnect-daemon/daemon.log
tail -f /var/log/ucdavis-openconnect-daemon/openconnect.log
tail -f /var/log/ucdavis-openconnect-daemon/launchd.err.log
```

## Tests

The unit tests run without sudo and use temporary state/config directories:

```zsh
ucdavis-vpn-launchdaemon/test/run-unit-tests.zsh
```

## Security Notes

- The daemon runs as root.
- The browser helper runs as the configured user with `launchctl asuser`.
- The no-sudo `ucdavis-vpnctl` command can only talk to the root daemon through a
  per-user control directory owned by the configured console user.
- Chrome uses a dedicated profile and local DevTools port.
- Do not commit `/Library/Application Support/ucdavis-vpn-daemon/config.env`.
- Do not commit cookies, logs, pid files, or Keychain exports.

## Uninstall

```zsh
cd ucdavis-vpn-launchdaemon
sudo ./uninstall.sh
```
