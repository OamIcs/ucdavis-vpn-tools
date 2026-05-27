#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
LABEL="local.ucdavis-openconnect-daemon"
LEGACY_LABELS=(com.weyl.ucdavis-openconnect-daemon)
PLIST_TEMPLATE="$ROOT_DIR/local.ucdavis-openconnect-daemon.plist"
INSTALL_BIN="/usr/local/sbin/ucdavis-vpn-root-daemon"
INSTALL_CTL="/usr/local/bin/ucdavis-vpnctl"
INSTALL_DIR="/Library/Application Support/ucdavis-vpn-daemon"
CONFIG_FILE="$INSTALL_DIR/config.env"
PLIST_FILE="/Library/LaunchDaemons/$LABEL.plist"
LOG_DIR="/var/log/ucdavis-openconnect-daemon"
DB_DIR="/var/db/ucdavis-openconnect-daemon"
STATE_DIR="/var/run/ucdavis-openconnect-daemon"
START_AFTER_INSTALL="${START_AFTER_INSTALL:-0}"

if [[ "$(id -u)" != "0" ]]; then
  print -u2 "Run with sudo:"
  print -u2 "  sudo \"$ROOT_DIR/install.sh\""
  exit 1
fi

shell_escape_sed() {
  printf '%s' "$1" | /usr/bin/sed 's/[\/&]/\\&/g'
}

ensure_config_default() {
  local key="$1"
  local value="$2"
  if ! /usr/bin/grep -q "^${key}=" "$CONFIG_FILE"; then
    print "${key}=${value}" >> "$CONFIG_FILE"
    print "Added default config: $key=$value"
  fi
}

remove_legacy_launchdaemons() {
  local legacy_label legacy_plist
  for legacy_label in "${LEGACY_LABELS[@]}"; do
    legacy_plist="/Library/LaunchDaemons/$legacy_label.plist"
    /bin/launchctl bootout "system/$legacy_label" >/dev/null 2>&1 || true
    if [[ -f "$legacy_plist" ]]; then
      /bin/launchctl bootout system "$legacy_plist" >/dev/null 2>&1 || true
      rm -f "$legacy_plist"
      print "Removed legacy LaunchDaemon: $legacy_plist"
    fi
  done
}

console_user="${SUDO_USER:-$(/usr/bin/stat -f %Su /dev/console 2>/dev/null)}"
[[ "$console_user" == "root" || -z "$console_user" ]] && console_user="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null)"
console_uid="$(/usr/bin/id -u "$console_user")"
console_home="$(/usr/bin/dscl . -read "/Users/$console_user" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
project_root="${ROOT_DIR:h}"

mkdir -p /usr/local/sbin /usr/local/bin "$INSTALL_DIR" "$LOG_DIR" "$DB_DIR" "$STATE_DIR"
remove_legacy_launchdaemons

if [[ ! -f "$PLIST_TEMPLATE" ]]; then
  print -u2 "Missing plist template: $PLIST_TEMPLATE"
  exit 1
fi

install -m 0755 "$ROOT_DIR/bin/ucdavis-vpn-root-daemon" "$INSTALL_BIN"
install -m 0755 "$ROOT_DIR/bin/ucdavis-vpnctl" "$INSTALL_CTL"

if [[ -f "$CONFIG_FILE" ]]; then
  backup="$CONFIG_FILE.backup.$(/bin/date +%Y%m%d-%H%M%S)"
  cp "$CONFIG_FILE" "$backup"
  print "Backed up existing config to $backup"
  if /usr/bin/grep -q '^LABEL=com\.weyl\.ucdavis-openconnect-daemon$' "$CONFIG_FILE"; then
    /usr/bin/sed -i '' 's/^LABEL=com\.weyl\.ucdavis-openconnect-daemon$/LABEL=local.ucdavis-openconnect-daemon/' "$CONFIG_FILE"
    print "Updated legacy LABEL in existing config."
  fi
else
  /usr/bin/sed \
    -e "s/__USER_NAME__/$(shell_escape_sed "$console_user")/g" \
    -e "s/__USER_UID__/$(shell_escape_sed "$console_uid")/g" \
    -e "s#__USER_HOME__#$(shell_escape_sed "$console_home")#g" \
    -e "s#__PROJECT_ROOT__#$(shell_escape_sed "$project_root")#g" \
    "$ROOT_DIR/config.env.example" > "$CONFIG_FILE"
  chmod 0644 "$CONFIG_FILE"
fi

ensure_config_default GUI_SESSION_WAIT_SECONDS 0
ensure_config_default GUI_SESSION_POLL_SECONDS 1
ensure_config_default MAX_BROWSER_SESSION_ATTEMPTS 2
ensure_config_default CONTROL_POLL_SECONDS 1
ensure_config_default PRESERVE_DEFAULT_ROUTE 1
ensure_config_default DEFAULT_ROUTE_RESTORE_DELAY_SECONDS 2
ensure_config_default SSH_CONFIG_TIMEOUT_SECONDS 5
ensure_config_default CLOSE_EXISTING_VPN_SESSIONS 1
if /usr/bin/grep -q '^MAX_BROWSER_SESSION_ATTEMPTS=3$' "$CONFIG_FILE"; then
  /usr/bin/sed -i '' 's/^MAX_BROWSER_SESSION_ATTEMPTS=3$/MAX_BROWSER_SESSION_ATTEMPTS=2/' "$CONFIG_FILE"
  print "Updated default config: MAX_BROWSER_SESSION_ATTEMPTS=2"
fi

install -m 0644 "$PLIST_TEMPLATE" "$PLIST_FILE"
chown root:wheel "$INSTALL_BIN" "$INSTALL_CTL" "$PLIST_FILE"
chmod 0755 "$INSTALL_BIN"
chmod 0755 "$INSTALL_CTL"
chmod 0644 "$PLIST_FILE"

/usr/bin/plutil -lint "$PLIST_FILE"

print "Installed:"
print "  $INSTALL_BIN"
print "  $INSTALL_CTL"
print "  $CONFIG_FILE"
print "  $PLIST_FILE"

if [[ "$START_AFTER_INSTALL" == "1" ]]; then
  /bin/launchctl bootout system "$PLIST_FILE" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap system "$PLIST_FILE"
  print "Started $LABEL"
else
  print "Not started. To enable now:"
  print "  sudo launchctl bootstrap system \"$PLIST_FILE\""
fi
