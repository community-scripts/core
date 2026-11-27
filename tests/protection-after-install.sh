#!/usr/bin/env bash
# var_protection went to pct create, so pct destroy refused every "Remove
# container" after a failed install while the menu reported it removed, and a
# retry found the old ID still taken.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

body="$(awk '/^build_container[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"
expect "pct create gets no protection" 0 "$(grep -c -- '-protection 1' <<<"$body")"
last_exit="$(grep -n 'exit \$install_exit_code' <<<"$body" | tail -n 1 | cut -d: -f1)"
protect="$(grep -n '^  _pve_protect_ct$' <<<"$body" | cut -d: -f1)"
expect "it is set once, after the failure handling" 1 "$((protect > last_exit))"
expect "and after a successful APT repair" 1 "$(grep -A1 'post_update_to_api "done" "0" "force"' <<<"$body" | grep -c '_pve_protect_ct')"

eval "$(awk '/^_pve_protect_ct[(][)] [{]/,/^}/' "$CORE_DIR/pve/backend.func")"
CTID=303 BUILD_LOG=/dev/null SET_RC=0
pct() { echo "pct $*" >>"$TEST_DIR/calls"; return "$SET_RC"; }
msg_warn() { echo "warn" >>"$TEST_DIR/calls"; }

: >"$TEST_DIR/calls"; PROTECT_CT=yes _pve_protect_ct
expect "var_protection=yes protects the finished container" "pct set 303 --protection 1" "$(cat "$TEST_DIR/calls")"
: >"$TEST_DIR/calls"; PROTECT_CT=no _pve_protect_ct
expect "without it nothing is set" "" "$(cat "$TEST_DIR/calls")"
: >"$TEST_DIR/calls"; PROTECT_CT=1 SET_RC=1 _pve_protect_ct
expect "a refused pct set only warns" "0 pct set 303 --protection 1|warn" "$? $(paste -sd'|' "$TEST_DIR/calls")"

echo "passed=${passed} failed=${failed}"
((failed == 0))
