#!/bin/zsh
set -euo pipefail

LABEL="local.ucdavis-openconnect-daemon"
LEGACY_LABELS=(com.weyl.ucdavis-openconnect-daemon)
INSTALL_BIN="/usr/local/sbin/ucdavis-vpn-root-daemon"
INSTALL_CTL="/usr/local/bin/ucdavis-vpnctl"
PLIST_FILE="/Library/LaunchDaemons/$LABEL.plist"

if [[ "$(id -u)" != "0" ]]; then
  print -u2 "Run with sudo:"
  print -u2 "  sudo \"$0\""
  exit 1
fi

/bin/launchctl bootout system "$PLIST_FILE" >/dev/null 2>&1 || true
rm -f "$PLIST_FILE"

for legacy_label in "${LEGACY_LABELS[@]}"; do
  legacy_plist="/Library/LaunchDaemons/$legacy_label.plist"
  /bin/launchctl bootout "system/$legacy_label" >/dev/null 2>&1 || true
  [[ -f "$legacy_plist" ]] && /bin/launchctl bootout system "$legacy_plist" >/dev/null 2>&1 || true
  rm -f "$legacy_plist"
done

rm -f "$INSTALL_BIN" "$INSTALL_CTL"

print "Removed LaunchDaemon and binary."
print "Left config/log/state directories in place:"
print "  /Library/Application Support/ucdavis-vpn-daemon"
print "  /var/log/ucdavis-openconnect-daemon"
print "  /var/db/ucdavis-openconnect-daemon"
