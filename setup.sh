#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
USER_CONFIG_DIR="$HOME/.config/ucdavis-openconnect-vpn"
USER_CONFIG_FILE="$USER_CONFIG_DIR/config.env"
USER_CONFIG_EXAMPLE="$ROOT_DIR/ucdavis-openconnect-vpn/config.env.example"
DAEMON_DIR="$ROOT_DIR/ucdavis-vpn-launchdaemon"
DAEMON_CONFIG="/Library/Application Support/ucdavis-vpn-daemon/config.env"
DAEMON_PLIST="/Library/LaunchDaemons/local.ucdavis-openconnect-daemon.plist"
DAEMON_LABEL="local.ucdavis-openconnect-daemon"
KEYCHAIN_SERVICE="ucdavis-openconnect-vpn"

if [[ "$(id -u)" == "0" ]]; then
  print -u2 "Run setup as your normal macOS user, not with sudo."
  print -u2 "The script will ask for sudo only when installing the LaunchDaemon."
  exit 1
fi

usage() {
  cat <<EOF
Usage: ./setup.sh

Guided first-time setup for the UC Davis OpenConnect VPN tools.
It creates the user config, installs the root LaunchDaemon, stores the password
in macOS Keychain, and can start the daemon immediately.
EOF
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local answer suffix
  if [[ "$default" == "y" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi
  read -r "answer?$prompt $suffix "
  answer="${answer:l}"
  if [[ -z "$answer" ]]; then
    [[ "$default" == "y" ]]
  else
    [[ "$answer" == "y" || "$answer" == "yes" ]]
  fi
}

read_with_default() {
  local var_name="$1"
  local prompt="$2"
  local default="${3:-}"
  local answer
  if [[ -n "$default" ]]; then
    read -r "answer?$prompt [$default]: "
    answer="${answer:-$default}"
  else
    read -r "answer?$prompt: "
  fi
  typeset -g "$var_name=$answer"
}

existing_config_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  /usr/bin/awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$file" |
    /usr/bin/sed -e 's/^"//' -e 's/"$//'
}

quote_config_value() {
  local value="$1"
  if [[ -z "$value" ]]; then
    print '""'
    return 0
  fi
  if [[ "$value" == *[[:space:]\"\\\$\\\`]* ]]; then
    local escaped="$value"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//\$/\\$}"
    escaped="${escaped//\`/\\\`}"
    print -r -- "\"$escaped\""
  else
    print -r -- "$value"
  fi
}

set_config_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local encoded tmp
  encoded="$(quote_config_value "$value")"
  tmp="$file.tmp.$$"
  if [[ -f "$file" ]]; then
    /usr/bin/awk -v key="$key" -v line="$key=$encoded" '
      BEGIN { done=0 }
      $0 ~ "^" key "=" {
        if (!done) print line
        done=1
        next
      }
      { print }
      END {
        if (!done) print line
      }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    print -r -- "$key=$encoded" > "$file"
  fi
}

ensure_user_config() {
  mkdir -p "$USER_CONFIG_DIR"
  if [[ ! -f "$USER_CONFIG_FILE" ]]; then
    cp "$USER_CONFIG_EXAMPLE" "$USER_CONFIG_FILE"
    print "Created user config: $USER_CONFIG_FILE"
  else
    print "Updating existing user config: $USER_CONFIG_FILE"
  fi
}

store_keychain_password() {
  local email="$1"
  local password
  print
  print "Store/update the VPN password in macOS Keychain."
  read -rs "password?UC Davis VPN password for $email (leave blank to skip): "
  print
  if [[ -z "$password" ]]; then
    print "Skipped Keychain password update."
    return 0
  fi
  /usr/bin/security add-generic-password \
    -a "$email" \
    -s "$KEYCHAIN_SERVICE" \
    -l "UC Davis VPN password" \
    -T /usr/bin/security \
    -U \
    -w "$password"
  unset password
  print "Keychain: OK ($KEYCHAIN_SERVICE / $email)"
}

install_missing_dependencies() {
  local missing=()
  command -v openconnect >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/openconnect || -x /usr/local/bin/openconnect ]] || missing+=(openconnect)
  command -v node >/dev/null 2>&1 || [[ -x /opt/homebrew/bin/node || -x /usr/local/bin/node || -x /Applications/Codex.app/Contents/Resources/node ]] || missing+=(node)
  (( ${#missing[@]} == 0 )) && return 0

  print "Missing dependencies: ${missing[*]}"
  if ! command -v brew >/dev/null 2>&1; then
    print -u2 "Homebrew was not found. Install ${missing[*]} first, then rerun setup."
    return 1
  fi
  if yes_no "Install missing dependencies with Homebrew now?" y; then
    brew install "${missing[@]}"
  else
    print -u2 "Install ${missing[*]} first, then rerun setup."
    return 1
  fi
}

apply_common_config() {
  local file="$1"
  set_config_value "$file" UC_DAVIS_EMAIL "$SETUP_EMAIL"
  set_config_value "$file" KEYCHAIN_SERVICE "$KEYCHAIN_SERVICE"
  set_config_value "$file" HEALTH_CHECK_MODE "$SETUP_HEALTH_MODE"
  set_config_value "$file" HEALTH_MIN_SUCCESS "$SETUP_HEALTH_MIN_SUCCESS"
  set_config_value "$file" PING_TARGET "$SETUP_PING_TARGET"
  set_config_value "$file" PING_TARGETS "$SETUP_PING_TARGETS"
  set_config_value "$file" TCP_TARGET "$SETUP_TCP_TARGET"
  set_config_value "$file" TCP_TARGETS "$SETUP_TCP_TARGETS"
  set_config_value "$file" TCP_PORT "$SETUP_TCP_PORT"
}

configure_daemon_config() {
  local tmp
  tmp="$(mktemp)"
  cp "$DAEMON_CONFIG" "$tmp"
  apply_common_config "$tmp"
  sudo cp "$tmp" "$DAEMON_CONFIG"
  sudo chmod 0644 "$DAEMON_CONFIG"
  rm -f "$tmp"
  print "Updated daemon config: $DAEMON_CONFIG"
}

print
print "UC Davis OpenConnect VPN guided setup"
print
print "This will:"
print "  1. create/update the user config"
print "  2. install the root LaunchDaemon"
print "  3. store the VPN password in macOS Keychain"
print "  4. optionally start automatic reconnect now"
print

install_missing_dependencies

existing_email="$(existing_config_value "$USER_CONFIG_FILE" UC_DAVIS_EMAIL 2>/dev/null || true)"
[[ "$existing_email" == "your_email@ucdavis.edu" ]] && existing_email=""
read_with_default SETUP_EMAIL "UC Davis email" "$existing_email"
if [[ -z "$SETUP_EMAIL" || "$SETUP_EMAIL" != *@* ]]; then
  print -u2 "A valid UC Davis email is required."
  exit 1
fi

print
print "Health check:"
print "  tunnel  easiest; checks OpenConnect and the macOS utun VPN address"
print "  tcp     checks one or more internal service ports, e.g. host-a:22 host-b:443"
print "  ping    checks one or more internal hosts with ICMP ping"
print
read_with_default SETUP_HEALTH_MODE "Health check mode" "tunnel"
SETUP_HEALTH_MODE="${SETUP_HEALTH_MODE:l}"

SETUP_HEALTH_MIN_SUCCESS=1
SETUP_PING_TARGET=""
SETUP_PING_TARGETS=""
SETUP_TCP_TARGET=""
SETUP_TCP_TARGETS=""
SETUP_TCP_PORT=22

case "$SETUP_HEALTH_MODE" in
  tunnel)
    ;;
  tcp)
    read_with_default SETUP_TCP_TARGETS "TCP targets, space-separated host:port values" ""
    if [[ -z "$SETUP_TCP_TARGETS" ]]; then
      print "No TCP targets entered; falling back to tunnel health check."
      SETUP_HEALTH_MODE=tunnel
    else
      read_with_default SETUP_HEALTH_MIN_SUCCESS "Minimum TCP targets that must pass" "1"
    fi
    ;;
  ping)
    read_with_default SETUP_PING_TARGETS "Ping targets, space-separated internal hosts/IPs" ""
    if [[ -z "$SETUP_PING_TARGETS" ]]; then
      print "No ping targets entered; falling back to tunnel health check."
      SETUP_HEALTH_MODE=tunnel
    else
      read_with_default SETUP_HEALTH_MIN_SUCCESS "Minimum ping targets that must pass" "1"
    fi
    ;;
  *)
    print "Unknown health mode '$SETUP_HEALTH_MODE'; using tunnel."
    SETUP_HEALTH_MODE=tunnel
    ;;
