# UC Davis OpenConnect VPN Tools

macOS command-line tools for connecting to the UC Davis Engineering VPN with
OpenConnect.

This is a local-client replacement for the Ivanti desktop app, not a replacement
for UC Davis SSO, MFA, or the VPN gateway. The UC Davis/Ivanti login flow is
still used; OpenConnect creates the tunnel.

## Mental Model

```text
Chrome login -> VPN cookie -> OpenConnect tunnel -> UC Davis internal network
```

The repository has two parts:

- `ucdavis-openconnect-vpn/`: manual user-level tool. Start here.
- `ucdavis-vpn-launchdaemon/`: optional root LaunchDaemon for auto-reconnect.

Use the manual tool first. Install the daemon only after manual connect/status
works reliably.

## Quick Start

Install dependencies:

```zsh
brew install openconnect
```

Configure the manual tool:

```zsh
cd ucdavis-openconnect-vpn
mkdir -p ~/.config/ucdavis-openconnect-vpn
cp config.env.example ~/.config/ucdavis-openconnect-vpn/config.env
```

Edit `~/.config/ucdavis-openconnect-vpn/config.env` and set:

```zsh
UC_DAVIS_EMAIL=your_email@ucdavis.edu
```

Store the VPN password in Keychain; see
[ucdavis-openconnect-vpn/README.md](ucdavis-openconnect-vpn/README.md).

Connect:

```zsh
bin/ucdavis-openconnect-vpn doctor
bin/ucdavis-openconnect-vpn connect
bin/ucdavis-openconnect-vpn status
```

Disconnect:

```zsh
bin/ucdavis-openconnect-vpn disconnect
```

## Optional Daemon

After manual connection works:

```zsh
cd ../ucdavis-vpn-launchdaemon
sudo ./install.sh
```

The daemon runs OpenConnect as root and monitors a configured internal target.
It still runs browser login as the normal GUI user.

## Notes

- This tool is for UC Davis VPN/internal resources. It is not a general-purpose
  public Internet proxy.
- Avoid combining it with other VPNs or proxies (like Clash or ShadowRocket).
- Do not commit passwords, cookies, browser profiles, logs, pid files, or local
  config files.

## Documentation

- [ucdavis-openconnect-vpn/README.md](ucdavis-openconnect-vpn/README.md):
  manual tool setup and use.
- [ucdavis-vpn-launchdaemon/README.md](ucdavis-vpn-launchdaemon/README.md):
  optional daemon setup and use.
- [docs/overview.md](docs/overview.md): architecture and detailed workflow.
- [docs/commands.md](docs/commands.md): command reference.
