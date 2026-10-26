#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
eval "$(awk '/^confirm_external_installer\(\) \{/,/^}/' "$CORE_DIR/core/core.func")"

msg_warn() { :; }
msg_custom() { :; }
msg_error() { echo "$*" >&2; }
# shellcheck disable=SC2034  # read by the eval'd helper
TAB3="" GATEWAY="" BGN="" CL=""
passed=0 failed=0

check() {
  if [[ "$3" == "$2" ]]; then
    echo "PASS $1"
    passed=$((passed + 1))
  else
    echo "FAIL $1: expected <$2>, got <$3>" >&2
    failed=$((failed + 1))
  fi
}
# exit code of one call; $1 is var_external_installer, $2 what the user types
run() {
  local rc=0
  (var_external_installer="$1" confirm_external_installer src url) <<<"$2" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
# no stdin at all, as in an unattended run without the variable
run_eof() {
  local rc=0
  (var_external_installer="" confirm_external_installer src url) </dev/null >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

check "var yes" 0 "$(run yes "")"
check "var YES" 0 "$(run YES "")"
check "var true" 0 "$(run true "")"
check "var no" 254 "$(run no "y")"
check "var wins over input" 254 "$(run no "yes")"
check "typed y" 0 "$(run "" y)"
check "typed Yes" 0 "$(run "" Yes)"
check "typed n" 254 "$(run "" n)"
check "just enter" 254 "$(run "" "")"
check "no stdin" 254 "$(run_eof)"

# what the message says; $1 is var_external_installer, $2 what the user types
said() {
  (var_external_installer="$1" confirm_external_installer src url) <<<"$2" 2>&1 >/dev/null || true
}
check "declining via the variable names the variable" 1 "$(said no "" | grep -c 'var_external_installer=no')"
check "declining at the prompt is a user abort" 1 "$(said "" n | grep -c 'Aborted by user')"

printf '%s passed, %s failed\n' "$passed" "$failed"
((failed == 0))
