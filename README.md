# UC Davis OpenConnect VPN Tools

Command-line tools for connecting to a UC Davis Engineering VPN gateway with
OpenConnect on macOS.

This project is useful when you want to use OpenConnect as the local VPN client
instead of the Ivanti desktop app. UC Davis SSO, MFA, and the VPN gateway are
still used normally.

## Features

- Manual connect/disconnect commands for day-to-day use.
- Chrome-based UC Davis login and MFA flow.
- OpenConnect tunnel startup with status and reachability checks.
- Optional root LaunchDaemon for always-on reconnect.
- Local config, logs, and state kept outside the repository.

## Quick Start

Install dependencies:

```zsh
brew install openconnect
```

Configure the user-level tool:

```zsh
cd ucdavis-openconnect-vpn
mkdir -p ~/.config/ucdavis-openconnect-vpn
cp config.env.example ~/.config/ucdavis-openconnect-vpn/config.env
```

Edit the config:

```zsh
~/.config/ucdavis-openconnect-vpn/config.env
```

At minimum, set:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
```

Store your VPN password in macOS Keychain. See
[ucdavis-openconnect-vpn/README.md](ucdavis-openconnect-vpn/README.md) for the
exact command.

Check the setup:

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

## Repository Structure

```text
ucdavis-vpn-tools/
+-- ucdavis-openconnect-vpn/
|   +-- User-level command-line wrapper
|   +-- Chrome/CDP cookie helper
|   +-- Best starting point for manual use
|
+-- ucdavis-vpn-launchdaemon/
|   +-- Root LaunchDaemon wrapper
|   +-- Connectivity monitor
|   +-- Optional always-on reconnect layer
|
+-- docs/
    +-- overview.md
    +-- commands.md
```

## Which Tool Should I Use?

Start with `ucdavis-openconnect-vpn/`. It is the manual user-level tool and is
the easiest way to verify that login, cookies, OpenConnect, routes, and DNS all
work on your machine.

| Subproject | Runs as | Job |
| --- | --- | --- |
| `ucdavis-openconnect-vpn/` | Normal user, with sudo for OpenConnect | Open Chrome, get the VPN cookie, start/stop OpenConnect manually |
| `ucdavis-vpn-launchdaemon/` | root LaunchDaemon | Keep the VPN up in the background and reconnect when reachability fails |

Only after manual connection works reliably should you consider the
LaunchDaemon:

```zsh
cd ../ucdavis-vpn-launchdaemon
sudo ./install.sh
```

## Documentation

- [ucdavis-openconnect-vpn/README.md](ucdavis-openconnect-vpn/README.md):
  setup and usage for the manual user tool.
- [ucdavis-vpn-launchdaemon/README.md](ucdavis-vpn-launchdaemon/README.md):
  setup and usage for the optional root daemon.
- [docs/overview.md](docs/overview.md): architecture, workflow, and the
  Ivanti/OpenConnect relationship.
- [docs/commands.md](docs/commands.md): every command and when to use it.

## Requirements

- macOS
- Homebrew `openconnect`
- Node.js
- Google Chrome
- UC Davis VPN account and MFA
- macOS Keychain item for the VPN password

Install OpenConnect:

```zsh
brew install openconnect
```

## Security

This repository should not contain:

- VPN passwords
- Keychain exports
- Browser profiles
- VPN cookies
- Logs, pid files, or local config files

Passwords are read from macOS Keychain at runtime.

Before sharing or publishing your fork, check for secrets and local paths:

```zsh
git status --short
rg -n 'your[_]email|g[h]p_|D[S]ID|D[S]SIGNIN|/User[s]/[^ ]+' .
```
