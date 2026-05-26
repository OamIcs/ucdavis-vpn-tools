# UC Davis OpenConnect User Tool

This subproject is the manual, user-level VPN tool.

It lets you connect to the UC Davis Engineering VPN gateway with OpenConnect
instead of using the local Ivanti desktop client. The UC Davis / Ivanti server
and web login flow are still used; OpenConnect is only replacing the local VPN
tunnel client.

## Basic Idea

OpenConnect can create the VPN tunnel, but it needs a valid Ivanti web session
cookie. This tool obtains that cookie through Chrome and then starts
OpenConnect.

```text
bin/ucdavis-openconnect-vpn connect
        |
        v
Chrome opens UC Davis / Ivanti login
        |
        v
User completes SSO/MFA
        |
        v
cookie helper reads DS* VPN cookies
        |
        v
OpenConnect starts with --protocol=nc --cookie-on-stdin
        |
        v
macOS gets a utun interface, VPN IP, routes, and DNS
```

The central OpenConnect command is:

```zsh
openconnect --protocol=nc --cookie-on-stdin vpn.engineering.ucdavis.edu
```

The wrapper handles the cookie acquisition, pid file, log file, reconnect retry,
and post-connect reachability check.

## When To Use This Tool

Use this subproject when:

- You want to connect and disconnect manually.
- You are testing whether this OpenConnect flow works on your machine.
- You want the simplest setup before installing any background daemon.
- You need to debug browser login, cookies, OpenConnect arguments, or routes.

If you want always-on reconnect behavior after this works, use
`../ucdavis-vpn-launchdaemon`.

## Requirements

- macOS
- Homebrew `openconnect`
- Node.js
- Google Chrome
- UC Davis VPN account and MFA
- A Keychain item for the VPN password

Install OpenConnect:

```zsh
brew install openconnect
```

## Configure

Create the config directory and copy the example:

```zsh
mkdir -p ~/.config/ucdavis-openconnect-vpn
cp config.env.example ~/.config/ucdavis-openconnect-vpn/config.env
```

Edit:

```zsh
~/.config/ucdavis-openconnect-vpn/config.env
```

At minimum, set:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
```

For reachability checks, set one of these:

```zsh
SSH_HOST_ALIAS=your-internal-ssh-alias
```

or:

```zsh
PING_TARGET=internal-host-or-ip
```

The target should be reachable only through the VPN. `status` and `connect` use
it to decide whether the tunnel is actually useful, not merely running.

## Store The Password In Keychain

Store the VPN password in macOS Keychain:

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

The scripts read the password at runtime and do not write it to repository
files.

## First Run

Check local dependencies and config:

```zsh
bin/ucdavis-openconnect-vpn doctor
```

Test browser login and cookie capture without starting the VPN:

```zsh
bin/ucdavis-openconnect-vpn cookie
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

## Commands

- `doctor`: check dependencies, config, Keychain, and reachability target.
- `status`: show OpenConnect state, VPN IP, ping status, route, and cookie metadata.
- `cookie`: obtain a browser VPN cookie without starting OpenConnect.
- `relogin`: force a fresh browser login and cookie refresh.
- `connect`: obtain or reuse a cookie, start OpenConnect, and verify reachability.
- `disconnect`: send SIGHUP to OpenConnect and preserve browser login where possible.
- `logout`: terminate OpenConnect with stronger logout semantics.

For more detail, see `../docs/commands.md`.

## Browser Session

Chrome uses a dedicated profile:

```zsh
~/.local/state/ucdavis-vpn-chrome-profile
```

The visible login tab can be closed after a cookie is captured while the profile
and cookies remain available for later reconnects.

## State And Logs

```text
Config:       ~/.config/ucdavis-openconnect-vpn/config.env
Chrome data:  ~/.local/state/ucdavis-vpn-chrome-profile
State:        ~/.local/state/ucdavis-openconnect-vpn/
Logs:         ~/Library/Logs/ucdavis-openconnect-vpn/
```

OpenConnect log:

```zsh
tail -f ~/Library/Logs/ucdavis-openconnect-vpn/openconnect.log
```

## Security Notes

- Do not commit local config files, cookies, logs, browser profiles, or Keychain
  exports.
- Use a private fork if your defaults reveal internal hostnames.
- Review `config.env` before enabling automatic reconnect through the daemon.
