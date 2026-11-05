#!/usr/bin/env bash
# Steps around the install that ended finished or still recoverable runs:
# pct set -description failing after a clean install, and a log line that
# could not be written on Incus.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^description[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"
eval "$(awk '/^(incus_log_msg|incus_strip_ansi|get_active_incus_logfile)[(][)] [{]/,/^}/' "$CORE_DIR/incus/core.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
WARN="$TEST_DIR/warn"
passed=0 failed=0

msg_warn() { echo "$*" >>"$WARN"; }
msg_custom() { :; }
post_update_to_api() { echo "$1" >>"$TEST_DIR/posted"; }
pct() {
  case "$1" in
  exec) echo "    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0" ;;
  set)
    echo "unable to open file '/etc/pve/nodes/pve/lxc/100.conf.tmp.1' - Permission denied" >&2
    return 2
    ;;
  esac
}

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

: >"$WARN"
CTID=100 APP=Debian NSAPP=debian
(set -e; trap 'exit 99' ERR; description 2>/dev/null)
expect "a failed pct set does not fail a finished install" 0 "$?"
expect "it says the notes were not written" 1 "$(grep -c 'Could not write the container notes' "$WARN")"
expect "and the run is still reported as done" done "$(cat "$TEST_DIR/posted")"

_INCUS_HOST_LOGFILE="$TEST_DIR/not-a-dir/log"
: >"$TEST_DIR/not-a-dir"
(set -e; trap 'exit 99' ERR; incus_log_msg "hello" 2>/dev/null)
expect "an unwritable Incus log does not end the run" 0 "$?"

_INCUS_HOST_LOGFILE="$TEST_DIR/incus.log"
incus_log_msg $'\e[32mhello\e[0m'
expect "a writable Incus log still gets the line without colors" 1 "$(grep -c '\] hello$' "$TEST_DIR/incus.log")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
