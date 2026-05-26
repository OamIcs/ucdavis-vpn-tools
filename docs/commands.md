# Command Reference

This document explains every command exposed by the two tools in this
repository.

Use the user-level tool first. Install the LaunchDaemon only after manual
connect/disconnect works reliably.

## User Tool Commands

Run these from `ucdavis-openconnect-vpn/`:

```zsh
bin/ucdavis-openconnect-vpn <command>
```

The user tool reads:

```text
~/.config/ucdavis-openconnect-vpn/config.env
```

### `doctor`

Checks local prerequisites and prints the active configuration paths.

```zsh
bin/ucdavis-openconnect-vpn doctor
```

Use this before the first connection attempt. It reports config, server, email,
Chrome profile, Node.js, OpenConnect, `vpnc-script`, Keychain status, and the
resolved reachability target.

### `status`

Shows whether the tracked OpenConnect process is running.

```zsh
bin/ucdavis-openconnect-vpn status
```

It reports OpenConnect state, VPN IP, ping status, VPN gateway route, Chrome
DevTools status, and cached cookie metadata.

### `cookie`

Starts or reuses the dedicated Chrome profile and obtains a VPN web cookie.

```zsh
bin/ucdavis-openconnect-vpn cookie
```

This command does not start OpenConnect. It verifies that browser login can
produce the Ivanti VPN cookie needed by OpenConnect. Successful output should
include `Cookie: present` and usually a `DSID` cookie.

### `relogin`

Forces a new browser login and refreshes the VPN cookie.

```zsh
bin/ucdavis-openconnect-vpn relogin
```

Use this when a cookie is stale, login state changed, or you want to force MFA
and login from scratch.

### `connect`

Obtains or reuses a VPN cookie, then starts OpenConnect in the background.

```zsh
bin/ucdavis-openconnect-vpn connect
```

The command flow is:

```text
check existing OpenConnect pid
repair stale VPN gateway route if needed
get VPN cookie from Chrome
start OpenConnect with --protocol=nc --cookie-on-stdin
write pid file
verify internal reachability
print status
```

By default the user tool starts OpenConnect through `nohup` so the tunnel does
not exit when the wrapper process receives `SIGHUP`. If OpenConnect rejects the
first cookie, the command forces one relogin and retries once.

### `disconnect`

Stops the tracked OpenConnect process with `SIGHUP`.

```zsh
bin/ucdavis-openconnect-vpn disconnect
```

Use this for a normal local disconnect when you want to preserve the browser
login session if the server allows it.

### `logout`

Stops the tracked OpenConnect process with `SIGTERM`.

```zsh
bin/ucdavis-openconnect-vpn logout
```

Use this when you want stronger logout semantics on the VPN session. The next
connection may need a fresh browser login.

## Root LaunchDaemon Commands

After installation, run these commands as root:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon <command>
```

The daemon reads:

```text
/Library/Application Support/ucdavis-vpn-daemon/config.env
```

### `doctor`

Checks root daemon prerequisites.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon doctor
```

It reports root/user context, GUI session availability, email, Node.js, cookie
helper path, OpenConnect, `vpnc-script`, ping target, and Keychain access from
the configured user.

### `status`

Shows daemon-tracked VPN state.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon status
```

It reports the LaunchDaemon label, config path, tracked OpenConnect pid, VPN IP,
ping status, VPN gateway route, OpenConnect processes, and cached cookie
metadata.

### `once`

Runs one monitor check.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon once
```

If the internal target is reachable, it logs success and exits. If the target is
not reachable and `AUTO_RECONNECT=1`, it attempts to connect.

### `connect`

Connects immediately through the root daemon path.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon connect
```

The command flow is:

```text
check tracked OpenConnect pid
check target reachability
run cookie helper in the configured user's GUI session
start OpenConnect as root
retry once with forced browser relogin if OpenConnect fails
```

Use this after `doctor` succeeds and before enabling automatic launchd startup.

### `disconnect`

Stops the daemon-tracked OpenConnect process with `SIGHUP`.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon disconnect
```

Use this to stop the current tunnel while preserving browser login state where
possible.

### `logout`

Stops the daemon-tracked OpenConnect process with `SIGTERM`.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon logout
```

Use this when you want the daemon-tracked VPN session terminated with stronger
logout semantics.

### `run`

Starts the long-running monitor loop.

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon run
```

You normally do not run this by hand. The LaunchDaemon plist runs it through
launchd. The loop optionally connects on startup, checks reachability every
`CHECK_INTERVAL_SECONDS`, counts failures, reconnects after
`FAILURE_THRESHOLD`, and honors `RECONNECT_COOLDOWN_SECONDS`.

## Installer Commands

Run these from `ucdavis-vpn-launchdaemon/`.

### `install.sh`

Installs the root daemon files.

```zsh
sudo ./install.sh
```

It writes:

```text
/usr/local/sbin/ucdavis-vpn-root-daemon
/Library/Application Support/ucdavis-vpn-daemon/config.env
/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

It does not start the daemon unless requested:

```zsh
sudo START_AFTER_INSTALL=1 ./install.sh
```

### `uninstall.sh`

Removes the LaunchDaemon installation.

```zsh
sudo ./uninstall.sh
```

Use this to disable and remove the root daemon path. It does not remove the
user-level project.

## launchctl Commands

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

## Log Commands

User tool logs:

```zsh
tail -f ~/Library/Logs/ucdavis-openconnect-vpn/openconnect.log
```

Daemon logs:

```zsh
tail -f /var/log/ucdavis-openconnect-daemon/daemon.log
tail -f /var/log/ucdavis-openconnect-daemon/openconnect.log
tail -f /var/log/ucdavis-openconnect-daemon/launchd.err.log
```

Use OpenConnect logs for tunnel negotiation and route/DNS script output. Use
daemon logs for monitor decisions and reconnect attempts.
