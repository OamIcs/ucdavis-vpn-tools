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

## Recommended Setup

For first-time setup, run the guided installer from the repository root:

```zsh
cd ..
./setup.sh
```

That script asks for the email, stores the password in Keychain, installs the
LaunchDaemon, and writes the main settings into the daemon config. You should
not need to edit this project's config by hand for a normal install.

After setup, use:

```zsh
ucdavis-vpnctl status
ucdavis-vpnctl connect
ucdavis-vpnctl disconnect
ucdavis-vpnctl on
ucdavis-vpnctl off
ucdavis-vpnctl set-password
```

## First Use

If setup starts the LaunchDaemon, the first connection may open Chrome to the
UC Davis/Microsoft login flow. Complete the login and Duo approval there. The
daemon captures the VPN cookie, starts OpenConnect as root, and then keeps
watching the tunnel.

Check the current state with:

```zsh
ucdavis-vpnctl status
```

If the daemon was installed but not started, start it and connect with:

```zsh
sudo launchctl bootstrap system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
ucdavis-vpnctl on
```

## Basic Commands

```zsh
ucdavis-vpnctl status        # show daemon, tunnel, health check, and cookie state
ucdavis-vpnctl connect       # connect or reconnect now
ucdavis-vpnctl disconnect    # drop the current tunnel; auto reconnect stays enabled
ucdavis-vpnctl off           # pause auto reconnect and log out the tunnel
ucdavis-vpnctl on            # resume auto reconnect and connect now
ucdavis-vpnctl set-password  # update the Keychain password
```

`disconnect` is a tunnel reset. Because automatic reconnect remains enabled,
the daemon may reconnect on the next failed health check. Use `off` when you
want the VPN to stay off, and `on` to resume normal monitoring.

## Manual Install

Use this only if you are deliberately skipping `../setup.sh`:

```zsh
brew install openconnect node
sudo ./install.sh
ucdavis-vpnctl set-password
${EDITOR:-nano} "/Library/Application Support/ucdavis-vpn-daemon/config.env"
sudo launchctl bootstrap system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

The installer writes:

```zsh
/usr/local/sbin/ucdavis-vpn-root-daemon
/usr/local/bin/ucdavis-vpnctl
/usr/local/libexec/ucdavis-openconnect-vpn/ucdavis-vpn-cookie.mjs
/Library/Application Support/ucdavis-vpn-daemon/config.env
/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

The cookie helper is copied into `/usr/local/libexec` so the installed daemon
does not read JavaScript files from the repository checkout.

The installer also removes the old legacy LaunchDaemon label
`com.weyl.ucdavis-openconnect-daemon` if it is present.

Start immediately during install instead of running `launchctl` later:

```zsh
sudo START_AFTER_INSTALL=1 ./install.sh
```

## Advanced Configure

Installed config:

```zsh
/Library/Application Support/ucdavis-vpn-daemon/config.env
```

Important settings:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
HEALTH_CHECK_MODE=auto
HEALTH_MIN_SUCCESS=1
SSH_HOST_ALIAS=your-internal-host
PING_TARGET=
PING_TARGETS=
TCP_TARGET=
TCP_TARGETS=
TCP_PORT=22
TCP_TIMEOUT_SECONDS=3
SSH_CONFIG_TIMEOUT_SECONDS=5
ROUTE_LOOKUP_TIMEOUT_SECONDS=5
CHECK_INTERVAL_SECONDS=60
FAILURE_THRESHOLD=2
RECONNECT_COOLDOWN_SECONDS=180
GUI_SESSION_WAIT_SECONDS=0
GUI_SESSION_POLL_SECONDS=1
MAX_BROWSER_SESSION_ATTEMPTS=2
CONTROL_POLL_SECONDS=1
PRESERVE_DEFAULT_ROUTE=1
DEFAULT_ROUTE_RESTORE_DELAY_SECONDS=2
VPN_SPLIT_ROUTES="169.237.0.0/16 128.120.0.0/16"
VPN_ROUTE_PING_TARGET=1
NETWORK_CHANGE_DETECT=1
NETWORK_CHANGE_SETTLE_SECONDS=3
NETWORK_CHANGE_BYPASS_COOLDOWN=1
CLOSE_EXISTING_VPN_SESSIONS=1
AUTO_RECONNECT=1
CONNECT_ON_START=1
```

`HEALTH_CHECK_MODE` can be `auto`, `ping`, `tcp`, or `tunnel`. `auto` uses
`TCP_TARGETS`/`TCP_TARGET` if set, otherwise `PING_TARGETS`/`PING_TARGET` or
`SSH_HOST_ALIAS`, otherwise only checks that OpenConnect and the `utun` VPN
address exist. `HEALTH_MIN_SUCCESS=1` means any one configured target passing
is enough, so one down internal host will not force a reconnect. Set
`TCP_TARGETS="host-a:22 host-b:443"` if ICMP ping is blocked or you prefer
checking service ports instead of a single ping target. Set
`HEALTH_CHECK_MODE=tunnel` to avoid configuring any internal host, with the
tradeoff that it verifies the tunnel is up but not that an internal service is
reachable.
When `SSH_HOST_ALIAS` is used, `SSH_CONFIG_TIMEOUT_SECONDS` bounds the `ssh -G`
config lookup so a bad SSH config cannot hang the daemon control loop.
`ROUTE_LOOKUP_TIMEOUT_SECONDS` bounds macOS route lookups, which can otherwise
hang during Wi-Fi/DNS transitions and freeze the monitor loop.
When the daemon starts before the desktop GUI is ready after boot,
`GUI_SESSION_WAIT_SECONDS=0` means it keeps polling the user's GUI session until
it is available, then immediately starts the browser login helper. Set a positive
number to use a bounded wait instead.
`MAX_BROWSER_SESSION_ATTEMPTS=2` stops automatic browser session acquisition
after two attempts while the VPN is still not verified by the health check.
The attempt state is stored under `/var/run`, so it resets after reboot. After
fixing the network or logging in manually, a manual `connect` also clears the
block and starts a fresh attempt:

`PRESERVE_DEFAULT_ROUTE=1` keeps the macOS default route on the physical network
after OpenConnect starts. This prevents the VPN route script from temporarily
turning the tunnel into the machine-wide default internet path.
`VPN_SPLIT_ROUTES` lists campus routes that should still go through the VPN
tunnel while the default route stays on the physical network. `VPN_ROUTE_PING_TARGET=1`
also pins the resolved health-check target, such as an SSH alias host or
`TCP_TARGET`, through the tunnel.
`NETWORK_CHANGE_DETECT=1` makes the daemon watch the physical default route and
Wi-Fi network name during its sleep loop. When they change, it repairs stale
routes, waits `NETWORK_CHANGE_SETTLE_SECONDS`, and checks/reconnects the VPN
without waiting for the normal monitor interval or cooldown.
`CLOSE_EXISTING_VPN_SESSIONS=1` tells the browser helper to select existing VPN
web sessions for closure on the Ivanti open-sessions page before continuing.

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
ucdavis-vpnctl set-password
ucdavis-vpnctl connect
ucdavis-vpnctl disconnect
ucdavis-vpnctl logout
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

# Log out the tunnel but leave automatic reconnect enabled.
ucdavis-vpnctl logout

# Pause automatic reconnect and log out the tunnel.
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
