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

Install dependencies:

```zsh
brew install openconnect
```

For the user-level OpenConnect tool:

```zsh
cd ucdavis-openconnect-vpn
mkdir -p ~/.config/ucdavis-openconnect-vpn
cp config.env.example ~/.config/ucdavis-openconnect-vpn/config.env
${EDITOR:-nano} ~/.config/ucdavis-openconnect-vpn/config.env
bin/ucdavis-openconnect-vpn doctor
bin/ucdavis-openconnect-vpn set-password
```

In that config, set `UC_DAVIS_EMAIL` and choose a health check. You can use
`PING_TARGETS`, `TCP_TARGETS`, `SSH_HOST_ALIAS`, or `HEALTH_CHECK_MODE=tunnel`.
The password is not stored in the config file; `set-password` saves it in macOS
Keychain.

For the root OpenConnect daemon:

```zsh
cd ucdavis-vpn-launchdaemon
sudo ./install.sh
ucdavis-vpnctl set-password
```

Read each project's README before enabling automatic reconnect. The root daemon
has its own installed config at
`/Library/Application Support/ucdavis-vpn-daemon/config.env`.

## Safety

These tools automate authentication and network routing. Before sharing or
publishing your fork, verify that no personal config, cookies, logs, or tokens
are staged:

```zsh
git status --short
rg -n 'your[_]email|g[h]p_|D[S]ID|D[S]SIGNIN|/User[s]/[^ ]+' .
```