esac
[[ "$SETUP_HEALTH_MIN_SUCCESS" == <-> ]] || SETUP_HEALTH_MIN_SUCCESS=1
(( SETUP_HEALTH_MIN_SUCCESS > 0 )) || SETUP_HEALTH_MIN_SUCCESS=1

ensure_user_config
apply_common_config "$USER_CONFIG_FILE"
print "Updated user config: $USER_CONFIG_FILE"

store_keychain_password "$SETUP_EMAIL"

print
print "Installing root LaunchDaemon files. macOS may ask for your password."
sudo "$DAEMON_DIR/install.sh"
configure_daemon_config

if yes_no "Start the LaunchDaemon and connect automatically now?" y; then
  sudo launchctl bootout system "$DAEMON_PLIST" >/dev/null 2>&1 || true
  sudo launchctl bootstrap system "$DAEMON_PLIST"
  sudo launchctl kickstart -k "system/$DAEMON_LABEL" >/dev/null 2>&1 || true
  print "Started $DAEMON_LABEL."
  print
  print "Status:"
  ucdavis-vpnctl status || true
else
  print
  print "Installed but not started. Start later with:"
  print "  sudo launchctl bootstrap system \"$DAEMON_PLIST\""
  print "  ucdavis-vpnctl on"
fi

print
print "Common commands:"
print "  ucdavis-vpnctl status        # show daemon, tunnel, health check, and cookie state"
print "  ucdavis-vpnctl connect       # connect or reconnect now"
print "  ucdavis-vpnctl disconnect    # drop the current tunnel; auto reconnect stays enabled"
print "  ucdavis-vpnctl off           # pause auto reconnect and log out the tunnel"
print "  ucdavis-vpnctl on            # resume auto reconnect and connect now"
print "  ucdavis-vpnctl set-password  # update the Keychain password"
print
print "Advanced settings live in:"
print "  $USER_CONFIG_FILE"
print "  $DAEMON_CONFIG"
