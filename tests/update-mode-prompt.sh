#!/usr/bin/env bash
set -uo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^_cs_ask_update_mode[(][)] [{]/,/^}/' "$CORE_DIR/ui/menu.func")"

passed=0 failed=0
export APP="Demo" YW="" GN="" CL=""
set_std_mode() { STD_MODE_SET="$VERBOSE"; }
_cs_clear() { :; }
exit_script() { echo "cancelled"; exit 0; }

expect() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
# $1 is what the user types; prints the VERBOSE value handed to set_std_mode
mode_for() {
  (
    VERBOSE="" STD_MODE_SET=""
    _cs_ask_update_mode >/dev/null <<<"$1"
    echo "${STD_MODE_SET:-unset}"
  )
}

expect "2 selects verbose" yes "$(mode_for 2)"
expect "1 selects silent" no "$(mode_for 1)"
expect "enter defaults to silent" no "$(mode_for "")"
expect "nonsense defaults to silent" no "$(mode_for x)"
expect "3 cancels" 1 "$( (_cs_ask_update_mode <<<"3") | grep -c cancelled)"
expect "the options are shown" 3 "$( (_cs_ask_update_mode <<<"") | grep -cE '^  [123][)]')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
