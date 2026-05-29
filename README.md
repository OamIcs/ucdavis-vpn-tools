# UC Davis OpenConnect VPN Tools

Small macOS tools for keeping a UC Davis Engineering VPN connection alive with
OpenConnect.

## Projects

- `ucdavis-openconnect-vpn/`: user-level OpenConnect wrapper plus a Chrome/CDP
  helper that obtains the VPN web login cookie.
- `ucdavis-vpn-launchdaemon/`: root LaunchDaemon that monitors reachability and
  starts OpenConnect automatically.

The tools were tested against a VPN gateway that accepts Juniper Network Connect
style cookies via:

```zsh
openconnect --protocol=nc
```

Your school or department may use a different realm, URL, or policy. Treat the
defaults as examples and review the generated config before enabling any daemon.

## What Is Not Committed

This repository should not contain:

- VPN passwords
- Keychain exports
- Browser profiles
- VPN cookies
- Logs, pid files, or local config files

Passwords are read from macOS Keychain at runtime.

## Quick Start

For a first-time install, use the guided setup from the repository root:

```zsh
./setup.sh
```

The setup script asks for:

- UC Davis email
- VPN password, stored in macOS Keychain
- a simple health-check choice
- whether to start the LaunchDaemon now

It also installs missing Homebrew dependencies if you approve, creates the user
config, installs the root LaunchDaemon, and writes the same basic settings to
both places.

After setup:

```zsh
ucdavis-vpnctl status
ucdavis-vpnctl connect
ucdavis-vpnctl disconnect
ucdavis-vpnctl on
ucdavis-vpnctl off
ucdavis-vpnctl set-password
```

## First Use

If `./setup.sh` starts the daemon, Chrome may open to the UC Davis/Microsoft
login flow. Complete the login and Duo approval in that browser window. After
the VPN connects, check:

```zsh
ucdavis-vpnctl status
```

If you skipped starting the daemon during setup, start it later with:

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

Use `off` when you intentionally do not want the VPN to reconnect, for example
on a network where VPN access is broken. Use `on` when you want the daemon to
resume normal monitoring.

## Config Files

There are two config files because the tools run in different security contexts:

- `~/.config/ucdavis-openconnect-vpn/config.env` is for the user-level helper
  and manual debugging commands.
- `/Library/Application Support/ucdavis-vpn-daemon/config.env` is for the root
  LaunchDaemon that keeps the VPN connected.

Most users do not need to edit either file during first install. `./setup.sh`
keeps the important values in sync. Edit them only for advanced settings such as
custom split routes, retry timing, browser profile paths, or multiple health
targets.

## Manual Install

Use the manual path only if you do not want the guided setup:

```zsh
brew install openconnect node
cd ucdavis-vpn-launchdaemon
sudo ./install.sh
ucdavis-vpnctl set-password
${EDITOR:-nano} "/Library/Application Support/ucdavis-vpn-daemon/config.env"
sudo launchctl bootstrap system /Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
```

## Safety

These tools automate authentication and network routing. Before sharing or
publishing your fork, verify that no personal config, cookies, logs, or tokens
are staged:

```zsh
git status --short
rg -n 'your[_]email|g[h]p_|D[S]ID|D[S]SIGNIN|/User[s]/[^ ]+' .
```
