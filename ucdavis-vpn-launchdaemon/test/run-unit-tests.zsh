#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$expected" == "$actual" ]] || fail "$label: expected '$expected', got '$actual'"
}

CONFIG_FILE="$TMP_DIR/config.env"
cat > "$CONFIG_FILE" <<EOF
LABEL=local.ucdavis-openconnect-daemon-test
USER_NAME=${USER}
USER_UID=$(id -u)
USER_HOME=${HOME}
SERVER=vpn.engineering.ucdavis.edu
UC_DAVIS_EMAIL=test@example.edu
KEYCHAIN_SERVICE=ucdavis-openconnect-vpn-test
SSH_HOST_ALIAS=
PING_TARGET=127.0.0.1
PING_COUNT=1
PING_TIMEOUT_MS=200
CHECK_INTERVAL_SECONDS=1
FAILURE_THRESHOLD=1
RECONNECT_COOLDOWN_SECONDS=1
GUI_SESSION_WAIT_SECONDS=1
GUI_SESSION_POLL_SECONDS=1
MAX_BROWSER_SESSION_ATTEMPTS=2
CONTROL_POLL_SECONDS=1
PRESERVE_DEFAULT_ROUTE=1
DEFAULT_ROUTE_RESTORE_DELAY_SECONDS=0
NETWORK_CHANGE_DETECT=1
NETWORK_CHANGE_SETTLE_SECONDS=0
NETWORK_CHANGE_BYPASS_COOLDOWN=1
AUTO_RECONNECT=1
CONNECT_ON_START=0
STATE_DIR=$TMP_DIR/state
DB_DIR=$TMP_DIR/db
LOG_DIR=$TMP_DIR/log
NODE_BIN=/usr/bin/false
COOKIE_HELPER=$TMP_DIR/missing-cookie-helper.mjs
OPENCONNECT_BIN=/usr/bin/false
VPNC_SCRIPT=/usr/bin/false
ROOT_DAEMON_BIN="$ROOT_DIR/bin/ucdavis-vpn-root-daemon"
EOF

set -- --config "$CONFIG_FILE"
UC_DAVIS_VPN_DAEMON_SOURCE_ONLY=1 source "$ROOT_DIR/bin/ucdavis-vpn-root-daemon"

mkdir -p "$STATE_DIR" "$DB_DIR" "$LOG_DIR"

log_stdout="$(log "unit log should not contaminate stdout" 2>/dev/null || true)"
assert_eq "" "$log_stdout" "log stdout"

assert_eq "0/2" "$(browser_session_budget_status)" "initial browser budget"
record_browser_session_attempt "unit one" >/dev/null
assert_eq "1/2" "$(browser_session_budget_status)" "first browser attempt"
record_browser_session_attempt "unit two" >/dev/null
block_browser_session_attempts_if_exhausted "unit exhausted" >/dev/null 2>&1 && fail "budget should be blocked"
browser_session_blocked || fail "block file should exist"
reset_browser_session_attempts "unit reset" >/dev/null
assert_eq "0/2" "$(browser_session_budget_status)" "reset browser budget"

set_auto_reconnect_paused "unit pause" >/dev/null
auto_reconnect_paused || fail "auto reconnect should be paused"
clear_auto_reconnect_paused "unit resume" >/dev/null
auto_reconnect_paused && fail "auto reconnect should be resumed"

is_tunnel_iface utun6 || fail "utun should be treated as a tunnel interface"
is_tunnel_iface en0 && fail "en0 should be treated as a physical interface"
remember_physical_default_route "192.0.2.1|en0" >/dev/null
assert_eq "192.0.2.1|en0" "$(saved_physical_default_route_info)" "saved physical route"
if remember_physical_default_route "172.25.228.1|utun6" >/dev/null 2>&1; then
  fail "tunnel default route should not be saved as physical"
fi
assert_eq "192.0.2.1|en0" "$(saved_physical_default_route_info)" "tunnel route should not replace saved physical route"

initialize_network_signature
[[ -f "$NETWORK_SIGNATURE_FILE" ]] || fail "network signature file should be initialized"
print -r -- "old-gateway|en0|ssid=old" > "$NETWORK_SIGNATURE_FILE"
detect_network_change >/dev/null 2>&1 || fail "network signature change should be detected"
[[ -f "$NETWORK_CHANGE_PENDING_FILE" ]] || fail "network change should create a pending marker"
network_change_summary="$(consume_network_change_pending)"
[[ "$network_change_summary" == old-gateway* ]] || fail "network change summary should mention old signature"

status_output="$("$ROOT_DIR/bin/ucdavis-vpnctl" --config "$CONFIG_FILE" status)"
print -r -- "$status_output" | /usr/bin/grep -q "Browser tries:" || fail "ctl status should include browser budget"
print -r -- "$status_output" | /usr/bin/grep -q "Auto:" || fail "ctl status should include auto state"
print -r -- "$status_output" | /usr/bin/grep -q "Default route:" || fail "ctl status should include default route"

print "ok"
