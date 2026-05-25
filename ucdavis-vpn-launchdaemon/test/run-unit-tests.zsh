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

status_output="$("$ROOT_DIR/bin/ucdavis-vpnctl" --config "$CONFIG_FILE" status)"
print -r -- "$status_output" | /usr/bin/grep -q "Browser tries:" || fail "ctl status should include browser budget"
print -r -- "$status_output" | /usr/bin/grep -q "Auto:" || fail "ctl status should include auto state"

print "ok"
