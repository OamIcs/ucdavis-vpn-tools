# UC Davis OpenConnect VPN Tools Overview

This repository contains macOS tools for connecting to a UC Davis Engineering
VPN gateway with OpenConnect.

The server-side VPN system is still UC Davis / Ivanti / Pulse / Juniper. The
local tunnel client is OpenConnect, not the Ivanti desktop client.

For command-by-command usage, see [commands.md](commands.md).

## What This Replaces

These tools can replace the local Ivanti VPN desktop client for this gateway if
the server accepts Juniper Network Connect sessions.

They do not replace:

- The UC Davis VPN gateway
- The Ivanti web login flow
- UC Davis SSO or MFA
- Server-side VPN policy

They replace only the local tunnel client:

```text
Ivanti desktop app  ->  OpenConnect
```

## Core Idea

The VPN gateway accepts a browser-authenticated session cookie. This repository
uses Chrome to obtain that cookie, then gives it to OpenConnect.

```text
Browser authentication             VPN tunnel
----------------------             ----------
Chrome + UC Davis SSO/MFA   --->   OpenConnect --protocol=nc
Ivanti web cookie                  utun interface, routes, DNS
```

The important OpenConnect invocation is:

```zsh
openconnect --protocol=nc --cookie-on-stdin vpn.engineering.ucdavis.edu
```

`--protocol=nc` means Juniper Network Connect protocol.

## Project Layout

```text
ucdavis-vpn-tools/
+-- ucdavis-openconnect-vpn/
|   +-- bin/ucdavis-openconnect-vpn
|   +-- bin/ucdavis-vpn-cookie.mjs
|   +-- config.env.example
|
+-- ucdavis-vpn-launchdaemon/
|   +-- bin/ucdavis-vpn-root-daemon
|   +-- install.sh
|   +-- uninstall.sh
|   +-- local.ucdavis-openconnect-daemon.plist
|   +-- config.env.example
|
+-- docs/
    +-- overview.md
    +-- commands.md
```

## Why There Are Two Projects

The two projects separate browser authentication from long-running system
networking.

| Project | Runs as | Purpose | Best for |
| --- | --- | --- | --- |
| `ucdavis-openconnect-vpn` | Normal user, with sudo for OpenConnect | Manual connect/disconnect and debugging | Occasional VPN use |
| `ucdavis-vpn-launchdaemon` | root LaunchDaemon | Background monitoring and reconnect | Always-on VPN |

Chrome login must run in the normal user's GUI session. OpenConnect needs
privileges to create `utun` interfaces and modify routes/DNS. The split keeps
those responsibilities explicit.

## Manual Workflow

Use this flow when running `ucdavis-openconnect-vpn` directly from a shell.

```text
1. User runs:
      bin/ucdavis-openconnect-vpn connect

2. The wrapper reads:
      ~/.config/ucdavis-openconnect-vpn/config.env

3. The cookie helper runs as the current user:
      bin/ucdavis-vpn-cookie.mjs

4. The helper starts or reuses a dedicated Chrome profile:
      ~/.local/state/ucdavis-vpn-chrome-profile

5. Chrome opens the UC Davis VPN SAML login page.

6. The helper submits the configured email and Keychain password when possible.
   MFA still happens through the normal browser flow.

7. The helper reads VPN cookies from Chrome, including DSID when login succeeds.

8. The wrapper starts OpenConnect with the cookie:
      sudo nohup openconnect --protocol=nc --cookie-on-stdin ...

9. OpenConnect creates the VPN tunnel:
      utun interface
      VPN-assigned IP
      routes and DNS through vpnc-script

10. The wrapper verifies reachability with PING_TARGET or SSH_HOST_ALIAS.
```

Result:

```text
Chrome handles login.
OpenConnect handles the tunnel.
The Ivanti desktop client is not used.
```

## Daemon Workflow

Use this flow after installing `ucdavis-vpn-launchdaemon`.

```text
1. launchd starts:
      /usr/local/sbin/ucdavis-vpn-root-daemon run

2. The root daemon reads:
      /Library/Application Support/ucdavis-vpn-daemon/config.env

3. The daemon checks whether the internal target is reachable.

4. If the target is reachable, it waits for the next check interval.

5. If the target is not reachable, the daemon asks the user's GUI session to
   run the cookie helper:
      launchctl asuser <uid> sudo -u <user> node ucdavis-vpn-cookie.mjs

6. The helper uses the user's Chrome profile and Keychain access to obtain the
   VPN cookie.

7. The root daemon starts OpenConnect directly:
      openconnect --protocol=nc --cookie-on-stdin ...

8. The daemon keeps checking reachability.

9. If checks fail enough times, it disconnects the tracked tunnel and retries
   after the configured cooldown.
```

Result:

```text
The daemon runs OpenConnect as root.
The browser login still runs as the normal user.
The VPN can reconnect without repeated sudo prompts.
```

## State And Logs

User tool:

```text
~/.config/ucdavis-openconnect-vpn/config.env
~/.local/state/ucdavis-vpn-chrome-profile
~/.local/state/ucdavis-openconnect-vpn/
~/Library/Logs/ucdavis-openconnect-vpn/
```

LaunchDaemon:

```text
/Library/Application Support/ucdavis-vpn-daemon/config.env
/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist
/var/run/ucdavis-openconnect-daemon/
/var/db/ucdavis-openconnect-daemon/
/var/log/ucdavis-openconnect-daemon/
```

## Which Mode To Use

Use `ucdavis-openconnect-vpn` if:

- You connect only when needed
- You want the simplest setup
- You are debugging login, cookies, or OpenConnect arguments

Use `ucdavis-vpn-launchdaemon` if:

- You want VPN auto-connect on startup
- You want automatic reconnect
- You want OpenConnect to run as root without repeated sudo prompts

## Compatibility With Other Proxy Software

OpenConnect and proxy/VPN tools such as Clash can conflict when both try to
control routing, DNS, or TUN interfaces.

Known problematic combinations:

- OpenConnect plus Clash TUN mode
- OpenConnect plus Clash VPN mode
- OpenConnect plus Clash fake-ip DNS mode
- Multiple tools that create `utun` interfaces and install default routes

The symptoms can look confusing:

- UC Davis internal hosts are reachable, but public sites are not.
- Public domains resolve to `198.18.0.x` fake IP addresses.
- Browser behavior differs from `curl`.
- One tool overwrites routes or DNS installed by the other.

Recommended split:

```text
OpenConnect handles:
  UC Davis VPN
  UC Davis internal hosts
  SSH/ping/internal services

Clash handles:
  YouTube, ChatGPT, and other public sites
  HTTP/SOCKS proxy for browsers and command-line tools

Disable:
  Clash TUN/VPN mode
  Clash fake-ip DNS mode when it interferes with system routing
```

For command-line tools, set proxy variables explicitly if needed:

```zsh
export HTTP_PROXY=http://127.0.0.1:7897
export HTTPS_PROXY=http://127.0.0.1:7897
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
```

Use the port configured in your Clash client.

## Assumptions And Limits

This approach depends on the UC Davis VPN gateway accepting OpenConnect Network
Connect sessions. It may stop working if the server policy changes to require
the official Ivanti client.

Do not commit local config files, cookies, logs, browser profiles, pid files, or
Keychain exports.
