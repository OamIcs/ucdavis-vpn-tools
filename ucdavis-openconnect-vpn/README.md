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
~/.config/ucdavis-openconnect-vpn/config.env
```

At minimum, set:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
```

If you want reachability checks to use an SSH alias, set `SSH_HOST_ALIAS`.
Otherwise set `PING_TARGET` to an internal host or IP that should only be
reachable through the VPN.

## Keychain

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

## Commands

```zsh
bin/ucdavis-openconnect-vpn doctor
bin/ucdavis-openconnect-vpn status
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

## Security Notes

- Do not commit local config files, cookies, logs, browser profiles, or Keychain
  exports.
- Use a private fork if your defaults reveal internal hostnames.
- Review `config.env` before enabling automatic reconnect.
