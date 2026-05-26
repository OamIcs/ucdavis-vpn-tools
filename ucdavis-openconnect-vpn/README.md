# UC Davis OpenConnect User Tool

Manual user-level tool for connecting to the UC Davis Engineering VPN with
OpenConnect.

Use this first. It verifies the full flow before you install any background
daemon.

## Workflow

```text
bin/ucdavis-openconnect-vpn connect
  -> opens/reuses Chrome for UC Davis login
  -> reads the VPN cookie from Chrome
  -> starts OpenConnect with that cookie
  -> checks that an internal target is reachable
```

Chrome handles UC Davis/Ivanti web login and MFA. OpenConnect creates the VPN
tunnel.

## Install

```zsh
brew install openconnect
```

```zsh
mkdir -p ~/.config/ucdavis-openconnect-vpn
cp config.env.example ~/.config/ucdavis-openconnect-vpn/config.env
```

Edit `~/.config/ucdavis-openconnect-vpn/config.env`:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
PING_TARGET=internal-host-or-ip
```

Instead of `PING_TARGET`, you may set `SSH_HOST_ALIAS` to an internal host from
`~/.ssh/config`.

Store the VPN password in Keychain:

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

## Use

Check setup:

```zsh
bin/ucdavis-openconnect-vpn doctor
```

Connect:

```zsh
bin/ucdavis-openconnect-vpn connect
```

Check status:

```zsh
bin/ucdavis-openconnect-vpn status
```

Disconnect:

```zsh
bin/ucdavis-openconnect-vpn disconnect
```

Force a fresh browser login:

```zsh
bin/ucdavis-openconnect-vpn relogin
```

## Commands

- `doctor`: check config, dependencies, Keychain, and reachability target.
- `cookie`: test browser login/cookie capture without starting VPN.
- `connect`: get/reuse cookie and start OpenConnect.
- `status`: show tunnel state, VPN IP, ping result, and cookie metadata.
- `disconnect`: stop OpenConnect while preserving browser login where possible.
- `logout`: terminate the VPN session more explicitly.

Full command reference: `../docs/commands.md`.

## Files

```text
Config:  ~/.config/ucdavis-openconnect-vpn/config.env
Chrome:  ~/.local/state/ucdavis-vpn-chrome-profile
State:   ~/.local/state/ucdavis-openconnect-vpn/
Logs:    ~/Library/Logs/ucdavis-openconnect-vpn/
```

## Notes

- Use this tool for UC Davis VPN/internal resources, not as a general public
  Internet proxy.
- Avoid Clash TUN/VPN/fake-ip DNS mode at the same time. Prefer OpenConnect for
  UC Davis and Clash HTTP/SOCKS/system proxy for other traffic.
- Do not commit local config, cookies, logs, browser profiles, or Keychain
  exports.
