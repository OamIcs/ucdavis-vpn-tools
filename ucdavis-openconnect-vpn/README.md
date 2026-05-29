# UC Davis OpenConnect User Tool

User-level wrapper for connecting to a UC Davis Engineering VPN gateway with
OpenConnect.

The wrapper starts or reuses a dedicated Chrome profile, obtains the VPN web
login cookie through the normal browser authentication flow, and passes that
cookie to:

```zsh
openconnect --protocol=nc
```

## Requirements

- macOS
- Homebrew `openconnect`
- Node.js
- Google Chrome
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
${EDITOR:-nano} ~/.config/ucdavis-openconnect-vpn/config.env
```

At minimum, set your UC Davis email and choose how the tool should verify the
VPN:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
```

Useful config fields:

- `SERVER`: VPN gateway hostname. The default is
  `vpn.engineering.ucdavis.edu`.
- `UC_DAVIS_EMAIL`: email submitted to the Microsoft/UC Davis login flow.
- `KEYCHAIN_SERVICE`: Keychain service name used for the password lookup. Keep
  this aligned with `set-password`.
- `HEALTH_CHECK_MODE`: `auto`, `ping`, `tcp`, or `tunnel`. `auto` uses
  `TCP_TARGETS`/`TCP_TARGET` if set, otherwise `PING_TARGETS`/`PING_TARGET` or
  `SSH_HOST_ALIAS`, otherwise tunnel presence.
- `HEALTH_MIN_SUCCESS`: number of health targets that must pass. The default is
  `1`, so one down internal host does not force a reconnect if another target
  is reachable.
- `SSH_HOST_ALIAS`: SSH config alias to resolve with `ssh -G`, such as a host
  from `~/.ssh/config`. In `ping` mode, the resolved hostname is pinged. In
  `tcp` mode, it is checked on `TCP_PORT`.
- `PING_TARGET`: internal host or IP to ping.
- `PING_TARGETS`: space-separated internal hosts or IPs to ping. The check
  succeeds when at least `HEALTH_MIN_SUCCESS` targets answer.
- `TCP_TARGET`: internal host and optional port to check with TCP, such as
  `internal-host:22`. This avoids relying on ICMP ping.
- `TCP_TARGETS`: space-separated TCP targets, such as
  `host-a:22 host-b:443`.
- `TCP_PORT`: default TCP port when `TCP_TARGET` or `SSH_HOST_ALIAS` does not
  include a port.
- `CHROME_PROFILE_DIR`: dedicated Chrome profile for VPN login cookies.
- `CLOSE_WINDOW_AFTER_COOKIE`: close the visible Chrome login tab after a VPN
  cookie is captured.
- `OPENCONNECT_BIN` and `VPNC_SCRIPT`: Homebrew OpenConnect paths. On Apple
  Silicon Homebrew, the defaults under `/opt/homebrew` are usually correct.
- `USE_SUDO`: keep `1` for direct user-level `connect`, because OpenConnect
  needs elevated privileges to create the tunnel interface.

After editing config, run:

```zsh
bin/ucdavis-openconnect-vpn doctor
```

## Keychain

Store or update the VPN password in macOS Keychain:

```zsh
bin/ucdavis-openconnect-vpn set-password
```

The scripts read the password at runtime and do not write it to repository
files.

## Commands

```zsh
bin/ucdavis-openconnect-vpn doctor
bin/ucdavis-openconnect-vpn status
bin/ucdavis-openconnect-vpn set-password
bin/ucdavis-openconnect-vpn cookie
bin/ucdavis-openconnect-vpn relogin
bin/ucdavis-openconnect-vpn connect
bin/ucdavis-openconnect-vpn disconnect
bin/ucdavis-openconnect-vpn logout
```

`disconnect` sends SIGHUP to OpenConnect and tries to preserve the browser login
session. `logout` terminates OpenConnect with logout semantics.

## Browser Session

Chrome uses a dedicated profile:

```zsh
~/.local/state/ucdavis-vpn-chrome-profile
```

The visible login tab can be closed after a cookie is captured while the profile
and cookies remain available for later reconnects.

If the VPN gateway reports existing open sessions during login, the browser
helper selects those sessions to close, then clicks `Login` to continue.
If the gateway instead returns a maximum-session or empty-assertion recovery
page, the helper stops and asks for a fresh login from the VPN entry URL so it
can reach the open-sessions page cleanly.

## Security Notes

- Do not commit local config files, cookies, logs, browser profiles, or Keychain
  exports.
- Use a private fork if your defaults reveal internal hostnames.
- Review `config.env` before enabling automatic reconnect.
