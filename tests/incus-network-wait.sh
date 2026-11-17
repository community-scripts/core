#!/usr/bin/env bash
# After the sysctl rollback restarted the container, the first `ip addr show dev
# eth0` failed and pipefail ended the run instead of the loop asking again.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^incus_wait_for_network[(][)] [{]/,/^}/' "$CORE_DIR/incus/backend.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
passed=0 failed=0

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}

msg_info() { :; }
msg_ok() { echo "OK $1" >>"$TEST_DIR/msgs"; }
msg_warn() { echo "WARN $1" >>"$TEST_DIR/msgs"; }
sleep() { :; }
incus() { :; }
incus_instance_field() { return 1; }
# eth0 is missing for the first $MISSING calls, as right after a restart.
incus_ct_exec() {
  local n
  n=$(($(cat "$TEST_DIR/calls" 2>/dev/null || echo 0) + 1))
  echo "$n" >"$TEST_DIR/calls"
  case "$1" in
  ip)
    ((n > MISSING)) || { echo "Device \"eth0\" does not exist." >&2; return 1; }
    [[ "$2" == "-4" ]] && echo "    inet 10.98.0.12/24 brd 10.98.0.255 scope global eth0"
    ;;
  ping) return 0 ;;
  esac
}

run() {
  rm -f "$TEST_DIR/calls" "$TEST_DIR/msgs"
  MISSING="$1" CT_NAME=ci-1 BRG=incusbr0 bash -c '
    set -Eeuo pipefail
    trap "echo ABORTED; exit 99" ERR
    eval "$1"
    incus_wait_for_network
    echo "IP=$IP"' _ "$(declare -f incus_wait_for_network incus_ct_exec incus_instance_field incus msg_info msg_ok msg_warn sleep); TEST_DIR=$TEST_DIR"
}

expect "an address present at once is used" "IP=10.98.0.12" "$(run 0)"
expect "a missing eth0 right after a restart is asked again" "IP=10.98.0.12" "$(run 3)"
expect "and the network is reported reachable" "OK Network reachable (10.98.0.12)" "$(cat "$TEST_DIR/msgs")"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
