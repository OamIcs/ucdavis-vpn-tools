# UC Davis OpenConnect Root LaunchDaemon

Optional always-on daemon for the UC Davis OpenConnect workflow.

Install this only after `../ucdavis-openconnect-vpn` works manually. The daemon
runs OpenConnect as root, monitors reachability, and reconnects when needed.

## Workflow

```text
launchd starts root daemon
  -> daemon checks an internal target
  -> if unreachable, cookie helper runs in the user's GUI session
  -> daemon starts OpenConnect as root
  -> daemon keeps monitoring and reconnects on repeated failure
```

Chrome login still runs as the normal user. OpenConnect runs as root so it can
create `utun` interfaces and update routes/DNS without interactive sudo prompts.

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

Edit:

```text
/Library/Application Support/ucdavis-vpn-daemon/config.env
```

Set at least:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
PING_TARGET=internal-host-or-ip
```

Instead of `PING_TARGET`, you may set `SSH_HOST_ALIAS` to an internal host from
the user's `~/.ssh/config`.

## Use

Check setup:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon doctor
```

Test daemon-managed connection:

```zsh
sudo /usr/local/sbin/ucdavis-vpn-root-daemon connect
sudo /usr/local/sbin/ucdavis-vpn-root-daemon status
```

Start with launchd:

```zsh
sudo launchctl bootstrap system "/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist"
sudo launchctl kickstart -k system/local.ucdavis-openconnect-daemon
```

Inspect or stop:

```zsh
sudo launchctl print system/local.ucdavis-openconnect-daemon
sudo launchctl bootout system "/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist"
```

## Commands

- `doctor`: check root/user context, GUI session, helper, OpenConnect, and Keychain.
- `connect`: connect immediately through the daemon path.
- `status`: show tracked tunnel state, VPN IP, ping result, and cookie metadata.
- `once`: run one monitor check.
- `disconnect`: stop the tracked tunnel with SIGHUP.
- `logout`: terminate the tracked tunnel more explicitly.
- `run`: long-running monitor loop, normally launched by launchd.

Full command reference: `../docs/commands.md`.

## Files

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

## Notes

- Use the daemon for UC Davis VPN/internal resources, not as a general public
  Internet proxy.
- Avoid Clash TUN/VPN/fake-ip DNS mode at the same time. Prefer OpenConnect for
  UC Davis and Clash HTTP/SOCKS/system proxy for other traffic.
- The daemon runs as root; the browser helper runs as the configured GUI user.
- Do not commit installed config, cookies, logs, pid files, or Keychain exports.

## Uninstall

```zsh
cd ucdavis-vpn-launchdaemon
sudo ./uninstall.sh
```
