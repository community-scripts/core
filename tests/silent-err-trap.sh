#!/usr/bin/env bash
# silent() re-armed `trap error_handler ERR` after every call. A script run
# through pct exec has no error_handler, so add-tailscale-lxc and
# add-netbird-lxc ended with exit 127 instead of apt's error.
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SILENT="$(awk '/^(silent|_cs_shield_hangup|_cs_reattach_output)[(][)] [{]/,/^}/' "$CORE_DIR/core/core.func")"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export SILENT LOG="$TEST_DIR/install.log"
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
run() {
  bash -c 'eval "$SILENT"; get_active_logfile() { echo "$LOG"; }; '"$1" 2>&1
  echo "rc=$?"
}

out="$(run 'set -e; silent true; f() { return 100; }; f')"
expect "without error_handler the failure keeps its own code" "rc=100" "$(tail -n1 <<<"$out")"
expect "and nothing calls a missing error_handler" 0 "$(grep -c 'error_handler' <<<"$out")"

out="$(run 'set -eE; trap "echo MINE; exit 9" ERR; silent true; false')"
expect "the caller's own ERR trap survives" "MINE rc=9" "$(echo $out)"

out="$(run 'error_handler() { echo HANDLED; exit 8; }; set -e; trap error_handler ERR; silent true; false')"
expect "error_handler is still armed when the trap is not visible" "HANDLED rc=8" "$(echo $out)"

out="$(run 'set -e; silent sh -c "exit 3" || echo "caught $?"')"
expect "a handled failure stays handled" "caught 3 rc=0" "$(echo $out)"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
